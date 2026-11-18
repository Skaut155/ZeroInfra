#!/usr/bin/env python3
"""User-side encoder/sender/monitor for experimental Meshtastic PRIVATE_APP=256.
No transmission occurs without the explicit --send flag.
"""
import argparse
import datetime
import secrets
import struct

MAGIC = b'EMG1'
HEADER = struct.Struct('<4sBBBBIII')
MAX_TEXT = 160
KINDS = {'alert': 1, 'receipt': 2, 'resolved': 3, 'fetch': 4, 'replay': 5}


def encode(kind, severity, flags, alert_id, expiry, origin, text=b''):
    if kind not in range(1, 6) or not 0 <= severity <= 3 or not 0 <= flags <= 1:
        raise ValueError('kind/severity/flags invalidos')
    if kind != 1 and flags or kind in (2,4) and text or kind in (1,5) and (not text or not severity):
        raise ValueError('Combinacion de tipo, flags y texto no valida')
    if kind != 4 and (not alert_id or not origin):
        raise ValueError('El ID y el origen son obligatorios salvo en FETCH')
    if not 0 <= alert_id <= 0xffffffff or not 0 <= origin <= 0xffffffff or len(text) > MAX_TEXT:
        raise ValueError('ID/origen/texto invalidos')
    return HEADER.pack(MAGIC, 1, kind, severity, flags, alert_id, expiry, origin) + text


def decode(data):
    if len(data) < HEADER.size or len(data) > HEADER.size+MAX_TEXT: return None
    magic,ver,kind,sev,flags,aid,expires,origin=HEADER.unpack_from(data)
    if magic != MAGIC or ver != 1 or kind not in range(1,6) or sev > 3 or flags & ~1:
        return None
    if kind != 1 and flags or kind in (2,4) and len(data) != HEADER.size:
        return None
    text=data[HEADER.size:]
    if kind != 4 and (not origin or not aid) or kind in (1,5) and (not text or not sev):
        return None
    return dict(kind=kind, severity=sev, id=aid, expiry=expires, origin=origin, text=text)


def main():
    ap=argparse.ArgumentParser(description='Protocolo experimental de alertas PRIVATE_APP=256')
    ap.add_argument('--port', default='/dev/ttyACM0', help='Puerto USB de la placa')
    ap.add_argument('--mode', choices=['alert','resolved','fetch'], default='alert')
    ap.add_argument('--origin', type=lambda s:int(s,0), help='NodeNum 32 bits del ORIGEN de la alerta, p.ej. 0x1234abcd')
    ap.add_argument('--destination', default='^all', help='^all o !xxxxxxxx de un nodo concreto')
    ap.add_argument('--severity', type=int, choices=[1,2,3], default=2)
    ap.add_argument('--text', default='Prueba de alerta de emergencia')
    ap.add_argument('--expires-minutes', type=int, default=15)
    ap.add_argument('--id', dest='alert_id', type=lambda s:int(s,0), default=None)
    ap.add_argument('--receipt', action='store_true', help='Recibo de aplicación, solo para alertas unicast')
    ap.add_argument('--send', action='store_true', help='Transmitir por LoRa, en lugar de solo mostrar el paquete')
    ap.add_argument('--mirror-chat', action='store_true',
                    help='Enviar tambien una copia TEXT_MESSAGE_APP visible en el chat de Meshtastic')
    ap.add_argument('--channel-index', type=int, choices=range(8), default=0,
                    metavar='{0..7}', help='Canal Meshtastic para ambos mensajes (por defecto: 0)')
    ap.add_argument('--listen', action='store_true', help='Escuchar y decodificar mensajes PRIVATE_APP')
    args=ap.parse_args()

    if args.listen:
        from pubsub import pub
        from meshtastic.serial_interface import SerialInterface
        def on_receive(packet, interface):
            decoded = packet.get('decoded', {})
            if decoded.get('portnum') not in ('PRIVATE_APP', 256): return
            msg=decode(decoded.get('payload', b''))
            if msg:
                print('EMERGENCY', {**msg, 'text':msg['text'].decode('utf-8','replace')}, flush=True)
        pub.subscribe(on_receive, 'meshtastic.receive')
        with SerialInterface(args.port):
            print('Escuchando', args.port)
            try:
                import time
                while True: time.sleep(1)
            except KeyboardInterrupt: pass
        return

    if args.mode != 'fetch' and args.origin is None:
        ap.error('--origin (NodeNum local) es obligatorio para ALERT y RESOLVED')
    if args.receipt and (args.mode != 'alert' or args.destination == '^all'):
        ap.error('Solo se permiten recibos de aplicación para ALERT unicast')
    if args.mode == 'fetch' and args.destination == '^all':
        ap.error('FETCH debe dirigirse en unicast a un nodo que pueda tener la alerta guardada')
    if args.mode == 'resolved' and not args.alert_id:
        ap.error('RESOLVED necesita --id de la alerta original')
    if args.mirror_chat and args.mode == 'fetch':
        ap.error('--mirror-chat solo tiene sentido con --mode alert o --mode resolved')

    kind = KINDS[args.mode]
    text = args.text.encode('utf-8') if kind != KINDS['fetch'] else b''
    expiry = 0 if args.expires_minutes <= 0 or kind == KINDS['fetch'] else int(
        (datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(minutes=args.expires_minutes)).timestamp())
    aid = (args.alert_id or (secrets.randbits(32) or 1)) if kind != KINDS['fetch'] else (args.alert_id or 0)
    origin = args.origin or 0
    frame=encode(kind, args.severity, int(args.receipt), aid, expiry, origin, text)
    print(f'MODE={args.mode}, ALERT_ID=0x{aid:08x}, bytes={len(frame)}, PRIVATE_APP=256, hex={frame.hex()}')
    if not args.send:
        print('SIN TRANSMISIÓN. Añade --send solo cuando quieras enviar realmente.')
        return
    # Un mensaje de texto no sustituye el paquete EMG1: es un duplicado legible.
    chat_text = None
    if args.mirror_chat:
        if args.mode == 'alert':
            chat_text = f'[ALERTA NIVEL {args.severity} | ID {aid:08x}] {args.text}'
        elif args.mode == 'resolved':
            chat_text = f'[ALERTA RESUELTA | ID {aid:08x}] {args.text}'
        # Evita enviar el primer paquete si el segundo no cabe en la trama.
        if len(chat_text.encode('utf-8')) > 220:
            ap.error('La copia para el chat es demasiado larga: limita el texto')
    from meshtastic.serial_interface import SerialInterface
    from meshtastic.protobuf import portnums_pb2
    with SerialInterface(args.port) as iface:
        iface.sendData(frame, destinationId=args.destination,
                       portNum=portnums_pb2.PortNum.PRIVATE_APP,
                       wantAck=args.destination != '^all',
                       channelIndex=args.channel_index)
        print('Paquete EMG1 enviado a la API local (PRIVATE_APP).')
        if chat_text is not None:
            iface.sendText(chat_text, destinationId=args.destination,
                           wantAck=args.destination != '^all',
                           channelIndex=args.channel_index)
            print('Copia enviada a la API local (TEXT_MESSAGE_APP).')
        print('La entrega por radio se verifica en el receptor; encolado no es entrega confirmada.')

if __name__=='__main__':
    main()
