import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeroinfra/core/emergency_codec.dart';
import 'package:zeroinfra/data/meshtastic/emergency_policy.dart';

void main() {
  test('SOS mantiene GPS dentro del mismo EMG1 v1', () {
    final text = EmergencyText.encode(
      latitude: 41.388791,
      longitude: 2.112964,
      body: 'Necesito ayuda',
    );
    expect(text, '@41.38879,2.11296 Necesito ayuda');
    final frame = EmgCodec.encode(EmgMessage(
      kind: EmgKind.alert,
      severity: 3,
      flags: 0,
      id: 123,
      expiresUnix: 0,
      originNode: 0x82e09b4e,
      text: text,
    ));
    final decoded = EmgCodec.decode(frame);
    expect(decoded.text, text);
    expect(EmergencyText.position(decoded.text)?.latitude, closeTo(41.38879, 1e-5));
    expect(EmergencyText.body(decoded.text), 'Necesito ayuda');
  });

  test('sin GPS y coordenadas no válidas no bloquean el SOS', () {
    expect(EmergencyText.encode(), 'SOS');
    expect(EmergencyText.encode(latitude: 100, longitude: 2), 'SOS');
    expect(EmergencyText.encode(latitude: double.nan, longitude: 2), 'SOS');
    expect(EmergencyText.encode(latitude: 41.5), 'SOS');
    expect(EmergencyText.encode(latitude: 41.5, longitude: double.infinity), 'SOS');
  });

  test('texto largo no rompe Unicode ni rebasa el presupuesto orientativo', () {
    final text = EmergencyText.encode(
      latitude: -89.99999,
      longitude: -179.99999,
      body: List.filled(80, '🆘').join(),
    );
    expect(utf8.encode(text).length, lessThanOrEqualTo(EmergencyPolicy.maxSignedSosTextBytes));
    expect(EmergencyText.position(text), isNotNull);
    expect(utf8.decode(utf8.encode(text)), text);
    expect(EmgCodec.encode(EmgMessage(
      kind: EmgKind.alert,
      severity: 3,
      flags: 0,
      id: 44,
      expiresUnix: 0,
      originNode: 0x82e09b4e,
      text: text,
    )).length, lessThanOrEqualTo(20 + EmergencyPolicy.maxSignedSosTextBytes));
  });
}
