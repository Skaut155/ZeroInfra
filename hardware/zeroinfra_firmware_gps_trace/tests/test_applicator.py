#!/usr/bin/env python3
"""Self-contained smoke test for the incremental patch installer."""
import importlib.util
import tempfile
from pathlib import Path

BASE = Path(__file__).resolve().parent.parent
SCRIPT = BASE / 'tools/apply_firmware_gps_trace.py'
spec = importlib.util.spec_from_file_location('applicator', SCRIPT)
app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(app)


def run():
    with tempfile.TemporaryDirectory() as tmp:
        firmware = Path(tmp)
        (firmware / 'platformio.ini').write_text('[env:tbeam-emergency]\n')
        directory = firmware / app.REL
        directory.mkdir(parents=True)
        (firmware / app.CPP).write_text(
            '#include "EmergencyWire.h"\n' +
            'void check() {\n' + app.LOG_ANCHOR + '\n}\n', encoding='utf-8')
        (firmware / app.CONFIG).write_text('#pragma once\n', encoding='utf-8')
        (firmware / app.WIRE).write_text(
            'HEADER_SIZE = 20\nMAX_TEXT_SIZE = 160\n'
            'enum class Kind\nAlert = 1\nReplay = 5\n', encoding='utf-8')

        changes = app.plan(firmware)
        assert len(changes) == 3
        assert 'EMG_GPS_RX' in changes[firmware / app.CPP][1]
        assert '#include "EmergencyGpsText.h"' in changes[firmware / app.CPP][1]
        for target, (_, after) in changes.items():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(after, encoding='utf-8')

        assert app.plan(firmware) == {}, 'second application must be a no-op'

        # Simulate a partial/manual edit and assert that the installer fails closed.
        cpp = firmware / app.CPP
        cpp.write_text(cpp.read_text().replace(
            'EMG_GPS_RX,kind=%u', 'EMG_GPS_CHANGED,kind=%u'), encoding='utf-8')
        try:
            app.plan(firmware)
        except ValueError:
            pass
        else:
            raise AssertionError('modified/partial install unexpectedly accepted')
        print('OK: transformation, idempotence, modified-install rejection')

if __name__ == '__main__':
    run()
