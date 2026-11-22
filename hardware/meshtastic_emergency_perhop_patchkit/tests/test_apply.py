#!/usr/bin/env python3
"""Synthetic anchor/idempotence test for incremental patch script; does NOT test real firmware."""
from pathlib import Path
import tempfile
import subprocess
import sys

root=Path(__file__).resolve().parent.parent
script = root/'tools/apply_per_hop.py'
router_header='''#include "Router.h"
#if EMERGENCY_APP_PRIORITY
#include "modules/optional/Emergency/EmergencyWire.h"
#endif
'''
router_body='''        // Priority remains local to the node. No on-air header changes and no relay priority inference.
        // A valid custom payload from this node is identified as an emergency alert.
        if (isFromUs(p) && p->which_payload_variant == meshtastic_MeshPacket_decoded_tag &&
            p->decoded.portnum == meshtastic_PortNum_PRIVATE_APP) {
            EmergencyWire::Message e = {};
            if (EmergencyWire::parse(p->decoded.payload.bytes, p->decoded.payload.size, e) &&
                e.kind == EmergencyWire::Kind::Alert && e.originNode == getNodeNum()) {
                p->priority = meshtastic_MeshPacket_Priority_ALERT;
            }
        }
        coerceCoordinatePacketToPositionChannel(p);'''
nh = '''#include "NextHopRouter.h"
                    meshtastic_MeshPacket *tosend = packetPool.allocCopy(*p); // keep a copy because we will be sending it
                    if (!tosend)
                        return true;
                    LOG_INFO("Rebroadcast msg from %x", p->relay_node);'''
ini = '''[env:tbeam-emergency]
build_flags =
  -DEMERGENCY_APP_PRIORITY=1
[env:tbeam-emergency-aging]
build_flags =
  -DEMERGENCY_APP_PRIORITY=1
'''
with tempfile.TemporaryDirectory() as td:
    d=Path(td)
    subprocess.run(['git','init','-q',str(d)],check=True)
    (d/'src/mesh').mkdir(parents=True)
    (d/'src/modules/optional/Emergency').mkdir(parents=True)
    (d/'src/mesh/Router.cpp').write_text(router_header+router_body)
    (d/'src/mesh/NextHopRouter.cpp').write_text(nh)
    (d/'platformio.ini').write_text(ini)
    for name in ('EmergencyWire.h','EmergencyConfig.h'):
        (d/'src/modules/optional/Emergency'/name).write_text('// existing '+name)
    subprocess.run(['git','-C',str(d),'add','.'],check=True)
    subprocess.run(['git','-C',str(d),'-c','user.name=Test','-c','user.email=test@example.com','commit','-qm','fixture'],check=True)
    for extra in ([], ['--apply']):
        r=subprocess.run([sys.executable,str(script),str(d),*extra],text=True,capture_output=True)
        assert r.returncode==0,(r.stdout,r.stderr)
    assert (d/'src/modules/optional/Emergency/EmergencyRelayPriority.h').exists()
    changed=(d/'src/mesh/NextHopRouter.cpp').read_text()
    assert 'EmergencyRelayPriority::promoteRelay(*tosend)' in changed
    assert (d/'platformio.ini').read_text().count('EMERGENCY_PER_HOP_PRIORITY=1')==2
    assert (d/'.emergency_perhop_backups/src/mesh/Router.cpp').exists()
    # Second application is rejected rather than silently duplicating code
    r=subprocess.run([sys.executable,str(script),str(d),'--apply'],text=True,capture_output=True)
    assert r.returncode!=0
    print('OK: dry-run, targeted edits, file backups, repeat-run guard')
