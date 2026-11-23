import 'package:flutter_test/flutter_test.dart';
import 'package:zeroinfra/core/emergency_codec.dart';
import 'package:zeroinfra/data/meshtastic/emergency_policy.dart';

void main() {
  test('la posición va al principio del texto con 5 decimales', () {
    expect(
      EmergencyText.encode(latitude: 41.388791, longitude: 2.112964),
      '@41.38879,2.11296 SOS',
    );
    expect(EmergencyText.encode(), 'SOS');
    // Sin una de las dos coordenadas no se escribe ninguna.
    expect(EmergencyText.encode(latitude: 41.5), 'SOS');
  });

  test('se leen la posición y el texto de un ALERT', () {
    const text = '@-33.45000,-70.66670 Atrapado en el edificio';
    final position = EmergencyText.position(text)!;
    expect(position.latitude, closeTo(-33.45, 1e-9));
    expect(position.longitude, closeTo(-70.6667, 1e-9));
    expect(EmergencyText.body(text), 'Atrapado en el edificio');

    expect(EmergencyText.position('SOS'), isNull);
    expect(EmergencyText.body('SOS'), 'SOS');
    // Fuera de rango o mal formada: se trata como texto sin posición.
    expect(EmergencyText.position('@95.0,2.0 SOS'), isNull);
    expect(EmergencyText.position('@41.5;2.5 SOS'), isNull);
  });

  test('el texto de un SOS cabe en EMG1 y vuelve igual', () {
    final text = EmergencyText.encode(latitude: -89.99999, longitude: -179.9);
    final bytes = EmgCodec.encode(
      EmgMessage(
        kind: EmgKind.alert,
        severity: EmergencyPolicy.severity,
        flags: 0,
        id: 42,
        expiresUnix: EmergencyPolicy.expiresUnix,
        originNode: 0x1a21fd32,
        text: text,
      ),
    );
    expect(bytes.length, lessThan(EmgCodec.headerSize + 40));
    expect(EmgCodec.decode(bytes).text, text);
  });

  test('describe da un texto legible para el chat', () {
    expect(
      EmergencyText.describe(
        kind: EmgKind.alert,
        body: 'SOS',
        latitude: 41.5,
        longitude: 2.5,
      ),
      'SOS · 41.50000, 2.50000',
    );
    expect(
      EmergencyText.describe(kind: EmgKind.alert, verified: false),
      'SOS · no verificada',
    );
    expect(EmergencyText.describe(kind: EmgKind.resolved), 'SOS cancelado');
  });
}
