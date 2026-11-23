import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeroinfra/core/emergency_codec.dart';
import 'package:zeroinfra/data/ble/mesh_transport.dart';
import 'package:zeroinfra/data/meshtastic/emergency_policy.dart';
import 'package:zeroinfra/data/meshtastic/meshtastic_client.dart';
import 'package:zeroinfra/generated/meshtastic/channel.pb.dart' as pb;
import 'package:zeroinfra/generated/meshtastic/config.pb.dart' as pb;
import 'package:zeroinfra/generated/meshtastic/mesh.pb.dart' as pb;
import 'package:zeroinfra/generated/meshtastic/portnums.pbenum.dart' as pb;
import 'package:zeroinfra/generated/meshtastic/telemetry.pb.dart' as pb;
import 'package:zeroinfra/models/connection_status.dart';
import 'package:zeroinfra/models/discovered_device.dart';
import 'package:zeroinfra/models/emergency_alert.dart';
import 'package:zeroinfra/models/mesh_message.dart';

const int _me = 0x00000001;
const int _other = 0x00000002;
const int _broadcast = 0xFFFFFFFF;

// Nodo de mentira: guarda lo que el cliente escribe y contesta a
// want_config_id con la configuración preparada en [configPackets].
class FakeTransport implements MeshTransport {
  // sync: los eventos llegan al cliente en el mismo `add`, sin esperas.
  final _fromRadio = StreamController<List<int>>.broadcast(sync: true);
  final _link = StreamController<bool>.broadcast(sync: true);
  final List<pb.FromRadio> _mailbox = [];

  final List<pb.ToRadio> written = [];
  List<pb.FromRadio> configPackets = [];
  bool answerConfig = true;

  // Un paquete que llega «en vivo» desde la malla.
  void push(pb.FromRadio message) => _fromRadio.add(message.writeToBuffer());

  void dropLink() => _link.add(false);

  @override
  Stream<List<DiscoveredDevice>> get scanResults => const Stream.empty();

  @override
  Stream<bool> get isScanning => const Stream.empty();

  @override
  Future<void> startScan() async {}

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connect(String deviceId) async => _link.add(true);

  @override
  Future<void> disconnect() async => _link.add(false);

  @override
  Stream<bool> get linkState => _link.stream;

  @override
  Stream<List<int>> get fromRadioStream => _fromRadio.stream;

  @override
  Future<void> writeToRadio(List<int> bytes) async {
    final message = pb.ToRadio.fromBuffer(bytes);
    written.add(message);
    if (message.hasWantConfigId() && answerConfig) {
      _mailbox
        ..addAll(configPackets)
        ..add(pb.FromRadio(configCompleteId: message.wantConfigId));
    }
  }

  @override
  Future<void> drainFromRadio() async {
    while (_mailbox.isNotEmpty) {
      _fromRadio.add(_mailbox.removeAt(0).writeToBuffer());
    }
  }

  @override
  Future<void> dispose() async {
    await _fromRadio.close();
    await _link.close();
  }
}

// Deja que se entreguen los eventos pendientes de los streams.
Future<void> settle() => Future<void>.delayed(Duration.zero);

pb.FromRadio textPacket(String text, {int from = _other, int to = _broadcast}) {
  return pb.FromRadio(
    packet: pb.MeshPacket(
      from: from,
      to: to,
      id: 77,
      decoded: pb.Data(
        portnum: pb.PortNum.TEXT_MESSAGE_APP,
        payload: utf8.encode(text),
      ),
    ),
  );
}

pb.FromRadio routingPacket(int requestId, pb.Routing_Error error) {
  return pb.FromRadio(
    packet: pb.MeshPacket(
      from: _me,
      to: _me,
      decoded: pb.Data(
        portnum: pb.PortNum.ROUTING_APP,
        requestId: requestId,
        payload: pb.Routing(errorReason: error).writeToBuffer(),
      ),
    ),
  );
}

pb.FromRadio positionPacket(int from, int latitudeI, int longitudeI) {
  return pb.FromRadio(
    packet: pb.MeshPacket(
      from: from,
      to: _broadcast,
      id: 55,
      decoded: pb.Data(
        portnum: pb.PortNum.POSITION_APP,
        payload: pb.Position(
          latitudeI: latitudeI,
          longitudeI: longitudeI,
        ).writeToBuffer(),
      ),
    ),
  );
}

// Un EMG1 que llega de la malla; [signed] es lo que pone el firmware en
// xeddsa_signed tras verificar la firma.
pb.FromRadio emgPacket(
  EmgMessage emg, {
  int from = _other,
  int id = 90,
  bool signed = true,
}) {
  return pb.FromRadio(
    packet: pb.MeshPacket(
      from: from,
      to: _broadcast,
      id: id,
      xeddsaSigned: signed,
      decoded: pb.Data(
        portnum: pb.PortNum.PRIVATE_APP,
        payload: EmgCodec.encode(emg),
      ),
    ),
  );
}

EmgMessage emg(
  EmgKind kind, {
  int origin = _other,
  int id = 1234,
  int expiresUnix = 0,
  String text = '@41.50000,2.50000 SOS',
}) {
  return EmgMessage(
    kind: kind,
    severity: 3,
    flags: 0,
    id: id,
    expiresUnix: expiresUnix,
    originNode: origin,
    text: kind == EmgKind.resolved ? '' : text,
  );
}

void main() {
  late FakeTransport transport;
  late MeshtasticClient client;

  setUp(() {
    transport = FakeTransport()
      ..configPackets = [
        pb.FromRadio(myInfo: pb.MyNodeInfo(myNodeNum: _me)),
        pb.FromRadio(
          nodeInfo: pb.NodeInfo(
            num: _me,
            user: pb.User(longName: 'Mi nodo', shortName: 'YO'),
          ),
        ),
        pb.FromRadio(
          nodeInfo: pb.NodeInfo(
            num: _other,
            user: pb.User(longName: 'Vecino', shortName: 'VE'),
            position: pb.Position(latitudeI: 413887900, longitudeI: 21129600),
            deviceMetrics: pb.DeviceMetrics(batteryLevel: 88),
          ),
        ),
        pb.FromRadio(
          config: pb.Config(lora: pb.Config_LoRaConfig(hopLimit: 5)),
        ),
        pb.FromRadio(
          channel: pb.Channel(index: 0, role: pb.Channel_Role.PRIMARY),
        ),
        pb.FromRadio(
          channel: pb.Channel(
            index: 1,
            role: pb.Channel_Role.SECONDARY,
            settings: pb.ChannelSettings(name: 'Rescate'),
          ),
        ),
        pb.FromRadio(
          channel: pb.Channel(index: 2, role: pb.Channel_Role.DISABLED),
        ),
      ];
    client = MeshtasticClient(
      transport,
      configTimeout: const Duration(milliseconds: 200),
    );
  });

  tearDown(() => client.dispose());

  test('connect descarga nodos y canales y queda conectado', () async {
    await client.connect('nodo');

    expect(client.status, ConnectionStatus.connected);
    expect(client.myNodeNum, _me);
    expect(transport.written.single.hasWantConfigId(), isTrue);

    expect(client.nodes, hasLength(2));
    final me = client.nodes.firstWhere((n) => n.nodeNum == _me);
    expect(me.isMe, isTrue);
    expect(me.hasPosition, isFalse);

    final other = client.nodes.firstWhere((n) => n.nodeNum == _other);
    expect(other.name, 'Vecino');
    expect(other.id, '!00000002');
    expect(other.latitude, closeTo(41.38879, 1e-5));
    expect(other.longitude, closeTo(2.11296, 1e-5));
    expect(other.hasPosition, isTrue);
    expect(other.hasBattery, isTrue);
    expect(other.batteryLevel, 88);

    // El canal deshabilitado no se expone.
    expect(client.channels.map((c) => c.index), [0, 1]);
    expect(client.channels.last.name, 'Rescate');
  });

  test('si el nodo no completa la configuración, connect falla', () async {
    transport.answerConfig = false;

    await expectLater(
      client.connect('nodo'),
      throwsA(isA<TimeoutException>()),
    );
    expect(client.status, ConnectionStatus.disconnected);
  });

  test('un texto de otro nodo se publica como mensaje recibido', () async {
    await client.connect('nodo');
    final received = <MeshMessage>[];
    final sub = client.messages.listen(received.add);

    transport.push(textPacket('hola'));
    await settle();

    expect(received, hasLength(1));
    expect(received.single.content, 'hola');
    expect(received.single.senderNum, _other);
    expect(received.single.senderName, 'Vecino');
    expect(received.single.isDirect, isFalse);
    expect(received.single.recipientId, MeshMessage.broadcastId);
    expect(received.single.status, MessageStatus.ack);
    await sub.cancel();
  });

  test('sendText escribe el paquete y sigue su entrega hasta el acuse',
      () async {
    await client.connect('nodo');
    final statuses = <MessageStatus>[];
    final sub = client.messages.listen((m) => statuses.add(m.status));

    final sent = await client.sendText('prueba');
    expect(sent.status, MessageStatus.transmitted);

    final packet = transport.written.last.packet;
    expect(packet.to, _broadcast);
    expect(packet.wantAck, isTrue);
    // hop_limit tomado de la configuración LoRa del nodo.
    expect(packet.hopLimit, 5);
    expect(packet.decoded.portnum, pb.PortNum.TEXT_MESSAGE_APP);
    expect(utf8.decode(packet.decoded.payload), 'prueba');
    expect(packet.id, sent.packetId);

    transport.push(routingPacket(packet.id, pb.Routing_Error.NONE));
    await settle();

    expect(statuses, [
      MessageStatus.queued,
      MessageStatus.transmitted,
      MessageStatus.ack,
    ]);
    await sub.cancel();
  });

  test('un error de routing marca el mensaje como fallido', () async {
    await client.connect('nodo');
    final statuses = <MessageStatus>[];
    final sub = client.messages.listen((m) => statuses.add(m.status));

    final sent = await client.sendText('prueba', toNode: _other);
    transport.push(
      routingPacket(sent.packetId, pb.Routing_Error.MAX_RETRANSMIT),
    );
    await settle();

    expect(statuses.last, MessageStatus.failed);
    await sub.cancel();
  });

  test('sendSos difunde un EMG1 ALERT con la posición propia', () async {
    await client.connect('nodo');
    transport.push(positionPacket(_me, 413887900, 21129600));
    await settle();

    final sent = await client.sendSos();
    expect(sent.isSos, isTrue);
    expect(sent.content, 'SOS · 41.38879, 2.11296');

    final packet = transport.written.last.packet;
    expect(packet.to, _broadcast);
    expect(packet.channel, EmergencyPolicy.channel);
    expect(packet.decoded.portnum, pb.PortNum.PRIVATE_APP);
    expect(packet.priority, EmergencyPolicy.priority);
    expect(packet.hopLimit, EmergencyPolicy.hopLimit);

    final alert = EmgCodec.decode(packet.decoded.payload);
    expect(alert.kind, EmgKind.alert);
    expect(alert.originNode, _me);
    expect(alert.id, isNot(0));
    expect(alert.severity, EmergencyPolicy.severity);
    expect(alert.flags, 0);
    expect(alert.text, '@41.38879,2.11296 SOS');
    expect(client.nodes.firstWhere((n) => n.isMe).isEmergency, isTrue);
  });

  test('cancelSos envía RESOLVED con el id del SOS y no se repite',
      () async {
    await client.connect('nodo');
    await client.sendSos();
    final alertId =
        EmgCodec.decode(transport.written.last.packet.decoded.payload).id;

    await client.cancelSos();

    final resolved =
        EmgCodec.decode(transport.written.last.packet.decoded.payload);
    expect(resolved.kind, EmgKind.resolved);
    expect(resolved.id, alertId);
    expect(resolved.originNode, _me);
    expect(client.nodes.firstWhere((n) => n.isMe).isEmergency, isFalse);
    // Ya no queda ningún SOS que cancelar.
    await expectLater(client.cancelSos(), throwsStateError);
  });

  test('el SOS propio sigue activo tras reconectar con el mismo nodo',
      () async {
    await client.connect('nodo');
    await client.sendSos();

    transport.dropLink();
    await client.connect('nodo');

    expect(client.nodes.firstWhere((n) => n.isMe).isEmergency, isTrue);
    await client.cancelSos();
    expect(client.nodes.firstWhere((n) => n.isMe).isEmergency, isFalse);
  });

  test('un ALERT recibido marca el nodo y publica la alerta', () async {
    await client.connect('nodo');
    final alerts = <EmergencyAlert>[];
    final messages = <MeshMessage>[];
    final subs = [
      client.alerts.listen(alerts.add),
      client.messages.listen(messages.add),
    ];

    transport.push(emgPacket(emg(EmgKind.alert)));
    await settle();

    final other = client.nodes.firstWhere((n) => n.nodeNum == _other);
    expect(other.isEmergency, isTrue);
    expect(other.latitude, closeTo(41.5, 1e-6));
    expect(other.longitude, closeTo(2.5, 1e-6));

    final alert = alerts.single;
    expect(alert.originNode, _other);
    expect(alert.id, 1234);
    expect(alert.text, 'SOS');
    expect(alert.isVerified, isTrue);
    expect(alert.latitude, closeTo(41.5, 1e-6));
    expect(client.activeAlerts, [alert]);

    expect(messages.single.isSos, isTrue);
    expect(messages.single.content, 'SOS · 41.50000, 2.50000');
    for (final sub in subs) {
      await sub.cancel();
    }
  });

  test('un RESOLVED cancela la alerta y quita la emergencia', () async {
    await client.connect('nodo');
    final alerts = <EmergencyAlert>[];
    final sub = client.alerts.listen(alerts.add);

    transport.push(emgPacket(emg(EmgKind.alert)));
    transport.push(emgPacket(emg(EmgKind.resolved), id: 91));
    await settle();

    expect(client.activeAlerts, isEmpty);
    expect(alerts.last.status, EmergencyDeliveryStatus.resolved);
    final other = client.nodes.firstWhere((n) => n.nodeNum == _other);
    expect(other.isEmergency, isFalse);
    await sub.cancel();
  });

  test('se descartan origen falso, repetidos, caducados y no EMG1',
      () async {
    await client.connect('nodo');
    final alerts = <EmergencyAlert>[];
    final sub = client.alerts.listen(alerts.add);

    // El paquete lo envía 0x03, pero dice venir de _other.
    transport.push(emgPacket(emg(EmgKind.alert, id: 1), from: 0x03));
    // La misma alerta por dos caminos (dos paquetes distintos).
    transport.push(emgPacket(emg(EmgKind.alert, id: 2), id: 100));
    transport.push(emgPacket(emg(EmgKind.alert, id: 2), id: 101));
    // Caducó en 1970.
    transport.push(emgPacket(emg(EmgKind.alert, id: 3, expiresUnix: 1)));
    // Bytes por PRIVATE_APP que no son EMG1.
    transport.push(
      pb.FromRadio(
        packet: pb.MeshPacket(
          from: _other,
          to: _broadcast,
          decoded: pb.Data(
            portnum: pb.PortNum.PRIVATE_APP,
            payload: [1, 2, 3],
          ),
        ),
      ),
    );
    await settle();

    expect(alerts.map((a) => a.id), [2]);
    expect(client.activeAlerts, hasLength(1));
    await sub.cancel();
  });

  test('sin firma verificada la alerta queda como no verificada', () async {
    await client.connect('nodo');
    final messages = <MeshMessage>[];
    final sub = client.messages.listen(messages.add);

    transport.push(emgPacket(emg(EmgKind.alert), signed: false));
    // Un REPLAY lo reenvía otro nodo: tampoco cuenta como verificado.
    transport.push(
      emgPacket(emg(EmgKind.replay, origin: 0x09, id: 7), id: 92),
    );
    await settle();

    expect(client.activeAlerts.map((a) => a.isVerified), [false, false]);
    expect(client.activeAlerts.last.isReplay, isTrue);
    expect(messages.first.content, contains('no verificada'));
    await sub.cancel();
  });

  test('sin conexión no se puede enviar', () {
    expect(client.sendText('hola'), throwsStateError);
  });

  test('al perderse el enlace el cliente queda desconectado', () async {
    await client.connect('nodo');

    transport.dropLink();

    expect(client.status, ConnectionStatus.disconnected);
    expect(client.sendText('hola'), throwsStateError);
  });
}
