#!/usr/bin/env python3
"""Parche incremental OPEN-SOS para Meshtastic 2.8.2 + EMG1 v2 + per-hop.

Uso:
  python3 tools/apply_open_sos.py /ruta/al/firmware            # dry-run (no modifica)
  python3 tools/apply_open_sos.py /ruta/al/firmware --apply    # aplica

Elimina SOLO la allowlist de NodeNum para SOS. Conserva XEdDSA verificada
como requisito de prioridad en retransmisores, y conserva el aging intacto.
"""
from __future__ import annotations

import argparse
import difflib
import re
import shutil
import subprocess
import sys
from pathlib import Path

BACKUP_DIR = '.emergency_open_sos_backups'
SIGNATURE = 'EMERGENCY_ORIGIN_POLICY_OPEN_SOS_V1'


def replace_once(contents: str, old: str, new: str, context: str) -> str:
    count = contents.count(old)
    if count != 1:
        raise ValueError(f'{context}: esperaba un único anclaje, encuentro {count}: {old[:85]!r}')
    return contents.replace(old, new, 1)


def regex_once(contents: str, pattern: str, new: str, context: str) -> str:
    matches = list(re.finditer(pattern, contents, re.MULTILINE))
    if len(matches) != 1:
        raise ValueError(f'{context}: esperaba una coincidencia, encuentro {len(matches)}')
    m = matches[0]
    return contents[:m.start()] + new + contents[m.end():]


def patch_config(src: str) -> str:
    if SIGNATURE in src:
        raise ValueError('EmergencyConfig.h: OPEN-SOS parece ya aplicado')
    # La lista puede haber sido editada por el usuario; solo exigimos la declaración.
    pattern = r'^static\s+constexpr\s+uint32_t\s+EMERGENCY_AUTHORIZED_ORIGINS\s*\[\s*\]\s*=\s*\{[^{}]*\}\s*;[ \t]*\n'
    policy = '''// EMERGENCY_ORIGIN_POLICY_OPEN_SOS_V1
// Cualquier NodeNum legítimo puede originar un SOS. Esto NO autentica la identidad.
// En relays, la prioridad ALERT requiere adicionalmente una firma XEdDSA VERIFICADA.
namespace EmergencyOriginPolicy {
inline bool validNodeNum(uint32_t nodeNum)
{
    return nodeNum != 0U && nodeNum != UINT32_MAX;
}
} // namespace EmergencyOriginPolicy
'''
    src = regex_once(src, pattern, policy, 'EmergencyConfig.h allowlist')
    # Limpieza opcional de las tres notas originales; no elimina comentarios del usuario.
    obsolete_prefixes = ('// EDIT THIS LIST:', '// {0} means nobody', '// A whitelist protects')
    src = ''.join(line for line in src.splitlines(keepends=True)
                  if not line.lstrip().startswith(obsolete_prefixes))
    return src


def patch_emergency(src: str) -> str:
    original = '''    bool authorized(uint32_t from) const
    {
        for (uint32_t node : EMERGENCY_AUTHORIZED_ORIGINS) {
            if (node != 0 && from == node) return true;
        }
        return false;
    }
'''
    src = replace_once(src, original, '', 'Emergency.cpp función authorized')
    src = replace_once(src,
        '// Only reply to directed, authorized, channel-encrypted app alerts. Never ACK a broadcast.',
        '// Only reply to directed, channel-encrypted app alerts. Never ACK a broadcast.',
        'Emergency.cpp comentario recibos')
    src = replace_once(src,
        'if (msg.kind == EmergencyWire::Kind::Replay && !authorized(msg.originNode)) return ProcessMessage::CONTINUE;',
        'if (msg.kind == EmergencyWire::Kind::Replay && !EmergencyOriginPolicy::validNodeNum(msg.originNode)) return ProcessMessage::CONTINUE;',
        'Emergency.cpp REPLAY')
    src = replace_once(src,
        '''        if (!authorized(from)) {
            LOG_WARN("EMG_APP_REJECT,unauthorized_from=%08x,id=%08x", from, msg.id);
            return ProcessMessage::CONTINUE;
        }''',
        '''        // OPEN-SOS: cualquier identidad de nodo válida puede pedir ayuda.
        // No implica autenticación: la firma verificada es una señal separada.
        if (!EmergencyOriginPolicy::validNodeNum(from)) {
            LOG_WARN("EMG_APP_REJECT,invalid_from=%08x,id=%08x", from, msg.id);
            return ProcessMessage::CONTINUE;
        }''',
        'Emergency.cpp comprobación emisor')
    return src


def patch_relay(src: str) -> str:
    original = '''inline bool authorized(uint32_t nodeNum)
{
    if (nodeNum == 0 || nodeNum == UINT32_MAX)
        return false;
    for (uint32_t allowed : EMERGENCY_AUTHORIZED_ORIGINS) {
        if (allowed != 0 && allowed == nodeNum)
            return true;
    }
    return false;
}

'''
    src = replace_once(src, original, '', 'EmergencyRelayPriority.h lista')
    src = replace_once(src,
        'p.decoded.portnum != meshtastic_PortNum_PRIVATE_APP || p.pki_encrypted || !authorized(p.from))',
        'p.decoded.portnum != meshtastic_PortNum_PRIVATE_APP || p.pki_encrypted ||\n        !EmergencyOriginPolicy::validNodeNum(p.from))',
        'EmergencyRelayPriority.h eligibility')
    src = replace_once(src,
        'if (!authorized(localNodeNum) || (p.from && p.from != localNodeNum) ||',
        'if (!EmergencyOriginPolicy::validNodeNum(localNodeNum) || (p.from && p.from != localNodeNum) ||',
        'EmergencyRelayPriority.h local')
    src = replace_once(src,
        '    // PhoneAPI may supply from=0, which Router::send() later resolves to the',
        '    // OPEN-SOS: todos los NodeNum válidos pueden enviar ALERT, sin allowlist.\n'
        '    // PhoneAPI may supply from=0, which Router::send() later resolves to the',
        'EmergencyRelayPriority.h comentario')
    src = replace_once(src,
        '    // sender; ALWAYS evaluate authorization against the true local NodeNum.',
        '    // sender; ALWAYS evaluate identity against the true local NodeNum.',
        'EmergencyRelayPriority.h comentario PhoneAPI')
    src = replace_once(src,
        '// A matching NodeNum alone is intentionally insufficient for relay elevation.',
        '// A valid NodeNum alone is insufficient for relay elevation: require verified XEdDSA.',
        'EmergencyRelayPriority.h comentario identidad')
    return src


def patch_router(src: str) -> str:
    src = replace_once(src,
        '        // Experimental local priority requires allowlisted local origin.',
        '        // OPEN-SOS: cualquier NodeNum local válido puede emitir ALERT.',
        'Router.cpp comentario de política local')
    return src


def check_previous_patch(root: Path) -> None:
    required_files = [
        'src/modules/optional/Emergency/EmergencyConfig.h',
        'src/modules/optional/Emergency/Emergency.cpp',
        'src/modules/optional/Emergency/EmergencyWire.h',
        'src/modules/optional/Emergency/EmergencyRelayPriority.h',
        'src/mesh/Router.cpp',
        'src/mesh/NextHopRouter.cpp',
        'src/mesh/EmergencyQueuePolicy.h',
        'platformio.ini',
    ]
    missing = [f for f in required_files if not (root / f).is_file()]
    if missing:
        raise ValueError('Falta el parche anterior; archivos ausentes: ' + ', '.join(missing))
    router = (root / 'src/mesh/Router.cpp').read_text(encoding='utf-8')
    relay = (root / 'src/mesh/NextHopRouter.cpp').read_text(encoding='utf-8')
    ini = (root / 'platformio.ini').read_text(encoding='utf-8')
    queue = (root / 'src/mesh/EmergencyQueuePolicy.h').read_text(encoding='utf-8')
    if 'EmergencyRelayPriority::promoteLocal' not in router or 'EmergencyRelayPriority::promoteRelay' not in relay:
        raise ValueError('No se encuentran los cambios de per-hop en Router/NextHopRouter')
    if ini.count('-DEMERGENCY_PER_HOP_PRIORITY=1') < 2 or '-DEMERGENCY_QUEUE_AGING=1' not in ini:
        raise ValueError('No se encuentran los entornos del último parche en platformio.ini')
    if 'EmergencyQueuePolicy::effective' not in queue and 'inline uint32_t effective' not in queue:
        raise ValueError('No existe la implementación de aging del primer parche')


def get_git_root(root: Path) -> None:
    proc = subprocess.run(['git', '-C', str(root), 'rev-parse', '--show-toplevel'],
                          capture_output=True, text=True)
    if proc.returncode != 0 or Path(proc.stdout.strip()).resolve() != root:
        raise ValueError('La ruta debe ser la raíz del repositorio Git de firmware (admite submódulos)')


def transform(root: Path) -> dict[Path, str]:
    paths = {
        'src/modules/optional/Emergency/EmergencyConfig.h': patch_config,
        'src/modules/optional/Emergency/Emergency.cpp': patch_emergency,
        'src/modules/optional/Emergency/EmergencyRelayPriority.h': patch_relay,
        'src/mesh/Router.cpp': patch_router,
    }
    result = {}
    for rel, action in paths.items():
        p = root / rel
        result[p] = action(p.read_text(encoding='utf-8'))
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('firmware', type=Path, help='Ruta de firmware (p.ej. ZeroInfra/hardware/firmware)')
    parser.add_argument('--apply', action='store_true', help='Aplicar; por defecto es dry-run')
    parser.add_argument('--allow-dirty', action='store_true', help='Permitir modificaciones locales preexistentes (se hacen backups)')
    parser.add_argument('--show-diff', action='store_true', help='Imprimir diff unificado sin modificar archivos')
    args = parser.parse_args()
    root = args.firmware.expanduser().resolve()
    try:
        get_git_root(root)
        check_previous_patch(root)
        config = (root / 'src/modules/optional/Emergency/EmergencyConfig.h').read_text(encoding='utf-8')
        if SIGNATURE in config and 'EMERGENCY_AUTHORIZED_ORIGINS' not in config:
            print('OPEN-SOS ya aplicado. No se modifican archivos.')
            return 0
        output = transform(root)   # Todos los anclajes antes de escribir nada.
        dirty = subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain'], text=True).strip()
        if dirty and args.apply and not args.allow_dirty:
            raise ValueError('Hay cambios sin commit. Haz un commit antes de --apply o usa --allow-dirty.')
        print('Cambios previstos:')
        for p, updated in output.items():
            print('  ', p.relative_to(root))
            if args.show_diff:
                original = p.read_text(encoding='utf-8')
                sys.stdout.writelines(difflib.unified_diff(original.splitlines(True), updated.splitlines(True),
                                                          fromfile=str(p.relative_to(root)),
                                                          tofile=str(p.relative_to(root))+' (nuevo)'))
        if dirty:
            print('Aviso: Git tiene cambios sin confirmar; no se modifican en el modo comprobación.')
        if not args.apply:
            print('COMPROBACIÓN OK (dry-run). Ejecuta --apply tras revisar/guardar los cambios.')
            return 0
        backup_root = root / BACKUP_DIR
        existing = [str((backup_root / p.relative_to(root)).relative_to(root))
                    for p in output if (backup_root / p.relative_to(root)).exists()]
        if existing:
            raise ValueError('Ya hay backups de esta versión; no se sobrescribirán: ' + ', '.join(existing))
        for p in output:
            backup = backup_root / p.relative_to(root)
            backup.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(p, backup)
        for p, updated in output.items():
            p.write_text(updated, encoding='utf-8')
        print(f'APLICADO. Backups locales en {BACKUP_DIR}/ (NO los subas a Git).')
        print('Siguiente: git diff --check && pio run -e tbeam-emergency')
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print('ERROR: ' + str(exc), file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
