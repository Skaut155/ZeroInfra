# Meshtastic · modificaciones experimentales para comunicaciones de emergencia

**Contenido:** código C++ añadido, un aplicador de modificaciones para el firmware, una CLI para generar mensajes y pruebas unitarias independientes del hardware.

El SHA real de tu checkout queda registrado en `emergency_base_sha.txt` después de aplicar.

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

1. Configura Meshtastic en la misma región LoRa y los mismos parámetros de canal para los cuatro dispositivos; no elimines CAD, límites de transmisión, cifrado ni control de airtime.
2. Reserva `PRIVATE_APP=256` para este experimento. **El formato EMG1 es propio**; los clientes Meshtastic habituales no muestran estas alertas como mensajes de texto normales.
3. Para proteger los mensajes, utiliza un canal con claves gestionadas correctamente. La lista de IDs no demuestra identidad criptográfica; para uso real hay que diseñar y verificar autenticación del emisor.

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
# Con el nodo 2b14 transmitiendo
python3 tools/emergency_cli.py --origin 0x82e09b4e --text "Alerta de prueba"
```

Para transmitir por USB a un nodo Meshtastic (requiere `pip install meshtastic` y autorización para usar el puerto):

```bash
# Con el nodo 2b14 transmitiendo
python3 tools/emergency_cli.py --port /dev/ttyACM0 \
    --origin 0x82e09b4e --text "Alerta de prueba" --send
```

Si quieres que esa retransmision también se pueda recibir por el canal de texto normal hay que usar el argumento `--mirror-chat`:

```bash
# Con el nodo 2b14 transmitiendo
python3 tools/emergency_cli.py --port /dev/ttyACM0 \
    --origin 0x82e09b4e --text "Alerta de prueba" --send --mirror-chat
```

**`--origin` debe corresponder al NodeNum real del emisor.** Para consultar el número se puede hacer con el siguiente comando:

```bash
meshtastic --port /dev/ttyACM0 --info
```

Para un mensaje directo que solicita recibo de la aplicación:

```bash
python3 ~/UNI/Q7/meshtastic_emergency_patchkit/tools/emergency_cli.py \
    --port /dev/ttyACM0 \
    --origin 0x82e09b4e \
    --mode alert \
    --severity 3 \
    --text "SOS de prueba desde el nodo 2b14" \
    --send
```

Para visualizar la recepción desde otro puerto USB mediante la API de Meshtastic:

```bash
python3 tools/emergency_cli.py --port /dev/ttyACM1 --listen
```

Para ver el flujo de acciones en la placa receptora, hay que activar la lectura de puertos serie por defecto primero. Después, abrimos el baudrate adecuado desde el terminal de pio:

```bash
# Esto en una terminal normal
meshtastic --port /dev/ttyACM1 \
    --set security.debug_log_api_enabled true

# Esto en la terminal de pio
pio device monitor -p /dev/ACM1 -b 115200
```

Ejemplo de salida de /dev/ACM1:

```bash
Routing sniffing DEBUG | ??:??:?? 25 [RadioIf] Lora RX (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 0, WantAck=0, HopLim=3 Ch=8 encrypted len=75 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=0x4e)
DEBUG | ??:??:?? 25 [RadioIf] Packet RX: 805ms
INFO  | ??:??:?? 25 [RadioIf] EMG_RXQ,accepted=1,evicted=0
DEBUG | ??:??:?? 25 [Router] Use channel 0 (hash 0x8)
DEBUG | ??:??:?? 25 [Router] Expand short PSK #1
DEBUG | ??:??:?? 25 [Router] Use AES128 key
DEBUG | ??:??:?? 25 [Router] decoded message (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=3 Ch=0 Portnum=256 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=0x4e)
DEBUG | ??:??:?? 25 [Router] handleReceived(REMOTE) (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=3 Ch=0 Portnum=256 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay
INFO  | ??:??:?? 25 [Router] EMG_APP_RX,kind=1,origin=82e09b4e,from=82e09b4e,id=c88973e8,severity=3
DEBUG | ??:??:?? 25 [Router] Routing sniffing (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=3 Ch=0 Portnum=256 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=0x4e)
INFO  | ??:??:?? 25 [Router] Rebroadcast msg from 4e
DEBUG | ??:??:?? 25 [Router] Expand short PSK #1
DEBUG | ??:??:?? 25 [Router] Use AES128 key
DEBUG | ??:??:?? 25 [Router] enqueue for send (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=2 Ch=8 encrypted len=75 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=
DEBUG | ??:??:?? 25 [Router] Delivering rx packet (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=3 Ch=0 Portnum=256 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=0
INFO  | ??:??:?? 25 [Router] Sort took 0 ms
DEBUG | ??:??:?? 25 [Router] Forwarding to phone (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=3 Ch=0 Portnum=256 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=0x
DEBUG | ??:??:?? 26 [RadioIf] Started Tx (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=2 Ch=8 encrypted len=75 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay=0x43 p
DEBUG | ??:??:?? 27 [RadioIf] Packet TX: 805ms
DEBUG | ??:??:?? 27 [RadioIf] Completed sending (id=0xa833ad0b fr=0x82e09b4e to=0xffffffff, transport = 1, WantAck=0, HopLim=2 Ch=8 encrypted len=75 rxSNR=12.25 rxRSSI=-57 hopStart=3 relay
```


## Ejecución de pruebas locales (todavía sin testear)

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