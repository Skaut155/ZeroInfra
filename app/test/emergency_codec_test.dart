import 'package:flutter_test/flutter_test.dart';

import '../lib/core/emergency_codec.dart';

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Vectores oficiales EMG1 v1 (Python CLI parity)', () {
    test('ALERT genera exactamente el mismo binario que Python', () {
      const input = EmgMessage(
        kind: EmgKind.alert,
        severity: 3,
        flags: 1,
        id: 0x448f9b82,
        expiresUnix: 0x6afa1baa,
        originNode: 0x1a21fd32,
        text: 'Alerta de',
      );
      final actual = EmgCodec.encode(input);
      expect(
        toHex(actual),
        '454d473101010301829b8f44aa1bfa6a32fd211a416c65727461206465',
      );
      final decoded = EmgCodec.decode(actual);
      expect(decoded.kind, EmgKind.alert);
      expect(decoded.severity, 3);
      expect(decoded.flags, 1);
      expect(decoded.id, input.id);
      expect(decoded.originNode, input.originNode);
      expect(decoded.text, 'Alerta de');
    });

    test('RECEIPT genera exactamente 20 bytes sin texto', () {
      const input = EmgMessage(
        kind: EmgKind.receipt,
        severity: 0,
        flags: 0,
        id: 0x448f9b82,
        expiresUnix: 0x6afa1baa,
        originNode: 0x1a21fd32,
      );
      expect(
        toHex(EmgCodec.encode(input)),
        '454d473101020000829b8f44aa1bfa6a32fd211a',
      );
    });

    test('FETCH de última alerta usa comodines en 0', () {
      const input = EmgMessage(
        kind: EmgKind.fetch,
        severity: 0,
        flags: 0,
        id: 0,
        expiresUnix: 0,
        originNode: 0,
      );
      expect(
        toHex(EmgCodec.encode(input)),
        '454d473101040000000000000000000000000000',
      );
    });

    test('RESOLVED sin texto genera vector exacto', () {
      const input = EmgMessage(
        kind: EmgKind.resolved,
        severity: 0,
        flags: 0,
        id: 0x448f9b82,
        expiresUnix: 0,
        originNode: 0x1a21fd32,
      );
      expect(
        toHex(EmgCodec.encode(input)),
        '454d473101030000829b8f440000000032fd211a',
      );
    });

    test('REPLAY conserva gravedad y texto', () {
      const input = EmgMessage(
        kind: EmgKind.replay,
        severity: 3,
        flags: 0,
        id: 0x448f9b82,
        expiresUnix: 0x6afa1baa,
        originNode: 0x1a21fd32,
        text: 'Alerta de',
      );
      expect(
        toHex(EmgCodec.encode(input)),
        '454d473101050300829b8f44aa1bfa6a32fd211a416c65727461206465',
      );
    });

    test('Rechaza textos que superan 160 bytes UTF-8 con acentos', () {
      final input = EmgMessage(
        kind: EmgKind.alert,
        severity: 2,
        flags: 0,
        id: 1,
        expiresUnix: 0,
        originNode: 100,
        text: 'á' * 81,
      );
      expect(() => EmgCodec.encode(input), throwsFormatException);
    });
  });
}
