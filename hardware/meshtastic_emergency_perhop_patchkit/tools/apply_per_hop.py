#!/usr/bin/env python3
"""Incremental per-hop priority patch for an ALREADY EMG1-patched firmware checkout.

Dry-run by default. Checks all anchors before writing. Does not alter the air protocol.
Designed for Meshtastic 2.8.2 b48e1e0 + previous emergency_patchkit v2.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import subprocess
import shutil

BASE = Path(__file__).resolve().parent.parent
HEADER = BASE / 'overlay/src/modules/optional/Emergency/EmergencyRelayPriority.h'

def once(text: str, old: str, new: str, name: str) -> str:
    n = text.count(old)
    if n != 1:
        raise RuntimeError(f'{name}: anclaje esperado una vez, encontrado {n}: {old[:120]!r}')
    return text.replace(old, new, 1)

def patch_router(s: str) -> str:
    s = once(s, '#include "modules/optional/Emergency/EmergencyWire.h"',
             '#include "modules/optional/Emergency/EmergencyRelayPriority.h"',
             'Router.cpp include EMG1')
    old = '''        // Priority remains local to the node. No on-air header changes and no relay priority inference.
        // A valid custom payload from this node is identified as an emergency alert.
        if (isFromUs(p) && p->which_payload_variant == meshtastic_MeshPacket_decoded_tag &&
            p->decoded.portnum == meshtastic_PortNum_PRIVATE_APP) {
            EmergencyWire::Message e = {};
            if (EmergencyWire::parse(p->decoded.payload.bytes, p->decoded.payload.size, e) &&
                e.kind == EmergencyWire::Kind::Alert && e.originNode == getNodeNum()) {
                p->priority = meshtastic_MeshPacket_Priority_ALERT;
            }
        }'''
    new = '''        // Experimental local priority requires allowlisted local origin.
        // Actual relay priority requires XEdDSA-verified sender signature.
        if (isFromUs(p) && EmergencyRelayPriority::promoteLocal(*p, getNodeNum())) {
            LOG_INFO("EMG_LOCAL_PRIORITY,from=%08x,id=%08x", p->from, p->id);
        }'''
    return once(s, old, new, 'Router.cpp local promotion')

def patch_next_hop(s: str) -> str:
    s = once(s, '#include "NextHopRouter.h"',
             '''#include "NextHopRouter.h"
#if EMERGENCY_PER_HOP_PRIORITY
#include "modules/optional/Emergency/EmergencyRelayPriority.h"
#endif''', 'NextHopRouter.cpp include')
    old = '''                    meshtastic_MeshPacket *tosend = packetPool.allocCopy(*p); // keep a copy because we will be sending it
                    if (!tosend)
                        return true;
                    LOG_INFO("Rebroadcast msg from %x", p->relay_node);'''
    new = '''                    meshtastic_MeshPacket *tosend = packetPool.allocCopy(*p); // keep a copy because we will be sending it
                    if (!tosend)
                        return true;
#if EMERGENCY_PER_HOP_PRIORITY
                    // The incoming packet was authenticated/decrypted before reaching sniffReceived().
                    // This local flag survives the copy but never appears in the on-air packet.
                    // Promote only authorized XEdDSA-verified EMG1 ALERTs, never opaque/unsigned packets.
                    if (EmergencyRelayPriority::promoteRelay(*tosend)) {
                        LOG_INFO("EMG_RELAY_PRIORITY,from=%08x,mesh_id=%08x,priority=%u", tosend->from,
                                 tosend->id, (unsigned)tosend->priority);
                    }
#endif
                    LOG_INFO("Rebroadcast msg from %x", p->relay_node);'''
    return once(s, old, new, 'NextHopRouter.cpp relay copy')

def patch_ini(s: str) -> str:
    if s.count('[env:tbeam-emergency]') != 1 or s.count('[env:tbeam-emergency-aging]') != 1:
        raise RuntimeError('platformio.ini: faltan los entornos del primer parche')
    if s.count('  -DEMERGENCY_APP_PRIORITY=1') != 2:
        raise RuntimeError('platformio.ini: se esperaban dos anclajes EMERGENCY_APP_PRIORITY')
    s = s.replace('  -DEMERGENCY_APP_PRIORITY=1',
                  '  -DEMERGENCY_APP_PRIORITY=1\n  -DEMERGENCY_PER_HOP_PRIORITY=1')
    return s

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('firmware', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    root = args.firmware.resolve()
    if not (root / '.git').exists():
        raise SystemExit('La ruta no es un repositorio Git')
    files = {
        root / 'src/mesh/Router.cpp': patch_router,
        root / 'src/mesh/NextHopRouter.cpp': patch_next_hop,
        root / 'platformio.ini': patch_ini,
    }
    dest = root / 'src/modules/optional/Emergency/EmergencyRelayPriority.h'
    if dest.exists():
        raise SystemExit(f'El header ya existe: {dest}. No se sobrescribe.')
    needed = [root / 'src/modules/optional/Emergency/EmergencyConfig.h',
              root / 'src/modules/optional/Emergency/EmergencyWire.h']
    for p in needed:
        if not p.is_file():
            raise SystemExit(f'No existe el archivo del parche EMG1 previo: {p}')
    changed = {}
    for p, action in files.items():
        changed[p] = action(p.read_text(encoding='utf-8'))
    status = subprocess.check_output(['git', '-C', str(root), 'status', '--short'], text=True).strip()
    sha = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
    print('Commit actual:', sha)
    if status:
        print('Aviso: tienes cambios sin confirmar:\n' + status)
        print('Conserva una copia o commit antes de aplicar este parche incremental.')
    print('Se modificarán:')
    for p in changed:
        print('  ', p.relative_to(root))
    print('Se añadirá:', dest.relative_to(root))
    if not args.apply:
        print('COMPROBACIÓN OK; ejecuta con --apply después de guardar tus cambios.')
        return
    # Verified all anchors before first write. Existing uncommitted files are
    # backed up with their ORIGINAL bytes before updating.
    backup = root / '.emergency_perhop_backups'
    backup.mkdir(exist_ok=True)
    for p in changed:
        relative = p.relative_to(root)
        b = backup / relative
        b.parent.mkdir(parents=True, exist_ok=True)
        if b.exists():
            raise SystemExit(f'Ya existe backup previo {b}. Revisa antes de reejecutar.')
    for p, modified in changed.items():
        b = backup / p.relative_to(root)
        shutil.copy2(p, b)
        p.write_text(modified, encoding='utf-8')
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(HEADER, dest)
    print('APLICADO. Copias originales en .emergency_perhop_backups/')
    print('Revisa git diff --check y compila pio run -e tbeam-emergency.')

if __name__ == '__main__':
    main()
