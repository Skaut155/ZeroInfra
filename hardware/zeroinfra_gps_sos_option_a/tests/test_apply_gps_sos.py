import tempfile
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from apply_gps_sos import patch_source, OLD_BLOCK, NEW_BLOCK, SOURCE, CLIENT, TEST


def test_logic():
    before = "import 'x';\nabstract final class EmergencyPolicy {\n  static const String text = 'SOS';\n}\nabstract final class EmergencyText {\n" + OLD_BLOCK + "\n}\n"
    result = patch_source(before)
    assert 'maxSignedSosTextBytes = 120' in result
    assert NEW_BLOCK in result
    assert patch_source(result) == result
    assert "import 'dart:convert';" in result

    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        source = root / SOURCE
        source.parent.mkdir(parents=True, exist_ok=True)
        source.write_text(before)
        client = root / CLIENT
        client.write_text('Future<MeshMessage> sendSos() { EmergencyText.encode(latitude: fix?.latitude, longitude: fix?.longitude); portNum: EmergencyPolicy.portNum; }')
        tool = Path(__file__).resolve().parents[1] / 'tools' / 'apply_gps_sos.py'
        p = subprocess.run([sys.executable, str(tool), d], capture_output=True, text=True)
        assert p.returncode == 0, p.stderr
        assert source.read_text() == before, 'dry-run modificó el archivo'
        p = subprocess.run([sys.executable, str(tool), d, '--apply'], capture_output=True, text=True)
        assert p.returncode == 0, p.stderr
        assert (root / TEST).exists()
        assert (source.with_suffix('.dart.gps_sos.bak')).exists()
        p = subprocess.run([sys.executable, str(tool), d, '--apply'], capture_output=True, text=True)
        assert p.returncode == 0, p.stderr
        assert (root / TEST).read_text().count("test('SOS mantiene GPS") == 1
    print('OK: aplicador dry-run, apply e idempotencia')


if __name__ == '__main__':
    test_logic()
