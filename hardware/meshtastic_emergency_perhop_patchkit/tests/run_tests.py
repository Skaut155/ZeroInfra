#!/usr/bin/env python3
"""Run host-only C++ tests against a copy of the REAL policy/header, with fixture NodeNum."""
from pathlib import Path
import tempfile
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
src = root / 'overlay/src/modules/optional/Emergency/EmergencyRelayPriority.h'
source_wire = root.parent / 'emergency_perhop_work/meshtastic_emergency_patchkit/overlay/src/modules/optional/Emergency/EmergencyWire.h'
# Allow caller to set previous patch path if directory locations differ.
import sys
if len(sys.argv)>1:
    source_wire = Path(sys.argv[1]).resolve()
if not source_wire.is_file():
    raise SystemExit('Pasa como argumento la ruta a EmergencyWire.h de tu primer parche')
with tempfile.TemporaryDirectory() as d:
    d = Path(d)
    shutil.copy2(src, d/'EmergencyRelayPriority.h')
    shutil.copy2(source_wire,d/'EmergencyWire.h')
    (d/'EmergencyConfig.h').write_text('''#pragma once
#include <stdint.h>
static constexpr uint32_t EMERGENCY_AUTHORIZED_ORIGINS[] = {0x1a21fd32};
''')
    cmd = ['g++','-std=c++17','-Wall','-Wextra','-Werror','-I',str(d),
           str(root/'tests/test_relay_policy.cpp'),'-o',str(d/'test-relay')]
    subprocess.run(cmd, check=True)
    subprocess.run([str(d/'test-relay')], check=True)
