#!/usr/bin/env python3
"""Smoke tests: C++ policy header + source consistency.
Usage: python3 tests/run_tests.py /path/to/firmware
"""
from __future__ import annotations
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
HEADER_DIR = ROOT / 'src/modules/optional/Emergency'

for name in ('EmergencyRelayPriority.h', 'EmergencyConfig.h', 'EmergencyWire.h'):
    if not (HEADER_DIR / name).is_file():
        raise SystemExit(f'Falta {HEADER_DIR / name}')

config = (HEADER_DIR / 'EmergencyConfig.h').read_text()
relay = (HEADER_DIR / 'EmergencyRelayPriority.h').read_text()
module = (HEADER_DIR / 'Emergency.cpp').read_text()
router = (ROOT / 'src/mesh/Router.cpp').read_text()
nh = (ROOT / 'src/mesh/NextHopRouter.cpp').read_text()
aging = (ROOT / 'src/mesh/EmergencyQueuePolicy.h').read_text()
assert 'EMERGENCY_AUTHORIZED_ORIGINS' not in config + relay + module
assert 'EMERGENCY_ORIGIN_POLICY_OPEN_SOS_V1' in config
assert 'requireVerifiedSignature && !p.xeddsa_signed' in relay
assert 'EmergencyRelayPriority::promoteLocal' in router
assert 'EmergencyRelayPriority::promoteRelay' in nh
assert 'waitMs / 4000U' in aging and '25U' in aging

with tempfile.TemporaryDirectory(prefix='emg_open_sos_') as tmp:
    binary = str(Path(tmp) / 'test_policy')
    cmd = ['g++', '-std=c++17', '-Wall', '-Wextra', '-Werror',
           '-I', str(HEADER_DIR), str(HERE / 'test_policy.cpp'), '-o', binary]
    subprocess.run(cmd, check=True)
    subprocess.run([binary], check=True)
print('OK: cabeceras C++ y dependencias del parche verificadas.')
