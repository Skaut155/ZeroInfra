# Meshtastic · modificaciones experimentales para comunicaciones de emergencia

**Contenido:** código C++ añadido, un aplicador de modificaciones para el firmware, una CLI para generar mensajes y pruebas unitarias independientes del hardware.

**Importante.** Este paquete **no contiene el firmware completo ni un firmware binario**. Debes aplicarlo sobre un checkout limpio del repositorio `meshtastic/firmware` de una versión compatible. Se revisaron archivos de `develop` el **15 de noviembre de 2026**, pero no se pudo fijar un SHA remoto ni ejecutar aquí la compilación de PlatformIO porque no se dispone del repositorio completo ni del entorno de la placa. El aplicador comprueba los puntos de modificación y falla si el código diverge. El SHA real de tu checkout queda registrado en `emergency_base_sha.txt` después de aplicar.

En tu repositorio ya clonado, guarda tu trabajo y crea una rama nueva:

```bash
git status --short
git rev-parse HEAD
git switch -c feature/emergency-mesh
```

Desde el directorio de este paquete:

```bash
python3 tools/apply.py /ruta/al/firmware
python3 tools/apply.py /ruta/al/firmware --apply
```

La primera ejecución solo comprueba que los archivos originales contienen **los anclajes esperados**. La segunda escribe los cambios y copia los archivos nuevos. Si falla, no fuerces la modificación: hay que adaptar el cambio a tu versión del código. **No ejecutes `--allow-dirty` salvo que hayas revisado los conflictos.**

## Configuración obligatoria de los nodos

1. Edita en el repositorio modificado `src/modules/optional/Emergency/EmergencyConfig.h`, sustituyendo `EMERGENCY_AUTHORIZED_ORIGINS[] = {0}` por los números de nodo de 32 bits que autorizas a participar, por ejemplo `{0x12345678, 0x87654321}`. `{0}` no permite ningún emisor. Copia una configuración coherente a todas las placas de tu laboratorio.
2. Configura Meshtastic en la misma región LoRa y los mismos parámetros de canal para los cuatro dispositivos; no elimines CAD, límites de transmisión, cifrado ni control de airtime.
3. Reserva `PRIVATE_APP=256` para este experimento. **El formato EMG1 es propio**; los clientes Meshtastic habituales no muestran estas alertas como mensajes de texto normales.
4. Para proteger los mensajes, utiliza un canal con claves gestionadas correctamente. La lista de IDs no demuestra identidad criptográfica; para uso real hay que diseñar y verificar autenticación del emisor.

## Compilar (en tu ordenador con PlatformIO)

```bash
cd /ruta/al/firmware
git diff --check
pio run -e tbeam-emergency
```

Para activar el algoritmo alternativo de espera en cola (*aging*):

```bash
pio run -e tbeam-emergency-aging
```

**No actives aging en una red real sin comprobar las interacciones con retransmisiones diferidas y hooks de transmisión.** La opción normal tiene `EMERGENCY_QUEUE_AGING=0` y conserva el orden de las colas de Meshtastic, añadiendo observabilidad.

Antes de flashear una placa, confirma que esa variante de T-Beam es exactamente la de tu hardware y que la compilación ha terminado sin errores. Si procede, utiliza:

```bash
pio run -e tbeam-emergency -t upload --upload-port /dev/ttyACM0
```

La configuración añade dos entornos **sin sustituir** `env:tbeam`. El módulo está desactivado cuando `EMERGENCY_ENABLE_MODULE` no está definido. Para comparar con un firmware **verdaderamente original**, utiliza una rama o checkout anterior a estos cambios; los archivos del núcleo se han instrumentado también en el checkout modificado.

## Generar, enviar y escuchar mensajes de ejemplo

La herramienta `tools/emergency_cli.py` permite construir tramas y probar el formato localmente sin transmitir, por defecto:

```bash
python3 tools/emergency_cli.py --origin 0x12345678 --text "Alerta de prueba"
```

Para transmitir por USB a un nodo Meshtastic (requiere `pip install meshtastic` y autorización para usar el puerto):

```bash
python3 tools/emergency_cli.py --port /dev/ttyACM0 \
    --origin 0x12345678 --text "Alerta de prueba" --send
```

Si quieres que esa retransmision también se pueda recibir por el canal de texto normal hay que usar el argumento `:w
--mirror-chat`

```bash
python3 tools/emergency_cli.py --port /dev/ttyACM0 \
    --origin 0x12345678 --text "Alerta de prueba" --send
```

**`--origin` debe corresponder al NodeNum real del emisor.** No sirve cualquier valor inventado: el módulo verifica el origen en la trama recibida. Usa la CLI original de Meshtastic para consultar los NodeNum de los dispositivos.

Para un mensaje directo que solicita recibo de la aplicación:

```bash
python3 tools/emergency_cli.py --port /dev/ttyACM0 \
    --origin 0x12345678 --destination '!87654321' --receipt \
    --text "Alerta de prueba" --send
```

Para recuperar la alerta más reciente almacenada temporalmente en otro nodo:

```bash
python3 tools/emergency_cli.py --port /dev/ttyACM0 \
    --mode fetch --destination '!87654321' --send
```

Para visualizar la recepción desde otro puerto USB:

```bash
python3 tools/emergency_cli.py --port /dev/ttyACM1 --listen
```

La interfaz Python de Meshtastic puede evolucionar; la llamada `sendData()` de esta herramienta **no se ha probado contra dispositivos físicos aquí**.

## Ejecución de pruebas locales

No requieren antenas ni transmisiones de radio:

```bash
python3 tests/test_patch_anchors.py
python3 tests/test_cli.py
g++ -std=c++17 -Wall -Wextra -Werror tests/test_wire.cpp -o /tmp/emergency-wire-test
/tmp/emergency-wire-test
g++ -std=c++17 -Wall -Wextra -Werror -Itests/stubs \
    -DEMERGENCY_ENABLE_MODULE=1 -fsyntax-only \
    overlay/src/modules/optional/Emergency/Emergency.cpp
```

Las clases de `tests/stubs/` **no son la librería real**; solo comprueban sintaxis de parte de la implementación. Antes de afirmar que funciona hay que compilar todo el firmware y ejecutar tests de integración con dos o más T-Beam.

## Qué incorpora

- Instrumentación de cola TX: aceptados, rechazados, expulsados, cancelados, enviados desde cola, pico de ocupación y espera media/máxima. Métricas RX de aceptados y descartados, CAD ocupado/libre, inicios TX, ACK/NAK y mensajes fiables.
- Reconocimiento local de los paquetes experimentales `ALERT` y asignación de prioridad Meshtastic `ALERT` **en el nodo origen**.
- Módulo `Emergency` opcional con formato `EMG1`, caducidad, deduplicación de alertas por identificador de aplicación y origen, lista de emisores admitidos, recibos directos de aplicación, retención temporal en RAM (8 alertas) y recuperación mediante peticiones directas `FETCH`.
- Política de *aging* de cola estrictamente optativa, que no eleva mensajes normales por encima de prioridad 99 ni modifica las prioridades originales almacenadas.
- Dos entornos PlatformIO propios para T-Beam, con MQTT deshabilitado por bandera de compilación. No se eliminan código GPS, BLE, radio, routing, cifrado ni módulos del firmware original.

## Qué NO incorpora y por qué

- **Ni modifica CSMA/CAD, el backoff ni las reglas de flood/next-hop.** Esos cambios requieren una línea base experimental, compatibilidad y verificación de la normativa radioeléctrica; el manual original recomienda medir antes de intervenir.
- **No garantiza recepción ni alta disponibilidad.** El acuse de aplicación confirma procesamiento local del módulo, no lectura humana. Los recibos solo se emiten en unicast, con limitación de frecuencia.
- **No propaga la prioridad ALERT a través de cabeceras LoRa.** La prioridad es local; cambiar el protocolo en aire comprometería compatibilidad. Los retransmisores estándar siguen aplicando su propia política.
- **No conserva alertas después de reiniciar.** El almacén de 8 alertas es volátil, con antigüedad máxima de una hora en RAM, y devuelve una alerta por petición como máximo.
- **No implementa una prueba de identidad criptográfica del origen.** Una lista de NodeNum no evita la falsificación de IDs. No lo uses para emergencias reales sin autenticación y validación adicionales.
- **No demuestra menor latencia ni mayor fiabilidad.** Se necesitan mediciones comparadas y tests con las placas para sostener cualquiera de esas afirmaciones.

Consulta `docs/CAMBIOS_POR_ARCHIVO.md` para la localización exacta de todos los cambios y sus puntos de inserción.
