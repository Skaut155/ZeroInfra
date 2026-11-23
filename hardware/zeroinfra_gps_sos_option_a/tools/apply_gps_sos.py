#!/usr/bin/env python3
"""Parche incremental y conservador sobre ZeroInfra: validación y tope del texto SOS EMG1.

NO cambia EmergencyWire.h, ni la estructura binaria, ni el routing.
No añade el envío del GPS desde cero: la rama pública ZeroInfra ya lo hace.
"""
import argparse
import difflib
import shutil
import sys
from pathlib import Path

LIMIT = 120
SOURCE = Path('app/lib/data/meshtastic/emergency_policy.dart')
CLIENT = Path('app/lib/data/meshtastic/meshtastic_client.dart')
TEST = Path('app/test/data/emergency_gps_patch_test.dart')

OLD_BLOCK = '''  static String encode({
    double? latitude,
    double? longitude,
    String body = EmergencyPolicy.text,
  }) {
    if (latitude == null || longitude == null) return body;
    final lat = latitude.toStringAsFixed(5);
    final lon = longitude.toStringAsFixed(5);
    return '@$lat,$lon $body';
  }'''

NEW_BLOCK = '''  static String encode({
    double? latitude,
    double? longitude,
    String body = EmergencyPolicy.text,
  }) {
    // Si falta una coordenada o los valores son inválidos, enviar el SOS
    // sin localización. El envío de una alerta nunca depende del GPS.
    final validPosition = latitude != null &&
        longitude != null &&
        latitude.isFinite &&
        longitude.isFinite &&
        latitude.abs() <= 90 &&
        longitude.abs() <= 180;
    final prefix = validPosition
        ? '@${latitude!.toStringAsFixed(5)},${longitude!.toStringAsFixed(5)} '
        : '';
    final text = body.trim().isEmpty ? EmergencyPolicy.text : body;
    final full = '$prefix$text';
    if (utf8.encode(full).length <= EmergencyPolicy.maxSignedSosTextBytes) {
      return full;
    }
    // Truncar por caracteres Unicode completos, no por bytes: nunca
    // generar UTF-8 corrupto ni bloquear el envío por un texto demasiado largo.
    var used = utf8.encode(prefix).length;
    final result = StringBuffer(prefix);
    for (final codePoint in text.runes) {
      final character = String.fromCharCode(codePoint);
      final bytes = utf8.encode(character).length;
      if (used + bytes > EmergencyPolicy.maxSignedSosTextBytes) break;
      result.write(character);
      used += bytes;
    }
    return result.toString();
  }'''

NEW_TEST = '''import 'dart:convert';

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
'''

def patch_source(src):
    if 'maxSignedSosTextBytes' in src and 'final validPosition = latitude != null' in src:
        return src  # Idempotente
    if 'maxSignedSosTextBytes' in src:
        raise ValueError('La política ya declara maxSignedSosTextBytes con otro código; revisar a mano')
    if src.count(OLD_BLOCK) != 1:
        raise ValueError('No encuentro la función EmergencyText.encode esperada; puede que la rama haya cambiado')
    const = "  static const String text = 'SOS';"
    if src.count(const) != 1:
        raise ValueError('No encuentro la constante EmergencyPolicy.text esperada')
    src = "import 'dart:convert';\n" + src if "import 'dart:convert';" not in src else src
    src = src.replace(const, const + '''
  /// Presupuesto conservador para facilitar firmas XEdDSA en broadcast.
  /// NO es una garantía de firma: depende de otros campos y del firmware.
  static const int maxSignedSosTextBytes = 120;''', 1)
    return src.replace(OLD_BLOCK, NEW_BLOCK, 1)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('repo', type=Path, help='Raíz de ZeroInfra (contiene app/)')
    ap.add_argument('--apply', action='store_true', help='Aplicar; sin esto solo comprueba y muestra diff')
    args = ap.parse_args()
    root = args.repo.expanduser().resolve()
    source, client, test = root / SOURCE, root / CLIENT, root / TEST
    if not source.is_file() or not client.is_file():
        ap.error('No encuentro app/lib/data/meshtastic/emergency_policy.dart y meshtastic_client.dart: usa la RAÍZ DE ZeroInfra, no el submódulo firmware')
    client_content = client.read_text(encoding='utf8')
    if not all(s in client_content for s in ('Future<MeshMessage> sendSos()', 'EmergencyText.encode(', 'latitude: fix?.latitude', 'longitude: fix?.longitude', 'portNum: EmergencyPolicy.portNum')):
        ap.error('Esta rama no coincide con el envío GPS+SOS ya implementado en ZeroInfra: abortando para no sobrescribir la integración de Flutter')
    before = source.read_text(encoding='utf8')
    try:
        after = patch_source(before)
    except ValueError as e:
        ap.error(str(e))
    current_test = test.read_text(encoding='utf8') if test.exists() else None
    if current_test not in (None, NEW_TEST):
        ap.error(f'{TEST} ya existe y no coincide; no se sobrescribirá')
    if before != after:
        print(''.join(difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True), fromfile=str(SOURCE), tofile=str(SOURCE))))
    else:
        print('El cambio de EmergencyText.encode ya está aplicado.')
    if current_test is None:
        print(f'+ Se creará {TEST}')
    print('COMPROBACIÓN OK.' if not args.apply else 'VALIDACIÓN OK.')
    if not args.apply:
        print('Para modificar archivos, repite con --apply')
        return
    if before != after:
        backup = source.with_suffix(source.suffix + '.gps_sos.bak')
        if not backup.exists():
            shutil.copy2(source, backup)
        source.write_text(after, encoding='utf8')
        print(f'Actualizado: {SOURCE}; copia: {backup.name}')
    if current_test is None:
        test.parent.mkdir(parents=True, exist_ok=True)
        test.write_text(NEW_TEST, encoding='utf8')
        print(f'Creado: {TEST}')
    print('PARCHE APLICADO. Ejecuta: cd app && dart format lib/data/meshtastic/emergency_policy.dart test/data/emergency_gps_patch_test.dart && flutter test')

if __name__ == '__main__':
    main()
