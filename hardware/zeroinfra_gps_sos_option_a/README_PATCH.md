# Parche incremental ZeroInfra — GPS dentro del mismo SOS EMG1 (opción A)

## Qué hace y qué no hace

**A fecha de revisión (23-11-2026), ZeroInfra `main` YA implementa el envío del GPS dentro del mismo SOS:** `app/lib/data/meshtastic/meshtastic_client.dart::sendSos()` llama a `EmergencyText.encode(latitude: ..., longitude: ...)` y manda un único `MeshPacket` `PRIVATE_APP=256`.

El parche **no reimplementa lo que existe**. Hace un refuerzo incremental en `app/lib/data/meshtastic/emergency_policy.dart`:

1. Descarta coordenadas incompletas, `NaN`, infinitas o fuera de rango, y envía un SOS sin posición en esos casos.
2. Limita el texto generado del SOS a **120 bytes UTF-8**, con corte seguro de caracteres Unicode. Es un presupuesto conservador para dejar margen a la firma, **no una garantía de que quede firmado**.
3. Añade tests (`app/test/data/emergency_gps_patch_test.dart`).
4. Verifica que tu rama `MeshtasticClient.sendSos()` ya inserta la posición. Si no coincide, aborta sin modificar nada.

**No toca el submódulo firmware** `hardware/firmware-emergency`, ni `EmergencyWire.h`, ni `Router.cpp`. El protocolo permanece EMG1 v1, con cabecera de 20 B y texto máximo de 160 B. Las opciones A del GPS no requieren cambiarlo.

Además incluye `tools/emg1_gps_cli.py` para hacer SOS de prueba con coordenadas explícitas. El CLI es independiente del aplicador.

## Aplicar sobre el repositorio

Descomprime este ZIP junto a `ZeroInfra` y sitúate en la carpeta que contiene ambos. Ejemplo:

```bash
cd ~/UNI/Q7
# En ese directorio deben existir ZeroInfra/ y zeroinfra_gps_sos_option_a/
```

Guarda tu trabajo:

```bash
cd ZeroInfra
git status
# Haz commit en tu rama antes del parche.
cd ..
```

Prueba primero **sin modificar archivos**:

```bash
python3 zeroinfra_gps_sos_option_a/tools/apply_gps_sos.py ZeroInfra/
```

Si aparece `COMPROBACIÓN OK`, aplícalo:

```bash
python3 zeroinfra_gps_sos_option_a/tools/apply_gps_sos.py ZeroInfra/ --apply
```

El aplicador crea `app/lib/data/meshtastic/emergency_policy.dart.gps_sos.bak` como copia si necesita modificar el código. Esa copia **no debe entrar en Git**.

Comprueba:

```bash
cd ZeroInfra/app
dart format lib/data/meshtastic/emergency_policy.dart test/data/emergency_gps_patch_test.dart
flutter test
flutter analyze
cd ..
git diff --check
git status
```

Si funciona:

```bash
git add app/lib/data/meshtastic/emergency_policy.dart app/test/data/emergency_gps_patch_test.dart
git commit -m 'test: validate GPS and size of SOS EMG1 payload'
git push
```

El script está pensado para el archivo observado en ZeroInfra `main`. Si la rama ha cambiado, se detiene para evitar sobrescrituras. Puedes ejecutarlo dos veces: es idempotente.

## Probar la trama desde USB con la CLI

**Primero, solo generar y mostrar el paquete:**

```bash
python3 zeroinfra_gps_sos_option_a/tools/emg1_gps_cli.py \
  --origin 0x82e09b4e --lat 41.38879 --lon 2.11296 \
  --text 'Necesito ayuda'
```

El ejemplo usa un NodeNum **de muestra**; usa el NodeNum real de la T-Beam A para enviar.

**T-Beam B: escuchar** (el puerto serie no debe estar abierto también por `pio device monitor`):

```bash
python3 zeroinfra_gps_sos_option_a/tools/emg1_gps_cli.py \
  --port /dev/ttyACM1 --listen
```

**T-Beam A: enviar**:

```bash
python3 zeroinfra_gps_sos_option_a/tools/emg1_gps_cli.py \
  --port /dev/ttyACM0 --origin 0x82e09b4e \
  --lat 41.38879 --lon 2.11296 \
  --text 'Necesito ayuda' --send
```

Si usas `--listen`, debes tener instalado `meshtastic` y **`pypubsub`** en el Python que ejecuta el script. Para cambiar a monitor serie en B, detén el listener antes.

El script **no duplica el mensaje en TEXT_MESSAGE_APP**: envía un solo `ALERT` `PRIVATE_APP=256`.

### Cómo verificar la prioridad

En B, abre por separado el monitor serie y envía un SOS nuevo desde A. Busca:

```text
EMG_APP_RX,kind=1,...
EMG_RELAY_DIAG,...sig_ok=1,...prior_after=110,promoted=1
EMG_TXQ_DIAG,stage=dequeue,...priority=110
```

La recepción del SOS y la retransmisión **no prueban por sí solas** que se haya asignado prioridad 110. El diagnóstico de firma depende del firmware, del tamaño y de las claves disponibles. Si ves `sig_ok=0`, no eludas las comprobaciones; analiza las firmas primero.

## Pruebas locales de las herramientas

```bash
python3 zeroinfra_gps_sos_option_a/tests/test_cli_gps.py
```

La carpeta `reference/` contiene un ejemplo para publicación HTTP cada diez minutos. **No se activa desde el aplicador**, porque requiere acordar endpoint y autenticación, y porque enviar ubicaciones sin consentimiento sería una mala configuración por defecto.

## Archivos del paquete

```text
README_PATCH.md
README_FLUTTER.md
README_BACKEND.md
tools/apply_gps_sos.py
tools/emg1_gps_cli.py
reference/location_uplink_service.dart
tests/test_cli_gps.py
```
