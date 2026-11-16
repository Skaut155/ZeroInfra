import 'dart:convert';
import 'dart:typed_data';

enum EmgKind { alert, receipt, resolved, fetch, replay }

class EmgMessage {
  final EmgKind kind;
  final int severity;
  final int flags;
  final int id;
  final int expiresUnix;
  final int originNode;
  final String text;

  const EmgMessage({
    required this.kind,
    required this.severity,
    required this.flags,
    required this.id,
    required this.expiresUnix,
    required this.originNode,
    this.text = '',
  });
}

class EmgCodec {
  static const headerSize = 20;
  static const maxTextBytes = 160;
  static const maxUint32 = 0xffffffff;

  static Uint8List encode(EmgMessage message) {
    final text = utf8.encode(message.text);
    _validate(message, text.length);

    final result = Uint8List(headerSize + text.length);
    final data = ByteData.sublistView(result);
    result.setRange(0, 4, [0x45, 0x4d, 0x47, 0x31]);
    result[4] = 1;
    result[5] = message.kind.index + 1;
    result[6] = message.severity;
    result[7] = message.flags;
    data.setUint32(8, message.id, Endian.little);
    data.setUint32(12, message.expiresUnix, Endian.little);
    data.setUint32(16, message.originNode, Endian.little);
    result.setRange(headerSize, result.length, text);
    return result;
  }

  static EmgMessage decode(List<int> input) {
    if (input.length < headerSize || input.length > headerSize + maxTextBytes) {
      throw const FormatException('Longitud EMG1 incorrecta');
    }

    final bytes = Uint8List.fromList(input);
    if (bytes[0] != 0x45 ||
        bytes[1] != 0x4d ||
        bytes[2] != 0x47 ||
        bytes[3] != 0x31 ||
        bytes[4] != 1) {
      throw const FormatException('Magic o versión EMG1 incorrectos');
    }
    if (bytes[5] < 1 || bytes[5] > 5) {
      throw const FormatException('Tipo EMG1 desconocido');
    }

    final data = ByteData.sublistView(bytes);
    final message = EmgMessage(
      kind: EmgKind.values[bytes[5] - 1],
      severity: bytes[6],
      flags: bytes[7],
      id: data.getUint32(8, Endian.little),
      expiresUnix: data.getUint32(12, Endian.little),
      originNode: data.getUint32(16, Endian.little),
      text: utf8.decode(bytes.sublist(headerSize)),
    );
    _validate(message, bytes.length - headerSize);
    return message;
  }

  static void _validate(EmgMessage message, int textLength) {
    if (textLength > maxTextBytes ||
        message.severity < 0 ||
        message.severity > 3 ||
        message.flags < 0 ||
        message.flags > 1) {
      throw const FormatException('Gravedad, flags o longitud inválidos');
    }
    for (final number in [
      message.id,
      message.expiresUnix,
      message.originNode,
    ]) {
      if (number < 0 || number > maxUint32) {
        throw const FormatException('Campo uint32 fuera de rango');
      }
    }
    if (message.kind != EmgKind.fetch &&
        (message.id == 0 || message.originNode == 0)) {
      throw const FormatException('ID u origen inválido');
    }
    if (message.kind != EmgKind.alert && message.flags != 0) {
      throw const FormatException('Flags no permitidos para este tipo');
    }
    if ((message.kind == EmgKind.receipt || message.kind == EmgKind.fetch) &&
        textLength != 0) {
      throw const FormatException('Este mensaje no admite texto');
    }
    if ((message.kind == EmgKind.alert || message.kind == EmgKind.replay) &&
        (textLength == 0 || message.severity == 0)) {
      throw const FormatException('ALERT/REPLAY sin gravedad o texto');
    }
  }
}
