#!/usr/bin/env python3
"""Incremental firmware patch for the EXISTING EMG1 v1 SOS GPS text format.

Does not alter serialization, LoRa, routing, signature rules or SOS payloads.
It adds an optional EMG_GPS_RX diagnostic message to Emergency.cpp for
accepted ALERT/REPLAY messages whose text begins with @lat,lon.

Default: dry-run. --apply writes after fully validating all anchors.
"""
from __future__ import annotations

import argparse
import difflib
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REL = Path('src/modules/optional/Emergency')
CPP = REL / 'Emergency.cpp'
CONFIG = REL / 'EmergencyConfig.h'
WIRE = REL / 'EmergencyWire.h'
GPS = REL / 'EmergencyGpsText.h'
GPS_SOURCE = ROOT / 'overlay' / GPS

INCLUDE_ANCHOR = '#include "EmergencyWire.h"\n'
INCLUDE_LINE = '#include "EmergencyGpsText.h"\n'
LOG_ANCHOR = ( '        LOG_INFO("EMG_APP_RX,kind=%u,origin=%08x,from=%08x,id=%08x,severity=%u",\n'
               '                 unsigned(static_cast<uint8_t>(msg.kind)), msg.originNode, from, msg.id, unsigned(msg.severity));\n')
LOG_INSERT = '''#if EMERGENCY_GPS_TEXT_TRACE
        // GPS is optional metadata inside the existing EMG1 v1 UTF-8 text.
        // Log only accepted alerts/replays; do not change rebroadcast behavior.
        if (msg.kind == EmergencyWire::Kind::Alert || msg.kind == EmergencyWire::Kind::Replay) {
            EmergencyGpsText::Position gps = {};
            if (EmergencyGpsText::parse(msg.text, msg.textSize, gps)) {
                LOG_INFO("EMG_GPS_RX,kind=%u,origin=%08x,id=%08x,lat_e5=%d,lon_e5=%d",
                         unsigned(static_cast<uint8_t>(msg.kind)), msg.originNode, msg.id,
                         int(gps.latitudeE5), int(gps.longitudeE5));
            }
        }
#endif
'''
CONFIG_INSERT = '''
// Optional ZeroInfra EMG1 SOS location diagnostic (GPS prefix: @lat,lon SOS).
// Does not influence transmission priority or acceptance of SOS without GPS.
#ifndef EMERGENCY_GPS_TEXT_TRACE
#define EMERGENCY_GPS_TEXT_TRACE 1
#endif
'''

def unique_replace(data: str, old: str, new: str, label: str) -> str:
    if data.count(old) != 1:
        raise ValueError(f'{label}: expected exactly one anchor, got {data.count(old)}')
    return data.replace(old, new, 1)


def plan(firmware: Path):
    files = {rel: firmware / rel for rel in (CPP, CONFIG, WIRE)}
    for rel, path in files.items():
        if not path.is_file():
            raise ValueError(f'Missing {rel}: pass the FIRMWARE root, not the ZeroInfra root')
    if not GPS_SOURCE.is_file():
        raise ValueError(f'Missing embedded source {GPS_SOURCE}')

    wire = files[WIRE].read_text(encoding='utf-8')
    if not all(x in wire for x in (
        'HEADER_SIZE = 20', 'MAX_TEXT_SIZE = 160',
        'enum class Kind', 'Alert = 1', 'Replay = 5',
    )):
        raise ValueError('Unexpected EmergencyWire.h: this patch requires EMG1 v1')

    cpp_before = files[CPP].read_text(encoding='utf-8')
    config_before = files[CONFIG].read_text(encoding='utf-8')
    existing_header = firmware / GPS
    new_header = GPS_SOURCE.read_text(encoding='utf-8')
    if existing_header.exists() and existing_header.read_text(encoding='utf-8') != new_header:
        raise ValueError(f'{GPS}: exists but differs; refusing to overwrite it')

    already = (
        INCLUDE_LINE in cpp_before
        and 'EMG_GPS_RX,kind=%u' in cpp_before
        and '#define EMERGENCY_GPS_TEXT_TRACE 1' in config_before
        and existing_header.is_file()
    )
    partial = (
        INCLUDE_LINE in cpp_before
        or 'EMG_GPS_RX,kind=%u' in cpp_before
        or 'EMERGENCY_GPS_TEXT_TRACE' in config_before
        or existing_header.exists()
    )
    if already:
        # Check exact injected trace, to avoid silently accepting manual modifications.
        if LOG_INSERT not in cpp_before or CONFIG_INSERT not in config_before:
            raise ValueError('GPS diagnostic appears installed but differs from this patch')
        return {}
    if partial:
        raise ValueError('Partial/modified GPS patch found; inspect files before retrying')

    cpp_after = unique_replace(
        cpp_before, INCLUDE_ANCHOR, INCLUDE_ANCHOR + INCLUDE_LINE, str(CPP)
    )
    cpp_after = unique_replace(
        cpp_after, LOG_ANCHOR, LOG_ANCHOR + LOG_INSERT, str(CPP)
    )
    config_after = config_before.rstrip('\n') + '\n' + CONFIG_INSERT
    return {
        files[CPP]: (cpp_before, cpp_after),
        files[CONFIG]: (config_before, config_after),
        existing_header: (None, new_header),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('firmware', type=Path, help='Firmware repository root containing src/mesh and platformio.ini')
    parser.add_argument('--apply', action='store_true', help='Write changes (default is dry-run)')
    args = parser.parse_args()
    firmware = args.firmware.expanduser().resolve()
    if not (firmware / 'platformio.ini').is_file():
        parser.error(f'No platformio.ini in {firmware}: pass the firmware root')
    try:
        changes = plan(firmware)
    except (OSError, UnicodeError, ValueError) as exc:
        parser.error(str(exc))
    if not changes:
        print('YA APLICADO: no changes necessary.')
        return
    for path, (before, after) in changes.items():
        print(f'FILE: {path.relative_to(firmware)}')
        if before is None:
            print(f'  New file ({len(after.encode("utf-8"))} bytes)')
        else:
            diff = difflib.unified_diff(
                before.splitlines(keepends=True), after.splitlines(keepends=True),
                fromfile=f'a/{path.relative_to(firmware)}',
                tofile=f'b/{path.relative_to(firmware)}',
            )
            print(''.join(diff))
    if not args.apply:
        print('COMPROBACIÓN OK (dry-run). Repeat with --apply to write changes.')
        return
    # Input and anchors have been verified before writing any files.
    for path, (before, after) in changes.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        if before is not None:
            backup = path.with_name(path.name + '.gps_trace.bak')
            if not backup.exists():
                shutil.copy2(path, backup)
        path.write_text(after, encoding='utf-8')
        print(f'UPDATED: {path.relative_to(firmware)}')
    print('PARCHE APLICADO. Build with: pio run -e tbeam-emergency')

if __name__ == '__main__':
    main()
