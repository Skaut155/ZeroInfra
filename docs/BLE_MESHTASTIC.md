# Conexión BLE y Meshtastic

Cómo se comunica la app con el nodo Meshtastic por Bluetooth LE. Referencia: [Client API de Meshtastic](https://meshtastic.org/docs/development/device/client-api/). Código: `app/lib/data/ble/` (transporte) y `app/lib/data/meshtastic/meshtastic_client.dart` (protocolo).

## UUIDs Verificados (LilyGO T-Beam - Firmware 2.7.26)
- **Servicio Principal:** `6ba1b218-15a8-461f-9fa8-5dcae273eafd`
- **Característica toRadio (Escritura):** `f75c76d2-129e-4dad-a1dd-7866124401e7`
- **Característica fromRadio (Lectura):** `2c55e69e-4993-11ed-b878-0242ac120002`
- **Característica fromNum (Notificaciones/Contador):** `ed9da18c-a800-4f66-a670-aa7547e34453`
- **Característica LogRecord (Depuración opcional):** `5a3d6e49-06e6-4423-9944-e9de8cdf9547`

Las constantes están en `app/lib/core/constants/meshtastic_ble.dart`.

## Características y propiedades

Según la Client API de Meshtastic:

| Característica | UUID | Propiedades | Uso en la app |
|---|---|---|---|
| fromRadio | `2c55e69e-4993-11ed-b878-0242ac120002` | read | Se lee repetidamente para sacar los paquetes `FromRadio` pendientes. |
| toRadio | `f75c76d2-129e-4dad-a1dd-7866124401e7` | write | Se escriben los `ToRadio` (con respuesta). |
| fromNum | `ed9da18c-a800-4f66-a670-aa7547e34453` | read, notify, write | Solo se usan sus notificaciones, como aviso de que hay datos en fromRadio. |
| LogRecord | `5a3d6e49-06e6-4423-9944-e9de8cdf9547` | notify | Registros de depuración del firmware (`LogRecord`). La app no lo usa todavía. |

La característica que la Client API marca como **obsoleta** es la de log en texto plano, `6c6fd238-78fa-436b-aacf-15c5be1ef2e2`, que la app no usa. `fromNum` **no** está obsoleta.

## Flujo de conexión

Tal como lo implementan `BleMeshTransport`, `MeshtasticBleService` y `MeshtasticClient`:

1. **Permisos:** `BleMeshTransport` pide los permisos de Bluetooth (ver más abajo) antes de cada escaneo o conexión. Si faltan, lanza `MeshPermissionException`.
2. **Comprobar Bluetooth:** la primera vez se comprueba que el móvil soporta Bluetooth (`StateError` si no). El escaneo espera hasta 5 s a que el adaptador esté encendido (`StateError` «El Bluetooth está apagado» si no). El escaneo filtra por el UUID del servicio y dura como máximo 15 s.
3. **Conectar:** `device.connect()` de flutter_blue_plus. En Android ya negocia un MTU de 512 por defecto, así que no se llama a `requestMtu`; en iOS lo negocia el sistema.
4. **Emparejar (solo Android):** `device.createBond()` muestra el diálogo del PIN si el móvil aún no está emparejado y espera hasta 90 s. Sin este paso, el PIN aparecía al escribir en `toRadio`, cuya escritura caduca a los 15 s, y la primera vinculación fallaba. Si ya estaba emparejado, sigue sin esperar.
5. **Descubrir servicios** y localizar el servicio Meshtastic y sus 3 características (toRadio, fromRadio, fromNum). Si falta alguna, se desconecta y se lanza `StateError`.
6. **Suscribirse a fromNum** (`setNotifyValue(true)`).
7. **Pedir la configuración:** el cliente escribe `ToRadio.want_config_id` con un número aleatorio (≥ 100000, porque el firmware reserva algunos valores menores). Estado `configuring`.
8. **Vaciar fromRadio:** se lee hasta obtener una lectura vacía; cada lectura es un `FromRadio`.
9. **Esperar `config_complete_id`** con el mismo número, con un tiempo máximo de 30 s (`TimeoutException` si no llega). Entonces el estado pasa a `connected` y se publican nodos y canales.
10. A partir de ahí, **cada notificación de fromNum** provoca un vaciado de fromRadio. Si llega un aviso mientras se está vaciando, se da una vuelta más al terminar (nunca hay dos lecturas en paralelo).

Si cualquier paso falla, la app desconecta y vuelve a `disconnected`. Al perderse el enlace, los mensajes propios que aún no se habían entregado al nodo (`queued`) pasan a `failed`.

## Qué procesa el cliente

### Mensajes `FromRadio`

| Variante | Qué hace la app |
|---|---|
| `my_info` | Guarda el número del nodo propio (`my_node_num`). |
| `node_info` | Crea o actualiza un nodo: nombre largo y corto, posición, batería, SNR, saltos y última vez oído. |
| `channel` | Añade o actualiza un canal; los `DISABLED` se quitan. |
| `config` | Solo `config.lora.hop_limit` (si es > 0), que se usa en los envíos de texto. |
| `config_complete_id` | Fin de la descarga, si coincide con el número pedido. |
| `packet` | Un `MeshPacket` de la malla (ver tabla siguiente). |
| `queue_status` | Si `res != 0`, el nodo no pudo encolar el paquete: el mensaje pasa a `failed`. |

El resto de variantes se ignoran. Un `FromRadio` ilegible se descarta sin detener la recepción.

### Puertos de `MeshPacket`

Cualquier paquete de otro nodo actualiza su SNR y su última hora de recepción. Los paquetes sin `decoded` (cifrados con una clave que el nodo no tiene) no se procesan más.

| Puerto | Qué hace la app |
|---|---|
| `TEXT_MESSAGE_APP` (1) | Mensaje de texto; si el texto tiene formato SOS, también es un SOS. |
| `ALERT_APP` (11) | Igual que el anterior; es el puerto por el que la app envía los SOS. |
| `POSITION_APP` (3) | Actualiza la posición del nodo (0,0 se interpreta como «sin posición»). |
| `NODEINFO_APP` (4) | Actualiza nombre largo y corto. |
| `TELEMETRY_APP` (67) | Actualiza la batería (`device_metrics.battery_level`, limitado a 0-100). |
| `ROUTING_APP` (5) | Acuse o error de un paquete propio enviado con `want_ack` (casado por `request_id`). |

## Envío

Los mensajes se envían como `ToRadio.packet` con:

- `to`: el nodo destino, o `0xFFFFFFFF` (difusión).
- `want_ack: true`.
- `id`: aleatorio y generado en la app (no en el nodo), para poder casarlo con el acuse `Routing.request_id`.
- `hop_limit` siempre explícito: el que informa el nodo en su configuración LoRa, o 3 por defecto. Un paquete con `hop_limit` 0 solo llega a los vecinos directos. El SOS usa 7 (ver `SosPolicy` en `docs/APP_CAPA_DATOS.md`).
- `decoded.portnum` y `decoded.payload` (texto en UTF-8, máximo 233 bytes).

Interpretación del acuse: con `error_reason` distinto de `NONE` el mensaje pasa a `failed`. En difusión, cualquier acuse sin error cuenta como `ack` (el firmware genera un acuse implícito al oír que otro nodo retransmite). En un mensaje directo solo cuenta el acuse cuyo remitente es el destinatario.

## Permisos

Ver `app/lib/core/permissions/permission_service.dart`:

- **Android 12 o superior (API 31+):** `BLUETOOTH_SCAN` y `BLUETOOTH_CONNECT`. No hace falta la ubicación porque el manifiesto declara `BLUETOOTH_SCAN` con `neverForLocation`.
- **Android 11 o inferior:** ubicación (sin ella el escaneo BLE no devuelve resultados). Los permisos Bluetooth antiguos se conceden al instalar.
- **iOS:** permiso de Bluetooth.

Si un permiso queda denegado de forma permanente, la vista Nodos ofrece abrir los ajustes del sistema.

## Pendiente de verificar con la placa

- **Emparejamiento / PIN:** probado el 18/11 con una T-Beam. Antes del cambio, la primera vinculación fallaba (ver paso 4). Falta repetir la prueba con un móvil sin emparejar para confirmar la corrección.
- **UUID:** confirmar con nRF Connect que la placa publica el servicio y las características de la tabla anterior.
