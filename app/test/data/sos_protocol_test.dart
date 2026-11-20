import 'package:flutter_test/flutter_test.dart';
import 'package:zeroinfra/data/meshtastic/sos_protocol.dart';

void main() {
  test('una alerta con posición se codifica y se vuelve a leer', () {
    final text = SosCodec.encode(
      const SosSignal(
        kind: SosKind.alert,
        nodeNum: 0xa1b2c3d4,
        latitude: 41.38879,
        longitude: 2.11296,
      ),
    );
    expect(text, 'SOS|v1|!a1b2c3d4|41.38879|2.11296');

    final signal = SosCodec.tryDecode(text)!;
    expect(signal.kind, SosKind.alert);
    expect(signal.nodeNum, 0xa1b2c3d4);
    expect(signal.latitude, closeTo(41.38879, 1e-6));
    expect(signal.longitude, closeTo(2.11296, 1e-6));
  });

  test('una alerta sin GPS lleva la posición vacía', () {
    final text = SosCodec.encode(
      const SosSignal(kind: SosKind.alert, nodeNum: 1),
    );
    expect(text, 'SOS|v1|!00000001||');

    final signal = SosCodec.tryDecode(text)!;
    expect(signal.latitude, isNull);
    expect(signal.longitude, isNull);
  });

  test('la cancelación se distingue de la alerta', () {
    final text = SosCodec.encode(
      const SosSignal(kind: SosKind.cancel, nodeNum: 0xa1b2c3d4),
    );
    expect(text, 'SOS|v1|!a1b2c3d4|CANCEL');
    expect(SosCodec.tryDecode(text)!.kind, SosKind.cancel);
  });

  test('un texto normal no es un SOS', () {
    expect(SosCodec.tryDecode('hola'), isNull);
    expect(SosCodec.tryDecode('SOS, necesito ayuda'), isNull);
    expect(SosCodec.tryDecode('SOS|v2|!a1b2c3d4|1|2'), isNull);
    expect(SosCodec.tryDecode('SOS|v1|a1b2c3d4|1|2'), isNull);
  });
}
