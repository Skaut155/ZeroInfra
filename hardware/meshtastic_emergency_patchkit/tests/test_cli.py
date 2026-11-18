import importlib.util
from pathlib import Path

p=Path(__file__).resolve().parents[1]/'tools'/'emergency_cli.py'
spec=importlib.util.spec_from_file_location('emergency_cli',p)
m=importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
encoded=m.encode(1,2,1,1,0,0x12345678,b'Hola')
assert m.decode(encoded)['id']==1
assert m.decode(encoded)['text']==b'Hola'
assert m.decode(encoded[:5]) is None
assert m.decode(encoded.replace(b'EMG1',b'BAD!',1)) is None
fetch=m.encode(4,0,0,0,0,0)
assert m.decode(fetch)['kind']==4
assert m.decode(fetch)['id']==0
assert m.decode(m.encode(3,0,0,7,0,0x12345678,b'RESUELTO'))['kind']==3
print('OK: serializacion Python y tipos ALERT/RESOLVED/FETCH')
