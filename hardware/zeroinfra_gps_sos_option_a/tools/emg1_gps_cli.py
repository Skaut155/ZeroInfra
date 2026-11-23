#!/usr/bin/env python3
"""Herramienta autónoma EMG1 v1 con GPS en el TEXTO del mismo SOS.

Usos:
  python3 emg1_gps_cli.py --origin 0x82e09b4e --lat 41.38879 --lon 2.11296
  python3 emg1_gps_cli.py --port /dev/ttyACM0 --origin 0x82e09b4e --lat 41.38879 --lon 2.11296 --send
  python3 emg1_gps_cli.py --port /dev/ttyACM1 --listen
El envío es explícito mediante --send, y no se duplica por TEXT_MESSAGE_APP.
"""
import argparse
import math
import re
import secrets
import struct

MAGIC = b'EMG1'
HEADER = struct.Struct('<4sBBBBIII')
MAX_EMG_TEXT_BYTES = 160
SOFT_SIGNED_BUDGET = 120  # presupuesto, NO garantía de firma
COORDS = re.compile(r'^@(-?\d{1,3}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)(?:\s+|$)')


def build_text(body, lat=None, lon=None):
    if (lat is None) != (lon is None):
        raise ValueError('--lat y --lon deben indicarse juntos')
    prefix = ''
    if lat is not None:
        if not math.isfinite(lat) or not math.isfinite(lon) or abs(lat) > 90 or abs(lon) > 180:
            raise ValueError('Latitud/longitud fuera de rango')
        prefix = f'@{lat:.5f},{lon:.5f} '
    body = body if body.strip() else 'SOS'
    # Límite conservador para proteger la posibilidad de firma: no bloquear el SOS.
    text = prefix + body
    if len(text.encode('utf-8')) <= SOFT_SIGNED_BUDGET:
        return text
    output = prefix
    for char in body:
        if len((output + char).encode('utf8')) > SOFT_SIGNED_BUDGET:
            break
        output += char
    return output


def parse_position(text):
    match = COORDS.match(text)
    if not match:
        return None, text
    lat, lon = float(match.group(1)), float(match.group(2))
    if not (math.isfinite(lat) and math.isfinite(lon) and abs(lat) <= 90 and abs(lon) <= 180):
        return None, text
    return (lat, lon), text[match.end():].strip()


def encode_alert(origin, alert_id, severity, text):
    payload = text.encode('utf8')
    if not 1 <= severity <= 3 or not (0 < origin <= 0xffffffff) or not (0 < alert_id <= 0xffffffff):
        raise ValueError('Gravedad, origin o id inválidos')
    if not payload or len(payload) > MAX_EMG_TEXT_BYTES:
        raise ValueError('Texto EMG1 supera 160 bytes o está vacío')
    # kind=1 ALERT, flags=0, expiresUnix=0 (sin caducidad)
    return HEADER.pack(MAGIC, 1, 1, severity, 0, alert_id, 0, origin) + payload


def decode_alert(data):
    if len(data) < HEADER.size or len(data) > HEADER.size + MAX_EMG_TEXT_BYTES:
        return None
    magic, version, kind, severity, flags, aid, expires, origin = HEADER.unpack_from(data)
    if magic != MAGIC or version != 1 or kind != 1 or severity not in (1, 2, 3) or flags or not aid or not origin:
        return None
    try:
        text = data[HEADER.size:].decode('utf8')
    except UnicodeError:
        return None
    position, body = parse_position(text)
    return {'kind': 'ALERT', 'severity': severity, 'id': f'0x{aid:08x}',
            'origin': f'!{origin:08x}', 'text': text, 'body': body,
            'position': position, 'expires': expires}


def listen(port):
    try:
        from meshtastic.serial_interface import SerialInterface
        from pubsub import pub
    except ImportError as exc:
        raise SystemExit(f'Falta dependencia: {exc}. Instala meshtastic y pypubsub en el mismo entorno Python.')
    def on_receive(packet, interface):
        data = packet.get('decoded', {})
        if data.get('portnum') not in ('PRIVATE_APP', 256):
            return
        msg = decode_alert(data.get('payload', b''))
        if msg is not None:
            print('EMG1_RX', msg, 'mesh_from=', packet.get('fromId', packet.get('from')),
                  'mesh_id=', packet.get('id'), flush=True)
    pub.subscribe(on_receive, 'meshtastic.receive')
    with SerialInterface(port):
        print('Escuchando alertas EMG1 en', port, flush=True)
        try:
            import time
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', default='/dev/ttyACM0')
    ap.add_argument('--origin', type=lambda s: int(s, 0), help='NodeNum real de la T-Beam emisora, p.ej. 0x82e09b4e')
    ap.add_argument('--lat', type=float, help='Latitud GPS de prueba')
    ap.add_argument('--lon', type=float, help='Longitud GPS de prueba')
    ap.add_argument('--text', default='SOS', help='Texto del SOS')
    ap.add_argument('--severity', type=int, choices=(1, 2, 3), default=3)
    ap.add_argument('--id', dest='alert_id', type=lambda s: int(s, 0))
    ap.add_argument('--destination', default='^all')
    ap.add_argument('--channel-index', type=int, choices=range(8), default=0)
    ap.add_argument('--listen', action='store_true')
    ap.add_argument('--send', action='store_true', help='Enviar de verdad; sin --send solo muestra bytes')
    args = ap.parse_args()
    if args.listen:
        if args.send:
            ap.error('--listen y --send son incompatibles')
        listen(args.port)
        return
    if args.origin is None:
        ap.error('Necesitas --origin (NodeNum verdadero de la placa emisora)')
    if args.destination != '^all':
        ap.error('Esta herramienta de prueba solo emite SOS broadcast para facilitar la firma y el relay; no usa unicast')
    try:
        text = build_text(args.text, args.lat, args.lon)
        alert_id = args.alert_id if args.alert_id is not None else (secrets.randbits(32) or 1)
        frame = encode_alert(args.origin, alert_id, args.severity, text)
    except ValueError as exc:
        ap.error(str(exc))
    print('EMG1_TX', decode_alert(frame))
    print(f'EMG1 bytes={len(frame)}; texto UTF-8={len(text.encode("utf8"))}; frame hex={frame.hex()}')
    print('Longitud total por radio y presencia de firma: solo se comprueban en logs del firmware; no se garantizan aquí.')
    if not args.send:
        print('DRY-RUN: no se ha enviado nada. Añade --send para transmitir.')
        return
    try:
        from meshtastic.serial_interface import SerialInterface
        from meshtastic.protobuf import portnums_pb2
    except ImportError as exc:
        raise SystemExit(f'Falta dependencia: {exc}. Instala meshtastic y pypubsub.')
    with SerialInterface(args.port) as iface:
        iface.sendData(frame, destinationId=args.destination,
                       portNum=portnums_pb2.PortNum.PRIVATE_APP,
                       wantAck=False, channelIndex=args.channel_index)
        print('Enviado a la API serie local. Comprueba RX/TX y firma en la otra placa.')


if __name__ == '__main__':
    main()
