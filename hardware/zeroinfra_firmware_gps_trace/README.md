# ZeroInfra — parche incremental de diagnóstico GPS EMG1 en firmware

## Qué hace

La **opción A** ya transmite las coordenadas en el texto del mismo mensaje `EMG1 v1` desde Flutter:

```text
@41.38879,2.11296 SOS
```

El firmware existente **ya puede transmitir, retransmitir, almacenar y entregar ese texto**; no necesita cambios para ello. Este parche opcional añade **interpretación y logs del prefijo de GPS** en el módulo `Emergency` para facilitar las pruebas por puerto serie.

- Archivo nuevo: `src/modules/optional/Emergency/EmergencyGpsText.h`.
- `Emergency.cpp`: lee GPS solo de alertas `ALERT` y `REPLAY` aceptadas; imprime `EMG_GPS_RX`.
- `EmergencyConfig.h`: opción `EMERGENCY_GPS_TEXT_TRACE` (por defecto `1`, puede ponerse a `0` durante la compilación).
- **No cambia** `EmergencyWire.h`, `PRIVATE_APP=256`, los envíos LoRa, la asignación de prioridad, las firmas, `hop_limit` ni los Protobuf.
- Las alertas sin GPS siguen siendo válidas. Tampoco se rechazan alertas con prefijos GPS malformados: simplemente no se imprime `EMG_GPS_RX`.
- Latitud y longitud se expresan en `grados × 100000` como enteros con signo, sin cálculo en coma flotante.

No es un parche para emitir el GPS periódicamente hacia una IP. **Eso debe hacerlo Flutter por Internet al backend**, como se explica en `README_FLUTTER.md` y `README_BACKEND.md` del paquete anterior.

## Aplicación

Suponiendo:

```text
~/UNI/Q7/
├── ZeroInfra/hardware/firmware-emergency/
└── zeroinfra_firmware_gps_trace/
```

Guarda primero cualquier trabajo en Git (en el submódulo del firmware). Después:

```bash
cd ~/UNI/Q7
python3 zeroinfra_firmware_gps_trace/tools/apply_firmware_gps_trace.py \
  ZeroInfra/hardware/firmware-emergency
```

Esto muestra un diff, **sin modificar nada**. Si aparece `COMPROBACIÓN OK`:

```bash
python3 zeroinfra_firmware_gps_trace/tools/apply_firmware_gps_trace.py \
  ZeroInfra/hardware/firmware-emergency --apply
```

Las copias de seguridad `*.gps_trace.bak` no deben subirse al repositorio.

## Compilar y flashear

```bash
cd ~/UNI/Q7/ZeroInfra/hardware/firmware-emergency
git diff --check
pio run -e tbeam-emergency
pio device list
pio run -e tbeam-emergency -t upload --upload-port /dev/ttyACM1
```

Ajusta el puerto según `pio device list`. Si usas `tbeam-emergency-aging`, compila y sube **ese** entorno en lugar de `tbeam-emergency`.

## Prueba con dos placas

Abre el monitor de la receptora B, sin mantener otro cliente abierto en el mismo puerto:

```bash
pio device monitor -p /dev/ttyACM1 -b 115200
```

En A, usando la herramienta del paquete anterior:

```bash
python3 ~/UNI/Q7/zeroinfra_gps_sos_option_a/tools/emg1_gps_cli.py \
  --port /dev/ttyACM0 --origin 0x82e09b4e \
  --lat 41.38879 --lon 2.11296 --text 'SOS GPS prueba' --send
```

Cambia `--origin` por el NodeNum verdadero de A. En B deberían aparecer (si los registros están habilitados):

```text
EMG_APP_RX,kind=1,...severity=3
EMG_GPS_RX,kind=1,origin=82e09b4e,id=...,lat_e5=4138879,lon_e5=211296
```

El registro `EMG_GPS_RX` **solo demuestra que el firmware ha reconocido las coordenadas**; la recepción correcta del mensaje está indicada por `EMG_APP_RX`. La promoción por salto requiere un registro independiente `EMG_RELAY_DIAG,...prior_after=110` y puede depender de la verificación de la firma.

## Pruebas locales

```bash
cd ~/UNI/Q7/zeroinfra_firmware_gps_trace
python3 tests/test_applicator.py
g++ -std=c++17 -Wall -Wextra -Werror \
  -Ioverlay/src/modules/optional/Emergency \
  tests/test_gps_text.cpp -o /tmp/test_emg_gps_text
/tmp/test_emg_gps_text
```

El aplicador es incremental e idempotente y aborta si encuentra archivos inesperados o una instalación parcial. No se ha compilado aquí la imagen completa de la T-Beam; las pruebas unitarias C++ usan el archivo aislado y no equivalen a una prueba de PlatformIO con vuestro repositorio.

## Registrar cambios en Git

```bash
cd ~/UNI/Q7/ZeroInfra/hardware/firmware-emergency
git add src/modules/optional/Emergency/Emergency.cpp \
        src/modules/optional/Emergency/EmergencyConfig.h \
        src/modules/optional/Emergency/EmergencyGpsText.h
git commit -m 'feat: trace GPS coordinates in EMG1 SOS packets'
git push
# Después, desde la raíz ZeroInfra:
cd ../..
git add hardware/firmware-emergency
git commit -m 'chore: update firmware for EMG1 GPS diagnostics'
git push
```
