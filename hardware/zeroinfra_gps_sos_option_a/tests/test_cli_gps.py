import importlib.util
from pathlib import Path

p = Path(__file__).resolve().parents[1] / 'tools' / 'emg1_gps_cli.py'
spec = importlib.util.spec_from_file_location('gps_cli', p)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

def test_roundtrip():
    text = m.build_text('Necesito ayuda', 41.388791, 2.112964)
    assert text == '@41.38879,2.11296 Necesito ayuda'
    packet = m.encode_alert(0x82e09b4e, 123, 3, text)
    parsed = m.decode_alert(packet)
    assert parsed['body'] == 'Necesito ayuda'
    assert parsed['position'] == (41.38879, 2.11296)
    assert len(packet) == 20 + len(text.encode('utf8'))

def test_validation():
    import pytest
    with pytest.raises(ValueError): m.build_text('SOS', 41.5, None)
    with pytest.raises(ValueError): m.build_text('SOS', 91, 2)
    assert m.build_text('SOS') == 'SOS'
    assert len(m.build_text('🚨'*100, -90, -180).encode('utf8')) <= 120

if __name__ == '__main__':
    test_roundtrip()
    try:
        test_validation()
    except ImportError:
        assert m.build_text('SOS') == 'SOS'
    print('OK: tests del CLI')
