# Capa de datos Meshtastic: diseño y decisiones

Explica la capa de datos de la app móvil pieza a pieza: qué hace cada una y por qué está hecha así. La guía de uso para las vistas está en [`APP_CAPA_DATOS.md`](APP_CAPA_DATOS.md).

---

## 1. Resumen

- La app tiene una capa de datos completa entre las vistas y el nodo Meshtastic. Se compone de:
    - un contrato, `MeshRepository`;
    - una implementación real que habla Protobuf con el nodo por BLE: `MeshtasticClient`, sobre `BleMeshTransport` y `MeshtasticBleService`;
    - una implementación simulada, `FakeMeshRepository`.
- Cuatro providers (`ConnectionProvider`, `NodesProvider`, `ChatProvider` y `SosProvider`) exponen ese estado a las cuatro pestañas de la app.
- Los modelos `MeshMessage`, `MeshNode` y `EmergencyAlert` parten de los que definió la interfaz y se amplían con campos opcionales (sección 3.8).
- El SOS viaja en EMG1, el formato de alertas del firmware del proyecto, por `PRIVATE_APP` (256) (sección 4).

**Validación:**
- **Tests:** `flutter analyze` sin errores y 25 tests automáticos que pasan (sección 3.12). Usan un nodo simulado (`FakeTransport`), así que comprueban la lógica del protocolo, pero no el Bluetooth ni el firmware.
- **Con una placa real** (Samsung SM-A346B y una T-Beam): la app conecta, empareja con PIN, descubre las características, se suscribe a `fromNum` y descarga la configuración del nodo.

## 2. Mapa de capas y ficheros

```text
vistas ─→ providers ─→ MeshRepository ─┬─ MeshtasticClient ─→ MeshTransport
                                       │   (Protobuf)          └─ BleMeshTransport
                                       │                           └─ MeshtasticBleService
                                       │                               (flutter_blue_plus)
                                       └─ FakeMeshRepository (sin placa)
```

Rutas relativas a `app/`. «Nuevo» incluye los ficheros que en la última versión confirmada (`9554d6c`) estaban vacíos o eran un esqueleto.

| Fichero | Estado | Qué es |
|---|---|---|
| `lib/data/mesh_repository.dart` | Nuevo | Contrato `MeshRepository` y excepción `MeshPermissionException`. |
| `lib/data/meshtastic/meshtastic_client.dart` | Nuevo | `MeshtasticClient`: protocolo `ToRadio`/`FromRadio`, nodos, canales, texto con acuses, SOS y alertas EMG1. |
| `lib/data/meshtastic/emergency_policy.dart` | Nuevo (23/11) | `EmergencyPolicy` y `EmergencyText`: política del SOS en EMG1 y posición en el texto. Sustituye a `sos_protocol.dart`, que se borra. |
| `lib/models/emergency_alert.dart` | Modificado (23/11) | Modelo de Carlos con tres campos opcionales: `latitude`, `longitude` e `isVerified`. |
| `lib/data/ble/mesh_transport.dart` | Nuevo | Interfaz `MeshTransport`: bytes de entrada y salida. |
| `lib/data/ble/ble_mesh_transport.dart` | Nuevo | `BleMeshTransport`: adapta `MeshtasticBleService` a `MeshTransport` y pide permisos. |
| `lib/data/ble/meshtastic_ble_service.dart` | Modificado | Correcciones de conexión y de vaciado de `fromRadio` (sección 3.10). |
| `lib/data/fake/fake_mesh_repository.dart` | Nuevo | Malla simulada. |
| `lib/core/permissions/permission_service.dart` | Modificado | Permisos según plataforma y versión de Android (sección 3.10). |
| `lib/core/constants/meshtastic_ble.dart` | Modificado | Solo comentarios. |
| `lib/models/mesh_message.dart`, `mesh_node.dart` | Modificado | Modelos de Carlos ampliados (sección 3.8). |
| `lib/models/connection_status.dart`, `mesh_channel.dart` | Nuevo | Estado de la conexión y canal del nodo. |
| `lib/models/discovered_device.dart` | Nuevo | Resultado del escaneo BLE. |
| `lib/providers/app_providers.dart` | Nuevo | Registra el repositorio y los cuatro providers. |
| `lib/providers/{connection,nodes,chat}_provider.dart` | Nuevo | Estado de las vistas Nodos, Mapa y Chat. |
| `lib/providers/sos_provider.dart` | Nuevo | Estado de la vista SOS. |
| `lib/views/nodes/nodes_view.dart` | Modificado | Pestaña Nodos conectada a los providers (escaneo, conexión, lista de nodos). |
| `lib/main.dart` | Modificado | Envuelve la app en `AppProviders`, que registra el repositorio y los providers. |
| `lib/generated/meshtastic/atak.pbenum.dart` | Nuevo | Enums `Team` y `MemberRole` que importa `module_config.pb.dart` (sección 3.11). |
| `pubspec.yaml` | Modificado | `protobuf` ^6.1.0 y `device_info_plus` ^11.0.0. |
| `android/app/src/main/AndroidManifest.xml` | Modificado | `BLUETOOTH` y `BLUETOOTH_ADMIN` limitados a `maxSdkVersion="30"`. |
| `.gitignore` | Modificado | Ignora `/android/build/`. |
| `test/data/meshtastic_client_test.dart`, `emergency_policy_test.dart` | Nuevo | Tests del cliente y de `EmergencyText`. `sos_protocol_test.dart` se borra. |
| `test/widget_test.dart` | Nuevo | La app arranca con la malla simulada. |

## 3. Pieza por pieza

### 3.1 Contrato `MeshRepository` y dos implementaciones

**Qué hace.** `MeshRepository` (`lib/data/mesh_repository.dart`) es la única interfaz de la que dependen los providers. Agrupa:

- conexión: `status`/`statusStream`, `scanResults`, `isScanning`, `startScan`, `stopScan`, `connect(deviceId)`, `disconnect`;
- estado de la malla: `myNodeNum`, `nodes`/`nodesStream`, `channels`/`channelsStream`;
- mensajes: `messages` (stream), `sendText`, `sendSos`, `cancelSos`; y `dispose`.

El contrato fija también los errores: `MeshPermissionException` (faltan permisos; `permanentlyDenied` si hay que ir a los ajustes), `StateError` (Bluetooth apagado, sin conexión, conexión ya en curso, enlace perdido), `TimeoutException` (el nodo no completa la configuración) y `ArgumentError` (texto vacío o demasiado largo).

Hay dos implementaciones: `MeshtasticClient` (nodo real) y `FakeMeshRepository` (simulada). `createMeshRepository()` en `app_providers.dart` elige una u otra.

**Por qué así.**

- Las vistas y los providers no saben si hay placa. Se puede desarrollar la interfaz en el emulador o en escritorio, donde no hay BLE.
- Los tests de widgets arrancan la app con `FakeMeshRepository` sin tocar Bluetooth ni permisos.
- `ConnectionProvider` traduce esas excepciones a mensajes para la interfaz sin conocer flutter_blue_plus ni Protobuf.
- Los streams emiten listas completas (`nodesStream`, `channelsStream`) o mensajes sueltos (`messages`) y el repositorio no guarda historial de mensajes: el estado de cada vista vive en su provider.

### 3.2 `MeshTransport` y `BleMeshTransport`

**Qué hace.** `MeshTransport` (`lib/data/ble/mesh_transport.dart`) solo mueve bytes: escaneo, `connect`/`disconnect`, `linkState` (true al establecerse el enlace, false al perderse), `fromRadioStream` (un evento por paquete `FromRadio`, errores de lectura como error del stream), `writeToRadio(bytes)` y `drainFromRadio()`. No sabe nada de Protobuf; serializar y deserializar es cosa de `MeshtasticClient`.

`BleMeshTransport` (`lib/data/ble/ble_mesh_transport.dart`) implementa esa interfaz sobre el `MeshtasticBleService` existente:

- Convierte `ScanResult` en `DiscoveredDevice` (id en texto, nombre anunciado, el del sistema o «Nodo Meshtastic», RSSI) y guarda cada `BluetoothDevice` visto en `_seen`, para conectar por id sin volver a escanear. Si el id no se ha visto, usa `BluetoothDevice.fromId` (reconectar a un nodo conocido).
- Convierte el estado de conexión de flutter_blue_plus en `linkState` (solo `connected` y `disconnected`).
- Antes de cada escaneo y de cada conexión llama a `_ensureReady()`: pide los permisos (`PermissionService.requestBluetoothPermissions`) y, la primera vez, `initialize()` del servicio. Traduce los fallos: permisos → `MeshPermissionException`; móvil sin Bluetooth → `StateError`; Bluetooth apagado (el `TimeoutException` de `startScan`) → `StateError('El Bluetooth está apagado')`.

**Por qué un adaptador y no cambiar `MeshtasticBleService`.**

- El servicio expone tipos de flutter_blue_plus (`BluetoothDevice`, `ScanResult`, `BluetoothConnectionState`). El adaptador los oculta: por encima de él solo hay `String`, `bool`, `List<int>` y modelos de la app.
- Con la interfaz `MeshTransport`, el cliente Protobuf se prueba con un transporte de mentira (`FakeTransport`, sección 3.11), sin Bluetooth ni placa.
- Los permisos se piden justo antes de escanear o conectar, no al arrancar la app: el diálogo del sistema aparece cuando el usuario pulsa «Escanear» o «Vincular» y entiende para qué es.
- El servicio de bajo nivel conserva su responsabilidad (GATT y lectura de `fromRadio`) y no se mezcla con permisos ni con modelos de la app.

### 3.3 Conexión y descarga de la configuración (handshake)

**Qué hace.** `MeshtasticClient.connect(deviceId)`:

1. Rechaza la llamada si el estado no es `disconnected` (`StateError`).
2. `connecting`: `_transport.connect(deviceId)`.
3. `configuring`: `_downloadConfig()`.
4. `connected`: corrige la marca `isMe` del nodo propio por si su ficha llegó antes que `my_info`, y publica nodos y canales.
5. Si cualquier paso falla: desconecta el transporte, vuelve a `disconnected` y relanza el error.

`_downloadConfig()` vacía el estado anterior (nodo propio, `hop_limit`, nodos, canales, acuses pendientes), genera un nonce, escribe `ToRadio(want_config_id: nonce)`, llama una vez a `drainFromRadio()` y espera a recibir `FromRadio.config_complete_id` con el mismo nonce, con un límite de 30 s (`configTimeout`, que los tests reducen a 200 ms). Mientras tanto, `_dispatch` va procesando `my_info` (número del nodo propio), `node_info`, `channel` y `config` (de la configuración LoRa toma el `hop_limit`).

**Por qué así.**

- **Nonce aleatorio a partir de 100000** (`100000 + nextInt(0x7FFFFFFF - 100000)`): por debajo de 100000 hay valores que el firmware reserva con significado especial (69420 y 69421, según el comentario del código). Un nonce aleatorio permite además ignorar un `config_complete_id` que no corresponda a esta petición.
- **Vaciado inicial explícito.** Tras `want_config_id` el cliente tiene que empezar a leer `fromRadio`; no se espera a un aviso de `fromNum`. Después, el transporte vacía solo con cada aviso del nodo. Es lo que documenta `MeshTransport.drainFromRadio`.
- **Límite de 30 s.** Sin él, un nodo que no termina dejaría la conexión colgada en `configuring`. Al vencer se lanza `TimeoutException` y el estado vuelve a `disconnected`.
- **`Completer` con `ignore()`.** El final de la descarga se señala con un `Completer` (`_configDone`). Si el enlace cae (`_handleLinkDown`) o llega un error de lectura (`_onReadError`) mientras se está escribiendo `want_config_id` o vaciando, se completa con error antes de que nadie haga `await` sobre él. Un `Future` que falla sin oyente se notifica como error no capturado; `done.future.ignore()` lo evita, y el `await` posterior recibe el error igualmente.
- **Las listas no se publican durante la descarga.** `_publishNodes` y `_publishChannels` no hacen nada en `configuring`: el nodo envía una ficha por cada nodo que conoce y publicar cada una provocaría una notificación por ficha y una lista a medias en pantalla. Se publican una sola vez al llegar a `connected`. Mientras, los providers conservan la lista anterior.
- **Por qué se toca `isMe` al final.** `_updateNode` calcula `isMe` comparando con `_myNodeNum`; si la ficha del nodo propio llegara antes que `my_info`, quedaría con `isMe = false`. Volver a pasarla por `_updateNode` al terminar lo corrige.

**Pérdida del enlace** (`_handleLinkDown`): completa con error la descarga en curso, marca `failed` los mensajes propios aún en `queued`, olvida los acuses pendientes, pone `myNodeNum` a null y el estado a `disconnected`. No borra la lista de nodos.

### 3.4 `hop_limit` siempre explícito

Cada paquete se envía con `hop_limit` fijado: el que informa el nodo en `config.lora.hop_limit` (si es mayor que 0) o `defaultHopLimit = 3`. El SOS usa `EmergencyPolicy.hopLimit = 7`. Un `MeshPacket` con `hop_limit` 0 (el valor por defecto de Protobuf si no se rellena) solo llega a los vecinos directos, así que nunca se deja sin fijar. El test de `sendText` comprueba que se usa el 5 que envía la configuración de prueba.

### 3.5 Envío de texto, id de paquete y estados de entrega

**Qué hace `_send`.**

1. Exige `connected` y `myNodeNum` (si no, `StateError`).
2. Codifica el texto en UTF-8; rechaza vacío o más de `maxPayloadBytes` (`ArgumentError`).
3. Genera el id del paquete en la app: `1 + nextInt(0xFFFFFFFF)`, nunca 0.
4. Construye `MeshPacket` con `to` (destino o `0xFFFFFFFF`), `channel`, `id`, `want_ack: true`, `hop_limit`, prioridad (solo SOS) y `decoded: Data(portnum, payload)`.
5. Crea el `MeshMessage` en `queued`, lo guarda en `_pendingAcks` (por id de paquete) y lo emite.
6. Escribe `ToRadio(packet)`. Si la escritura falla, `failed` y relanza. Si va bien, `transmitted`, y devuelve el mensaje.

**Por qué el id se genera en la app.** El acuse llega como un paquete `ROUTING_APP` cuyo `Data.request_id` es el id del paquete original. Si lo asignara el nodo, la app no sabría qué id esperar. Generándolo aquí, `_onRouting` busca `_pendingAcks[data.requestId]` directamente.

**Estados** (los de Carlos, `MessageStatus`):

| Estado | Cuándo |
|---|---|
| `queued` | Creado, aún no entregado al nodo por BLE. |
| `transmitted` | La escritura en `toRadio` terminó: el nodo lo aceptó. No implica que haya salido por radio. |
| `ack` | Acuse sin error (ver abajo). También es el estado de todo mensaje recibido. |
| `failed` | Falló la escritura; `queue_status` con `res != 0`; acuse con `error_reason` distinto de `NONE`; o se perdió el enlace estando en `queued`. |

**Difusión frente a directo.** En una difusión no hay destinatario que confirme: el firmware genera un acuse «implícito» al oír que otro nodo retransmite el paquete, y eso cuenta como `ack`. En un mensaje directo, ese acuse implícito (con `from` igual al nodo propio) solo indica que la malla lo reenvió, no que el destinatario lo recibiera; por eso solo cuenta el acuse cuyo `from` es el destinatario (`packet.from == pending.recipientNum`). Si nunca llega, el mensaje se queda en `transmitted`.

**`queue_status`.** El nodo informa por `FromRadio.queue_status` si ha podido encolar un paquete para emitirlo. Con `res != 0` el paquete no saldrá, y el mensaje con ese `mesh_packet_id` pasa a `failed`.

**Un acuse no hace retroceder el estado.** Si el acuse llegara antes de terminar la escritura BLE, `_setDeliveryStatus` no vuelve de `ack` a `transmitted`. Los estados `ack` y `failed` son finales y sacan el mensaje de `_pendingAcks`.

**Límite de 100 acuses pendientes.** Un mensaje cuyo acuse no llega nunca (un directo sin respuesta, una difusión que nadie retransmite) se quedaría en `_pendingAcks` para siempre. Al llegar a 100 se descarta el más antiguo; ese mensaje conserva su último estado.

**Límite de 233 bytes.** Es `pb.Constants.DATA_PAYLOAD_LEN` del código generado, el tamaño máximo de `Data.payload`. Se cuenta en bytes UTF-8, no en caracteres (una letra con tilde ocupa 2). La simulación no lo comprueba.

**Id del mensaje en la app.** `MeshMessage.id` es `"<senderId>_<packetId>"` (por ejemplo `!00000002_77`): los ids de paquete solo son únicos por remitente. `ChatProvider` usa ese id para sustituir un mensaje cuando cambia su estado. El id de paquete está aparte, en `packetId`.

### 3.6 Recepción

`_onFromRadio` deserializa cada `FromRadio` dentro de un `try`: un paquete ilegible se descarta sin detener la recepción. `_dispatch` reparte por `whichPayloadVariant()`. Para cada `MeshPacket` (`_onMeshPacket`):

- Si viene de otro nodo, actualiza su SNR (si no es 0) y su `lastHeard`.
- Sin `decoded` (cifrado con una clave que el nodo no tiene) no se procesa más.
- Según el puerto: `ROUTING_APP` → acuses; `POSITION_APP` → posición (0,0 significa «sin posición»); `NODEINFO_APP` → nombres; `TELEMETRY_APP` → batería (limitada a 0-100; Meshtastic usa valores mayores de 100 para «alimentado por cable»); `TEXT_MESSAGE_APP` → mensaje de texto; `PRIVATE_APP` → `_onEmergency` (sección 4). Cualquier otro puerto se ignora.
- `_emitReceived` publica el `MeshMessage` en `ack`, tanto para un texto como para un SOS (en ese caso, con `isSos` y un texto legible).

### 3.7 `PortNum` con `if/else` y Protobuf con prefijo `pb`

- `_dispatch` usa `switch` sobre `FromRadio_PayloadVariant`, que en el código generado es un `enum` de Dart. `PortNum`, en cambio, no es un `enum`: es una clase (`extends ProtobufEnum`) con constantes estáticas. Un `switch` sobre ella no puede comprobar que se cubren todos los casos y la comparación por patrón constante depende de cómo esa clase define la igualdad; con `if/else` y `==` el comportamiento queda explícito. (Este motivo no está comentado en el código.)
- Los ficheros generados se importan todos con el mismo prefijo `pb` (`channel.pb.dart`, `mesh.pb.dart`, `portnums.pbenum.dart`, `telemetry.pb.dart`). Las clases generadas tienen nombres genéricos (`Position`, `Data`, `Channel`, `Config`, `User`, `Constants`, `Telemetry`) que se confundirían con los modelos de la app o con clases de otros paquetes. Con el prefijo, cada línea deja claro qué es formato de red (`pb.Channel`) y qué es modelo de la app (`MeshChannel`). `mesh.pb.dart` reexporta `mesh.pbenum.dart`, por eso `pb.MeshPacket_Priority` y `pb.Constants` funcionan con el mismo prefijo.

### 3.8 Modelos: ampliación de los de la interfaz

**Qué se ha hecho.** La interfaz (Carlos) y la capa de datos (Shiqi) se desarrollaron en paralelo, y cada una definió al principio sus propios modelos. La interfaz ya pintaba `MeshMessage` con id de texto, `recipientId` y `status` mutable (`queued/transmitted/ack/failed`). En vez de sustituirlos, los modelos se han rehecho como **ampliación**: se conservan los campos, tipos, constructor y estados de la interfaz y se añaden campos opcionales con valor por defecto.

| Modelo | De Carlos (sin cambios) | Añadido |
|---|---|---|
| `MeshMessage` | `id`, `senderId`, `senderName`, `recipientId`, `content`, `timestamp`, `isMe`, `status` (mutable), `isDirect`, `isEmergency` | `packetId`, `senderNum`, `recipientNum`, `channel`, `isSos`, `broadcastId`, `copyWith({status})`; `isEmergency` también es true con `isSos` |
| `MeshNode` | `id`, `name`, `latitude`, `longitude`, `batteryLevel`, `snr`, `isGateway`, `isEmergency`, `lastHeard` | `nodeNum`, `shortName`, `hopsAway`, `isMe`, `hasPosition`, `hasBattery`, `neverHeard`, `MeshNode.unknown`, `idFromNum`, `copyWith` |

**Por qué.** Así las vistas siguieron compilando sin tocarlas mientras se desarrollaba la capa de datos, y los providers reales producen objetos del mismo tipo que las vistas ya pintaban. Cuando las vistas pasaron a datos reales, no tuvieron que cambiar de modelo.

**Coste.** Los campos de Carlos no admiten null, así que «no hay dato» se expresa de otra forma:

| Falta de dato | Cómo se indica | Valor del campo |
|---|---|---|
| Posición | `hasPosition == false` | `latitude`/`longitude` = 0 (que es un punto real, en el golfo de Guinea) |
| Batería | `hasBattery == false` | `batteryLevel` = 0 |
| Nunca oído | `lastHeard == MeshNode.neverHeard` | instante 0 de la época Unix |
| SNR | `snr == 0` | un SNR real de 0,0 dB se ve como desconocido |

Consecuencias: quien pinte un nodo tiene que mirar los flags antes de usar esos campos; `hasPosition` y `hasBattery` valen true por defecto para que los nodos del simulador de Carlos (que siempre traen datos) sigan igual; `copyWith` trata null como «no cambiar», así que `hopsAway` no puede volver a null y la posición solo cambia si llegan las dos coordenadas. Pasar posición o batería a `copyWith` pone el flag correspondiente a true. El constructor ya no es `const` (el de Carlos no lo era).

`status` sigue siendo mutable porque el simulador de Carlos lo cambia en el sitio; la capa real nunca lo modifica: emite una copia con `copyWith(status: ...)` y el mismo `id`.

### 3.9 Providers

**Qué hace cada uno.**

| Provider | Vista | Expone |
|---|---|---|
| `ConnectionProvider` | Nodos | `status`, `isConnected`, `isScanning`, `devices`, `connectedDevice`, `errorMessage`, `needsSettings`; `startScan`, `stopScan`, `connect(DiscoveredDevice)`, `disconnect`, `openSettings`, `clearError`. Sus métodos no lanzan: `_run` convierte cada excepción en `errorMessage`. |
| `NodesProvider` | Mapa (y lista de Nodos) | `nodes`, `me`, `others`, `withPosition` (filtra por `hasPosition`), `byNum`. |
| `ChatProvider` | Chat | `messages` (historial acumulado), `channels`, `errorMessage`, `broadcastMessages(channel)`, `directMessages(nodeNum)`, `sendText`. Sustituye un mensaje por id al cambiar su estado. |
| `SosProvider` | SOS | `isActive` (el nodo propio tiene `isEmergency`), `isSending` (evita envíos dobles), posición del nodo propio, `lastSignal`, `errorMessage`; `send`, `cancel`. |

**Por qué uno por vista.** Cada vista escucha solo lo que pinta; un mensaje nuevo no redibuja el mapa ni un cambio de batería el chat. Todos dependen solo de `MeshRepository`.

**Por qué `lazy: false`.** `AppProviders` los crea al arrancar. `MeshRepository.messages` no guarda historial y sus streams son broadcast: lo que se emite sin oyente se pierde. Si `ChatProvider` se creara al abrir la pestaña Chat, los mensajes llegados antes no aparecerían nunca.

**`--dart-define=FAKE_MESH=true`.** `kUseFakeMesh = bool.fromEnvironment('FAKE_MESH')` es una constante de compilación: se pasa en `flutter run` (o `build`/`test`) y `createMeshRepository()` crea `FakeMeshRepository` en lugar de `MeshtasticClient(BleMeshTransport())`. `AppProviders` acepta además un `repository` para los tests.

**La simulación** (`FakeMeshRepository`): el escaneo encuentra un dispositivo al cabo de 1 s; al conectar crea 4 nodos alrededor del Campus Nord (el propio, un gateway, un repetidor a 1 salto y uno creado con `MeshNode.unknown`, sin posición ni batería) y 2 canales (primario y `Rescate`); cada 20 s llega una difusión de otro nodo; los envíos pasan por `queued` → `transmitted` (0,3 s) → `ack` (1,5 s). No limita el tamaño ni simula fallos.

### 3.10 Correcciones de `meshtastic_ble_service.dart` y `permission_service.dart`

Comparación con la versión `9554d6c`.

**`MeshtasticBleService`**

| Problema en `9554d6c` | Corrección |
|---|---|
| No compilaba: el aviso de `fromNum` llamaba a `_drainFromRadio()` (el método es `drainFromRadio`) y el bucle usaba `_drain_Again`. | Nombres corregidos. |
| `_drainAgain` no se bajaba nunca dentro del bucle: una vez a true, el vaciado se repetía sin fin. | Se baja al empezar cada vuelta; un aviso que llegue durante la vuelta la vuelve a subir y se da exactamente una vuelta más. |
| `_clear()` bajaba `_isReading` y `_drainAgain`: una desconexión durante un vaciado permitía arrancar otro en paralelo. | `_clear()` ya no los toca; solo los libera el `finally` del vaciado. |
| Tras una reconexión, un vaciado en marcha seguía leyendo la característica de la conexión anterior. | Se compara `identical(characteristic, _fromRadio)`: los bytes de una conexión cerrada se descartan y, si hay una nueva, se vacía esa. |
| Los errores de lectura solo se escribían con `debugPrint` y cortaban el bucle sin avisar a nadie. | Se publican como error en `fromRadioStream` (el cliente los usa para abortar la descarga de configuración); los de una conexión ya cerrada se ignoran. |
| Cada `connect` añadía un listener a `connectionState` con `cancelWhenDisconnected(delayed: true, next: true)`: los de intentos fallidos se acumulaban. Además, `connectionState` emite el estado actual al suscribirse (`disconnected` antes de conectar), que se tomaba por una desconexión real. | Una sola suscripción guardada en `_connSub`, cancelada de forma explícita; un contador de intentos (`_attempt`) descarta eventos de intentos anteriores; los `disconnected` previos a ver `connected` se ignoran. Si se cancela la suscripción tras haber visto `connected`, se emite `disconnected` a mano. |
| Nada impedía dos `connect` simultáneos. | `_isConnecting` lanza `StateError`; conectar al mismo dispositivo no hace nada; a otro distinto, desconecta primero. |
| Las características se asignaban a los campos antes de comprobar que estaban las tres. | Se buscan en variables locales y se guardan solo al final, tras comprobar que el nodo sigue conectado y el intento es el actual. |
| `requestMtu(512)` en Android (con `import 'dart:io'`). | Eliminado: en flutter_blue_plus `connect()` ya pide un MTU de 512 en Android (parámetro `mtu`). |
| `dispose` no invalidaba listeners ni la suscripción de conexión. | Incrementa `_attempt` y cancela `_connSub`. |

**`PermissionService`**

| Problema en `9554d6c` | Corrección |
|---|---|
| Pedía siempre `bluetoothScan`, `bluetoothConnect` y `location`, en cualquier plataforma y versión. En Android 12+ la ubicación sobra (el manifiesto declara `BLUETOOTH_SCAN` con `neverForLocation`) y, si el usuario la denegaba, el BLE quedaba bloqueado. En Android 11 o inferior los permisos de escaneo y conexión no se piden en ejecución. En iOS no pedía `Permission.bluetooth`. | `_requiredPermissions()` según plataforma: Android 12+ (API 31, leída con `device_info_plus`) → escaneo y conexión; Android ≤ 11 → ubicación; iOS → `bluetooth`. |
| Devolvía `bool`: no distinguía «denegado» de «denegado para siempre», así que la app no podía ofrecer abrir los ajustes. | Devuelve `BlePermissionStatus` (`granted`, `denied`, `permanentlyDenied`); `restricted` cuenta como `permanentlyDenied`. |
| `checkPermissions()` comprobaba permisos distintos de los que pedía `requestBluetoothPermissions()`. | Los dos usan `_requiredPermissions()`. |

En el manifiesto, `BLUETOOTH` y `BLUETOOTH_ADMIN` llevan ahora `maxSdkVersion="30"`: solo hacen falta hasta Android 11.

**Emparejamiento con PIN (añadido el 18/11, tras la primera prueba con la placa).** En el primer intento de cada móvil la vinculación fallaba y el segundo funcionaba. El firmware de Meshtastic exige un enlace cifrado para escribir en `toRadio`. Como el móvil no estaba emparejado, Android lanzaba el diálogo del PIN al escribir `want_config_id`, y esa escritura caduca a los 15 s (límite de `write()` en flutter_blue_plus): si el PIN tardaba más, la conexión se abortaba y el emparejamiento terminaba justo después. Ahora `connect()` llama a `device.createBond()` en Android justo después de conectar, antes de cualquier escritura. Esa llamada espera hasta 90 s al PIN y vuelve enseguida si el móvil ya estaba emparejado. Si el usuario cancela o el PIN es incorrecto, se lanza un `StateError` con un mensaje para la pantalla de Nodos.

### 3.11 `pubspec.yaml`

- `protobuf: ^6.1.0` (antes ^3.1.0). El código de `lib/generated/` sale de `protoc_plugin` 25.1.0, que exige `package:protobuf` 6.1.0 o superior; con la 3.1.0 no compila (ver `docs/PROTOBUF.md`).
- `device_info_plus: ^11.0.0`, para leer la versión de Android en `PermissionService`.

**`atak.pbenum.dart`.** `module_config.pb.dart` importa `atak.pbenum.dart`, que no se había generado aunque `protos/meshtastic/atak.proto` sí estaba en el repositorio. `flutter analyze` no lo detectaba porque `analysis_options.yaml` excluye `lib/generated/`; los tests no compilaban. Se ha regenerado con el comando de `docs/PROTOBUF.md`, que ahora incluye `atak.proto` y `field_metadata.proto`.

### 3.12 Tests

**`FakeTransport`** (en `test/data/meshtastic_client_test.dart`) hace de nodo:

- Sus `StreamController` son `broadcast(sync: true)`: cada `add` llega al cliente en el acto.
- Guarda cada `ToRadio` escrito en `written`.
- Al recibir `want_config_id` (si `answerConfig` es true) deja en un buzón los `configPackets` y un `config_complete_id` con el mismo nonce. **El buzón solo se entrega cuando el cliente llama a `drainFromRadio()`**, así que el test de conexión comprueba también que el cliente hace el vaciado inicial.
- `push()` simula un paquete que llega de la malla; `dropLink()`, la pérdida del enlace.
- `settle()` deja pasar una vuelta del bucle de eventos para que lleguen los mensajes del stream `messages` del cliente, que no es síncrono.

La configuración de prueba: nodo propio `1` (sin posición), vecino `2` («Vecino», posición 41.38879, 2.11296, batería 88), `hop_limit` 5, canales 0 (primario), 1 (`Rescate`) y 2 (deshabilitado). `configTimeout` de 200 ms.

| Test | Comprueba |
|---|---|
| `connect descarga nodos y canales y queda conectado` | Estado `connected`, `myNodeNum`, una sola escritura (`want_config_id`), 2 nodos, `isMe` y `hasPosition` del propio, nombre, id, posición y batería del vecino, canal deshabilitado oculto. |
| `si el nodo no completa la configuración, connect falla` | `TimeoutException` y estado `disconnected`. |
| `un texto de otro nodo se publica como mensaje recibido` | Contenido, `senderNum`, `senderName`, difusión (`recipientId == broadcastId`), estado `ack`. |
| `sendText escribe el paquete y sigue su entrega hasta el acuse` | Devuelve `transmitted`; paquete en difusión, `want_ack`, `hop_limit` 5, puerto de texto, id igual a `packetId`; tras el acuse: `queued`, `transmitted`, `ack`. |
| `un error de routing marca el mensaje como fallido` | Directo + `MAX_RETRANSMIT` → `failed`. |
| `sendSos difunde un EMG1 ALERT con la posición propia` | Difusión por el canal 0, `PRIVATE_APP`, prioridad y `hop_limit` de `EmergencyPolicy`; cabecera EMG1 (ALERT, origen propio, id distinto de 0, gravedad 3, flags 0); texto `@41.38879,2.11296 SOS`; nodo propio en emergencia. |
| `cancelSos envía RESOLVED con el id del SOS y no se repite` | RESOLVED con el mismo id y origen; quita la emergencia; un segundo `cancelSos` lanza `StateError`. |
| `el SOS propio sigue activo tras reconectar con el mismo nodo` | Tras perder el enlace y reconectar, el nodo propio sigue en emergencia y se puede cancelar. |
| `un ALERT recibido marca el nodo y publica la alerta` | Emergencia y posición del nodo; alerta con texto, `isVerified` y posición; `activeAlerts`; mensaje legible en el chat. |
| `un RESOLVED cancela la alerta y quita la emergencia` | `activeAlerts` vacío, `status` resuelta y nodo sin emergencia. |
| `se descartan origen falso, repetidos, caducados y no EMG1` | De cinco paquetes solo cuenta una alerta. |
| `sin firma verificada la alerta queda como no verificada` | `isVerified` false sin firma y en un REPLAY; «no verificada» en el chat. |
| `sin conexión no se puede enviar` | `StateError`. |
| `al perderse el enlace el cliente queda desconectado` | Estado `disconnected` y `sendText` lanza `StateError`. |

`test/data/emergency_policy_test.dart`: posición en el texto (con y sin GPS, lectura, fuera de rango, mal formada), que el texto quepa en EMG1 y vuelva igual, y el texto legible del chat.

`test/widget_test.dart`: la app arranca con `FakeMeshRepository` y muestra las cuatro pestañas.

**No cubierto por tests:** la regla del acuse implícito en directos, `queue_status`, el límite de 100 acuses, el de 233 bytes, el paso a `failed` de los mensajes en `queued` al perder el enlace, un error de lectura durante la descarga, `BleMeshTransport`, `MeshtasticBleService`, `PermissionService` y los providers.

## 4. SOS y EMG1

Desde el 23/11 el SOS viaja en **EMG1**, el formato binario del firmware de Cristina (`EmergencyWire.h`). Su firmware solo trata un paquete como alerta, y le da prioridad en cada salto, si es un EMG1 ALERT por `PRIVATE_APP` (256), con `originNode` igual al emisor y con la firma verificada. El SOS provisional (`SOS|v1|...` por `ALERT_APP`) no cumplía nada de eso.

### Ficheros

- `lib/core/emergency_codec.dart` (Carlos): códec EMG1. Coincide byte a byte con `EmergencyWire.h` y se usa sin cambios.
- `lib/data/meshtastic/emergency_policy.dart`: `EmergencyPolicy` (puerto, prioridad, saltos, canal, gravedad 3, sin caducidad, texto `SOS`) y `EmergencyText` (posición en el texto y texto legible para el chat).
- `lib/models/emergency_alert.dart` (Carlos): se añaden `latitude`, `longitude` e `isVerified`, opcionales.
- `sos_protocol.dart` y `sos_protocol_test.dart` se borran.

### Envío

- `sendSos` difunde un ALERT con `originNode = myNodeNum`, un `id` aleatorio distinto de 0, gravedad 3, `flags = 0` y el texto `@lat,lon SOS` (o `SOS` sin GPS). **Por qué en difusión:** Meshtastic solo firma las difusiones, y sin firma los retransmisores no dan prioridad.
- **Por qué un id nuevo en cada SOS:** el firmware descarta durante una hora un (origen, id) que ya ha visto.
- `cancelSos` difunde un RESOLVED con el mismo `id`, así que el cliente recuerda el SOS activo (`_ownSos`). Se conserva tras reconectar con el mismo nodo; con otro nodo se olvida, porque el firmware solo acepta el RESOLVED del mismo origen. Sin SOS activo, `cancelSos` lanza `StateError`.
- `_send` acepta ahora bytes (`payload`) y, aparte, el texto que se muestra en el chat (`content`).
- **Por qué la posición va en el texto:** EMG1 no tiene campos de posición. Con 5 decimales (≈ 1 m) el EMG1 ocupa unos 40 bytes, para que quepa la firma.

### Recepción (`_onEmergency`)

- **Validación:** se descartan los paquetes propios y lo que `EmgCodec.decode` no acepta.
- **ALERT:** solo si `originNode == packet.from` (la misma regla que el firmware). Marca el nodo en emergencia con la posición del texto, crea un `EmergencyAlert` y lo emite por `alerts` y, como mensaje con `isSos`, por `messages`.
- **REPLAY:** una alerta guardada que reenvía otro nodo; no exige esa regla, pero nunca cuenta como verificada, porque la firma es la de quien la reenvía.
- **RESOLVED:** con la misma regla de origen, quita la alerta de `activeAlerts`, la marca `resolved` y quita la emergencia del nodo si no le queda otra alerta.
- **Duplicados:** cada (origen, id) se procesa una vez (`_seenAlerts`, hasta 200). Un RESOLVED que llega antes que su ALERT hace que el ALERT se descarte después.
- **Sin procesar:** las alertas caducadas (`expiresUnix` en el pasado) se ignoran, y RECEIPT y FETCH los gestiona el firmware.
- **`isVerified` = `MeshPacket.xeddsa_signed`:** lo pone el firmware tras verificar la firma; ya estaba en nuestros `.proto`.
- **Reconexión:** las alertas activas se conservan y, como la descarga vacía los nodos, se vuelven a marcar.

### Interfaz nueva

- `MeshRepository.alerts` (`Stream<EmergencyAlert>`) y `MeshRepository.activeAlerts`.
- `SosProvider.alerts`: las alertas activas de otros nodos, para la vista SOS.
- `sendSos` y `cancelSos` mantienen la firma; la vista SOS de Carlos no cambia.
- **Simulación:** `FakeMeshRepository` envía un SOS verificado a los 30 s, que se cancela 60 s después, y uno sin verificar a los 45 s.

### Pendiente

- Probar con dos placas con el firmware de Cristina: que el SOS aparezca como `EMG_APP_RX` en el receptor y, en un retransmisor, `EMG_RELAY_PRIORITY`.
- Medir el tamaño máximo del texto con la firma.
- Si la app se cierra con un SOS activo, se pierde su id y no se puede cancelar desde la app.
- No se piden las alertas guardadas en el nodo (FETCH) al conectar.

## 5. Limitaciones y pendiente

- **Prueba con la placa a medias:** la conexión y la descarga de la configuración funcionan; falta comprobar la lista de nodos, los mensajes y la corrección del emparejamiento.
- **Sin persistencia:** historial y nodos viven en memoria.
- **Sin reconexión automática:** tras perder el enlace hay que volver a vincular.
- Al perder el enlace, los mensajes en `transmitted` dejan de seguirse y se quedan en ese estado.
- Tras desconectar, la lista de nodos se conserva (con el nodo propio aún marcado `isMe`), aunque `myNodeNum` pase a null; `NodesProvider.me` y `SosProvider.isActive` siguen mostrando el último estado.
- `isGateway` sin implementar (siempre false con la placa real).
- Emparejamiento con PIN, UUID con la placa real e iOS: sin probar.
- La simulación no limita el tamaño del texto ni simula fallos.
- SOS: ver «Pendiente» en la sección 4.
