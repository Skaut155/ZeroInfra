# Capa de datos Meshtastic: qué se ha cambiado y por qué

Documento de revisión de la rama `rama-SHIQI` (15 y 16 de noviembre). Explica cada pieza nueva o modificada de la app, qué hace y por qué está hecha así, para poder revisarla, defenderla y fusionarla. La guía de uso para las vistas está en [`APP_CAPA_DATOS.md`](APP_CAPA_DATOS.md).

---

## 1. Resumen y estado

- La app ya tiene una capa de datos completa entre las vistas y el nodo Meshtastic: un contrato (`MeshRepository`), una implementación real que habla Protobuf con el nodo por BLE (`MeshtasticClient` sobre `BleMeshTransport` y `MeshtasticBleService`) y una simulada (`FakeMeshRepository`).
- Cuatro providers (`ConnectionProvider`, `NodesProvider`, `ChatProvider`, `SosProvider`) exponen ese estado a las vistas. Solo la pestaña Nodos los usa de momento.
- Los modelos `MeshMessage` y `MeshNode` son los de Carlos ampliados con campos opcionales; su `MeshProvider` simulado y su chat siguen funcionando sin cambios.
- Se han aplicado las correcciones pendientes de `meshtastic_ble_service.dart` y `permission_service.dart`.
- El SOS sigue con el formato provisional (`SOS|v1|...` por `ALERT_APP`); el paso a EMG1 queda para cuando el firmware de Cristina esté cerrado (sección 5).

**Estado: nada de esto se ha compilado ni ejecutado.** Se ha revisado a mano contra el código Protobuf generado (`app/lib/generated/`) y contra la API de flutter_blue_plus 1.36.8. Además, la rama no compila por sí sola: `main.dart` y `test/widget_test.dart` importan `services/mesh_provider.dart`, que solo existe en `main`. Hay que fusionar primero (sección 4) y después pasar:

```bash
cd app
flutter pub get
flutter analyze
flutter test
```

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
| `lib/data/meshtastic/meshtastic_client.dart` | Nuevo (antes, esqueleto sin compilar) | `MeshtasticClient`: protocolo `ToRadio`/`FromRadio`, nodos, canales, texto con acuses, SOS. |
| `lib/data/meshtastic/sos_protocol.dart` | Nuevo | `SosPolicy` y `SosCodec`: formato y política del SOS provisional. |
| `lib/data/ble/mesh_transport.dart` | Nuevo | Interfaz `MeshTransport`: bytes de entrada y salida. |
| `lib/data/ble/ble_mesh_transport.dart` | Nuevo | `BleMeshTransport`: adapta `MeshtasticBleService` a `MeshTransport` y pide permisos. |
| `lib/data/ble/meshtastic_ble_service.dart` | Modificado | Correcciones de conexión y de vaciado de `fromRadio` (sección 3.10). |
| `lib/data/fake/fake_mesh_repository.dart` | Nuevo | Malla simulada. |
| `lib/core/permissions/permission_service.dart` | Modificado | Permisos según plataforma y versión de Android (sección 3.10). |
| `lib/core/constants/meshtastic_ble.dart` | Modificado | Solo comentarios. |
| `lib/models/mesh_message.dart`, `mesh_node.dart` | Modificados | Modelos de Carlos ampliados (sección 3.8). |
| `lib/models/connection_status.dart`, `mesh_channel.dart` | Nuevos (antes vacíos) | Estado de la conexión y canal del nodo. |
| `lib/models/discovered_device.dart` | Nuevo | Resultado del escaneo BLE. |
| `lib/providers/app_providers.dart` | Nuevo | Registra el repositorio y los cuatro providers. |
| `lib/providers/{connection,nodes,chat}_provider.dart` | Nuevos (antes vacíos) | Estado de las vistas Nodos, Mapa y Chat. |
| `lib/providers/sos_provider.dart` | Nuevo | Estado de la vista SOS. |
| `lib/views/nodes/nodes_view.dart` | Modificado | Pestaña Nodos conectada a los providers (escaneo, conexión, lista de nodos). |
| `lib/main.dart` | Modificado | Envuelve la app en `AppProviders`, por fuera del `MeshProvider` de Carlos. |
| `pubspec.yaml` | Modificado | `protobuf` ^6.1.0 y `device_info_plus` ^11.0.0. |
| `android/app/src/main/AndroidManifest.xml` | Modificado | `BLUETOOTH` y `BLUETOOTH_ADMIN` limitados a `maxSdkVersion="30"`. |
| `.gitignore` | Modificado | Ignora `/android/build/`. |
| `test/data/meshtastic_client_test.dart`, `sos_protocol_test.dart` | Nuevos | Tests del cliente y del códec SOS. |
| `test/widget_test.dart` | Nuevo (antes vacío) | La app arranca con la malla simulada. |

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

Cada paquete se envía con `hop_limit` fijado: el que informa el nodo en `config.lora.hop_limit` (si es mayor que 0) o `defaultHopLimit = 3`. El SOS usa `SosPolicy.hopLimit = 7`. Un `MeshPacket` con `hop_limit` 0 (el valor por defecto de Protobuf si no se rellena) solo llega a los vecinos directos, así que nunca se deja sin fijar. El test de `sendText` comprueba que se usa el 5 que envía la configuración de prueba.

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
- Según el puerto: `ROUTING_APP` → acuses; `POSITION_APP` → posición (0,0 significa «sin posición»); `NODEINFO_APP` → nombres; `TELEMETRY_APP` → batería (limitada a 0-100; Meshtastic usa valores mayores de 100 para «alimentado por cable»); `TEXT_MESSAGE_APP` y `ALERT_APP` → `_onText`. Cualquier otro puerto se ignora.
- `_onText` emite un `MeshMessage` en `ack`. Si el texto es un SOS (`SosCodec.tryDecode`), marca el nodo **remitente del paquete** en emergencia (no el id escrito en el texto) y actualiza su posición si la trae.

### 3.7 `PortNum` con `if/else` y Protobuf con prefijo `pb`

- `_dispatch` usa `switch` sobre `FromRadio_PayloadVariant`, que en el código generado es un `enum` de Dart. `PortNum`, en cambio, no es un `enum`: es una clase (`extends ProtobufEnum`) con constantes estáticas. Un `switch` sobre ella no puede comprobar que se cubren todos los casos y la comparación por patrón constante depende de cómo esa clase define la igualdad; con `if/else` y `==` el comportamiento queda explícito. (Este motivo no está comentado en el código.)
- Los ficheros generados se importan todos con el mismo prefijo `pb` (`channel.pb.dart`, `mesh.pb.dart`, `portnums.pbenum.dart`, `telemetry.pb.dart`). Las clases generadas tienen nombres genéricos (`Position`, `Data`, `Channel`, `Config`, `User`, `Constants`, `Telemetry`) que se confundirían con los modelos de la app o con clases de otros paquetes. Con el prefijo, cada línea deja claro qué es formato de red (`pb.Channel`) y qué es modelo de la app (`MeshChannel`). `mesh.pb.dart` reexporta `mesh.pbenum.dart`, por eso `pb.MeshPacket_Priority` y `pb.Constants` funcionan con el mismo prefijo.

### 3.8 Modelos: ampliación de los de Carlos

**Qué se ha hecho.** El 15 de noviembre Carlos subió a `main` su `MeshProvider` simulado y cambió `MeshMessage` (id de texto, `recipientId`, `status` mutable con `queued/transmitted/ack/failed`); su chat ya los usa. Los modelos de Shiqi eran distintos y chocaban. Se han rehecho como **ampliación**: se conservan los campos, tipos, constructor y estados de Carlos y se añaden campos opcionales con valor por defecto.

| Modelo | De Carlos (sin cambios) | Añadido |
|---|---|---|
| `MeshMessage` | `id`, `senderId`, `senderName`, `recipientId`, `content`, `timestamp`, `isMe`, `status` (mutable), `isDirect`, `isEmergency` | `packetId`, `senderNum`, `recipientNum`, `channel`, `isSos`, `broadcastId`, `copyWith({status})`; `isEmergency` también es true con `isSos` |
| `MeshNode` | `id`, `name`, `latitude`, `longitude`, `batteryLevel`, `snr`, `isGateway`, `isEmergency`, `lastHeard` | `nodeNum`, `shortName`, `hopsAway`, `isMe`, `hasPosition`, `hasBattery`, `neverHeard`, `MeshNode.unknown`, `idFromNum`, `copyWith` |

**Por qué.** Así el `MeshProvider` y el chat de Carlos compilan sin tocarlos, y los providers reales producen objetos del mismo tipo que él ya pinta. El día que su chat pase a datos reales no tendrá que cambiar de modelo.

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

### 3.11 `pubspec.yaml`

- `protobuf: ^6.1.0` (antes ^3.1.0). El código de `lib/generated/` sale de `protoc_plugin` 25.1.0, que exige `package:protobuf` 6.1.0 o superior; con la 3.1.0 no compila (ver `docs/PROTOBUF.md`).
- `device_info_plus: ^11.0.0`, para leer la versión de Android en `PermissionService`.

El `pubspec.lock` de `main` (subido por Carlos) fija `protobuf` 3.1.0 y no tiene `device_info_plus`. `flutter pub get` tras la fusión lo actualizará; hay que confirmar ese cambio.

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
| `sendSos aplica SosPolicy y marca el nodo propio en emergencia` | Puerto, prioridad y `hop_limit` de `SosPolicy`; texto decodificable; `isEmergency` del nodo propio a true y, tras `cancelSos`, a false. |
| `un SOS de otro nodo lo marca en emergencia con su posición` | `isEmergency` y latitud del remitente. |
| `sin conexión no se puede enviar` | `StateError`. |
| `al perderse el enlace el cliente queda desconectado` | Estado `disconnected` y `sendText` lanza `StateError`. |

`test/data/sos_protocol_test.dart`: alerta con posición (codifica y decodifica), alerta sin GPS (`SOS|v1|!00000001||`), cancelación, y textos que no son SOS (versión distinta, id sin `!`).

`test/widget_test.dart`: la app arranca con `FakeMeshRepository` y el `MeshProvider` de Carlos y muestra las cuatro pestañas. Necesita la fusión.

**No cubierto por tests:** la regla del acuse implícito en directos, `queue_status`, el límite de 100 acuses, el de 233 bytes, el paso a `failed` de los mensajes en `queued` al perder el enlace, un error de lectura durante la descarga, `BleMeshTransport`, `MeshtasticBleService`, `PermissionService` y los providers.

## 4. Convivencia con el código de Carlos y fusión

### Situación

- `main.dart` registra `AppProviders` (capa real) por fuera del `ChangeNotifierProvider(MeshProvider)` de Carlos. Los dos conviven.
- Solo la pestaña Nodos usa datos reales. El chat de Carlos usa su `MeshProvider` simulado. En el código de `main`, el mapa pinta una lista de nodos fija dentro de `map_view.dart` y la vista SOS guarda su propio estado local; ninguno de los dos lee todavía un provider.

### Cómo fusionar

En el repositorio del equipo, en `rama-SHIQI` y con `origin/main` actualizado (`git fetch origin`):

```bash
git add -A
git commit -m "Capa de datos Meshtastic: repositorio, cliente, providers y tests"
git merge origin/main
git checkout --ours app/lib/main.dart app/lib/models/mesh_message.dart
git add app/lib/main.dart app/lib/models/mesh_message.dart
git commit
cd app && flutter pub get && flutter analyze && flutter test
```

- La fusión da conflicto de texto en `app/lib/main.dart` y `app/lib/models/mesh_message.dart`. La versión de `rama-SHIQI` de ambos ya incluye lo de Carlos (su `MeshProvider` en `main.dart`; sus campos y estados en `MeshMessage`), así que se resuelven quedándose con la propia: durante un `merge`, `--ours` es la rama en la que se está.
- `pubspec.yaml` se fusiona solo.
- **Hasta hacer la fusión, `rama-SHIQI` no compila**: `main.dart` y `test/widget_test.dart` importan `services/mesh_provider.dart`, que solo existe en `main`.
- Tras `flutter pub get`, confirmar también el `pubspec.lock` actualizado (sección 3.11).

### Qué tiene que hacer Carlos para que su chat use datos reales

Los modelos ya son los mismos, así que el cambio está en de dónde salen los datos. Su `MeshProvider` tiene que dejar de generarlos y delegar en `MeshRepository` y los providers. Correspondencia:

| `MeshProvider` (Carlos) | Equivalente real | Nota |
|---|---|---|
| `nodes` | `NodesProvider.nodes` | |
| `connectedNodeId`, `connectedNode` | `NodesProvider.me?.id`, `NodesProvider.me` | |
| `messages` | `ChatProvider.messages` | |
| `getMessagesForChannel(null / 'broadcast')` | `ChatProvider.broadcastMessages(0)` | Los SOS reales son difusiones por el canal 0 con `isSos`, así que ya aparecen ahí. |
| `getMessagesForChannel(nodeId)` | `ChatProvider.directMessages(nodeNum)` | `nodeNum` del nodo con ese `id` en `NodesProvider.nodes`. |
| `sendMessage(text, recipientId:)` | `ChatProvider.sendText(text, toNode: nodeNum)` | `toNode` null = difusión. Devuelve `false` con el motivo en `errorMessage`. |
| `simulateIncomingMessage` | — | Con `FAKE_MESH=true`, `FakeMeshRepository` genera una difusión cada 20 s. |
| `triggerSos()`, `cancelSos()`, `isEmergencyActive` | `SosProvider.send()`, `cancel()`, `isActive` | |
| `isScanning`, `startScan()`, `stopScan()` | `ConnectionProvider.isScanning`, `startScan()`, `stopScan()` | |
| `connectToNode(nodeId)`, `disconnectNode()` | `ConnectionProvider.connect(DiscoveredDevice)`, `disconnect()` | Se conecta a un dispositivo BLE del escaneo, no a un nodo de la malla. |

Alternativa más directa: que `chat_view.dart` lea `ChatProvider` y `NodesProvider` con `context.watch` y deje `MeshProvider` solo para la simulación. Lo deciden Carlos y Shiqi.

Dos detalles de su chat a revisar con él: el texto de ayuda de `ack` dice «ACK confirmado por el receptor», pero en difusión `ack` significa que algún nodo lo retransmitió; y el de `transmitted` dice «Emitido por radio LoRa», pero solo indica que el nodo lo aceptó por BLE.

## 5. SOS y EMG1

### Hoy (provisional)

Todo lo que distingue un SOS está en `lib/data/meshtastic/sos_protocol.dart`:

- `SosPolicy`: puerto `ALERT_APP` (11), prioridad `ALERT`, `hop_limit` 7, canal 0. Un solo paquete por SOS, en difusión y con `want_ack`.
- `SosCodec`: texto `SOS|v1|!a1b2c3d4|lat|lon` (5 decimales; vacíos sin GPS) o `SOS|v1|!a1b2c3d4|CANCEL`.
- Al recibir, se acepta por `ALERT_APP` o `TEXT_MESSAGE_APP`; se marca al remitente del paquete con `isEmergency`, se actualiza su posición y el mensaje aparece en el chat con `isSos`.

Shiqi ha decidido no tocarlo hasta que el firmware esté cerrado.

### Propuesta de Cristina (EMG1)

Formato binario propio dentro de `Data.payload`, por `PRIVATE_APP` (256):

- Cabecera de 20 bytes: `EMG1`, versión 1, `kind`, `severity` (0-3), `flags` (bit 0: pedir recibo en una ALERT unicast), `id` (uint32), `expiresUnix` (uint32), `originNode` (uint32); enteros en little-endian. Después, texto UTF-8 de hasta 160 bytes (total ≤ 180, por debajo de los 233 de Meshtastic).
- Tipos: `ALERT` (1), `RECEIPT` (2), `RESOLVED` (3), `FETCH` (4), `REPLAY` (5).
- Una alerta se identifica por `(originNode, id)`, no por el id del paquete Meshtastic.
- El firmware pone prioridad `ALERT` al reconocer EMG1 en el envío local; no se transmite a los retransmisores.

Su firmware (Meshtastic 2.8.2 modificado) no es definitivo: las pruebas están previstas para el miércoles y todavía no ha conseguido la retransmisión.

### Qué habrá que cambiar en la app cuando el firmware esté cerrado

| Fichero | Cambio |
|---|---|
| Nuevo `lib/data/meshtastic/emg1_codec.dart` (Cristina propone `lib/core/emergency_codec.dart`; decidir la ruta) | Códec binario EMG1 con las validaciones de su documento. Se puede partir de su `EmgCodec`. |
| Nuevo `test/data/emg1_codec_test.dart` | Los cinco vectores hexadecimales de su documento (ALERT, RECEIPT, FETCH, RESOLVED, REPLAY), más longitudes inválidas, texto con acentos y tipos sin texto. |
| `meshtastic_client.dart`, `_onMeshPacket` | Nueva rama `else if (port == pb.PortNum.PRIVATE_APP)`: decodificar con `try/catch FormatException`. Hoy ese puerto se ignora (solo actualiza SNR y `lastHeard` del remitente). |
| `meshtastic_client.dart`, `_send` | Aceptar un payload en bytes además de texto (hoy codifica siempre `String` en UTF-8). |
| `meshtastic_client.dart`, `_sendSos` | `sendSos` → `ALERT` con `originNode = myNodeNum` e `id` nuevo (uint32 no nulo); `cancelSos` → `RESOLVED` con el mismo `(originNode, id)`, así que hay que recordar la última alerta propia. Revisar si se sigue fijando `priority` (lo hace el firmware) y si `want_ack` tiene sentido en difusión. |
| `mesh_repository.dart`, `fake_mesh_repository.dart` | Stream de alertas y, si se acuerda, parámetros de `sendSos` (gravedad, texto). La simulación tiene que implementarlos también. |
| Nuevo `lib/models/emergency_alert.dart` | Modelo de alerta con clave `(originNode, id)` y los campos de su tabla (`severity`, `text`, `expiresUnix`, `senderNode`, `destinationNode`, `channel`, `meshPacketId`, `receivedAt`, estado, `isReplay`). |
| `sos_provider.dart` | Lista de alertas, deduplicación por `(originNode, id)`, estado resuelta, `RECEIPT`. `isActive` dejaría de salir de `MeshNode.isEmergency`. |
| `sos_protocol.dart`, `sos_protocol_test.dart`, rama SOS de `_onText` | Retirarlos. `ALERT_APP` dejaría de usarse para el SOS. |
| `meshtastic_client_test.dart` | Adaptar los dos tests de SOS. |
| `docs/APP_CAPA_DATOS.md`, `docs/BLE_MESHTASTIC.md` | Actualizar la sección SOS y la tabla de puertos. Avisar a Andrés: el SOS pasaría del puerto 11 al 256. |

### Dudas que salen de su documento (para preguntarle)

1. **Versión de firmware y de `.proto`.** Las placas llevarían Meshtastic 2.8.2 modificado, pero `app/lib/generated/` se generó con los `.proto` de 2.7.26 (`docs/PROTOBUF.md`). ¿Se regeneran o se confirma que `ToRadio`/`FromRadio` son compatibles?
2. **Nodos autorizados.** `EMERGENCY_AUTHORIZED_ORIGINS` (en `EmergencyConfig.h`) es una lista por número de nodo. ¿Qué números de nodo se incluyen? Cada T-Beam conectada a un móvil tiene que estar para que sus alertas se procesen.
3. **`expiresUnix`.** ¿0 (sin caducidad absoluta) u hora del móvil más un margen? El firmware aplica además una ventana nominal de una hora desde la recepción.
4. **Posición.** EMG1 no tiene campo de posición y el SOS actual la lleva. ¿Va en el texto, en un paquete `POSITION_APP` aparte o se usa la última posición conocida del nodo?
5. **Gravedad y texto del botón SOS.** Qué `severity` (1-3) y qué texto envía el botón.
6. **Destino, canal y acuse.** ¿Siempre difusión por el canal 0? En difusión no hay `RECEIPT`; ¿se mantiene `want_ack`? ¿Se mantiene `hop_limit` 7?
7. **`RESOLVED`** solo lo acepta el firmware si `originNode` coincide con el remitente: la cancelación tiene que salir del mismo nodo que envió la alerta.
8. **`FETCH`/`REPLAY`.** ¿Cuándo debe pedir la app las alertas almacenadas (al conectar, a mano)? El nodo guarda 8 en RAM y responde una por petición.
9. **Retransmisión.** Mientras no funcione en su firmware, EMG1 solo se puede probar entre vecinos directos.
10. **Revisión de referencia.** Qué revisión de `EmergencyWire.h` se toma como contrato para el códec y los tests.

## 6. Limitaciones y pendiente

- **Sin compilar ni ejecutar**; la rama no compila hasta fusionar con `main`.
- Solo la pestaña Nodos usa datos reales; chat, mapa y SOS siguen con datos simulados o locales.
- **Sin persistencia:** historial y nodos viven en memoria.
- **Sin reconexión automática:** tras perder el enlace hay que volver a vincular.
- Al perder el enlace, los mensajes en `transmitted` dejan de seguirse y se quedan en ese estado.
- Tras desconectar, la lista de nodos se conserva (con el nodo propio aún marcado `isMe`), aunque `myNodeNum` pase a null; `NodesProvider.me` y `SosProvider.isActive` siguen mostrando el último estado.
- `isGateway` sin implementar (siempre false con la placa real).
- Emparejamiento con PIN, UUID con la placa real e iOS: sin probar.
- La simulación no limita el tamaño del texto ni simula fallos.
- SOS provisional (sección 5).
