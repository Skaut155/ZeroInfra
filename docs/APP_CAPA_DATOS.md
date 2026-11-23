# Capa de datos de la app: guía para las vistas

Esta guía explica cómo conectar las vistas de Flutter (chat, mapa, SOS) a la malla, real o simulada, usando los providers. Las vistas no necesitan tocar Bluetooth ni Protobuf. El detalle de cada pieza y el porqué de su diseño está en [`CAMBIOS_CAPA_DATOS.md`](CAMBIOS_CAPA_DATOS.md).

> **Estado:** todo este código se ha escrito sin poder compilarlo ni probarlo con hardware. Además, `rama-SHIQI` no compila hasta fusionarla con `main`, porque `main.dart` y `test/widget_test.dart` importan `services/mesh_provider.dart`. Tras la fusión hay que pasar `flutter pub get`, `flutter analyze` y `flutter test` (ver [Limitaciones](#8-limitaciones-conocidas-y-pendiente)).

---

## 1. Capas

| Capa | Ficheros (`app/lib/`) | Qué hace |
|---|---|---|
| Vistas | `views/` | Pintan el estado y llaman a los providers. |
| Providers | `providers/` | `ChangeNotifier` con el estado de cada vista. Se registran en `app_providers.dart`. |
| Contrato | `data/mesh_repository.dart` | `MeshRepository`: interfaz única de la que dependen los providers. |
| Protocolo Meshtastic | `data/meshtastic/meshtastic_client.dart` | `MeshtasticClient`: implementa `MeshRepository` hablando `ToRadio`/`FromRadio` (Protobuf). |
| SOS | `data/meshtastic/emergency_policy.dart` | `EmergencyPolicy` y `EmergencyText`: cómo viaja un SOS en EMG1 y cómo se escribe la posición en su texto. El códec binario es `core/emergency_codec.dart` (Carlos). |
| Transporte | `data/ble/mesh_transport.dart` | `MeshTransport`: bytes de entrada y salida, sin Protobuf. |
| BLE | `data/ble/ble_mesh_transport.dart` → `data/ble/meshtastic_ble_service.dart` | `BleMeshTransport` (permisos y adaptación) sobre `MeshtasticBleService` (flutter_blue_plus). |
| Simulación | `data/fake/fake_mesh_repository.dart` | `FakeMeshRepository`: otra implementación de `MeshRepository`, sin placa. |

```
vistas → providers → MeshRepository ─┬─ MeshtasticClient → MeshTransport
                                     │     (BleMeshTransport → MeshtasticBleService)
                                     └─ FakeMeshRepository
```

## 2. Arrancar sin placa

```bash
cd app
flutter run --dart-define=FAKE_MESH=true
```

Con ese flag, `createMeshRepository()` (en `app_providers.dart`) crea un `FakeMeshRepository`:

- El escaneo encuentra un dispositivo simulado al cabo de 1 s; hay que pulsar «Vincular» en la pestaña Nodos, como con una placa.
- Al conectar aparecen 4 nodos alrededor del Campus Nord: el propio, uno marcado como gateway, un repetidor a 1 salto y uno sin GPS ni batería (`hasPosition` y `hasBattery` a false, para probar cómo se pintan los datos que faltan).
- 2 canales: el primario (sin nombre) y `Rescate` (índice 1).
- Cada 20 s llega un mensaje de difusión de otro nodo por el canal 0.
- Los envíos propios pasan por `queued` → `transmitted` (0,3 s) → `ack` (1,5 s). No simula fallos ni limita el tamaño del texto.

Sin el flag se usa el Bluetooth real, que necesita un móvil Android físico (el emulador no tiene BLE).

## 3. Convivencia con `MeshProvider`

Tras la fusión con `main` hay dos fuentes de datos en la app, y las dos usan los mismos modelos (`MeshMessage`, `MeshNode`):

- **`MeshProvider`** (`services/mesh_provider.dart`, de Carlos): simulado. Lo usa hoy el chat.
- **`AppProviders`** (`providers/app_providers.dart`): la capa real (o la simulación de `FAKE_MESH`). Hoy solo la usa la pestaña Nodos.

`main.dart` registra `AppProviders` por fuera del `ChangeNotifierProvider(MeshProvider)`, así que desde cualquier vista se pueden leer los dos. Para que el chat muestre datos reales, `MeshProvider` tiene que delegar en los providers (o el chat leerlos directamente). Correspondencia:

| `MeshProvider` | Equivalente real |
|---|---|
| `nodes` | `NodesProvider.nodes` |
| `connectedNodeId`, `connectedNode` | `NodesProvider.me?.id`, `NodesProvider.me` |
| `messages` | `ChatProvider.messages` |
| `getMessagesForChannel(null / 'broadcast')` | `ChatProvider.broadcastMessages(0)` (los SOS son difusiones por el canal 0) |
| `getMessagesForChannel(nodeId)` | `ChatProvider.directMessages(nodeNum)` |
| `sendMessage(text, recipientId:)` | `ChatProvider.sendText(text, toNode: nodeNum)` |
| `simulateIncomingMessage` | Sin equivalente; con `FAKE_MESH=true` llega una difusión cada 20 s |
| `triggerSos()`, `cancelSos()`, `isEmergencyActive` | `SosProvider.send()`, `cancel()`, `isActive` |
| `isScanning`, `startScan()`, `stopScan()` | `ConnectionProvider.isScanning`, `startScan()`, `stopScan()` |
| `connectToNode(nodeId)`, `disconnectNode()` | `ConnectionProvider.connect(DiscoveredDevice)`, `disconnect()` (se conecta a un dispositivo BLE del escaneo, no a un nodo de la malla) |

Los providers reales trabajan con el número de nodo (`nodeNum`), y tu chat con el id en texto (`id`). Para pasar de uno a otro:

```dart
final nodes = context.read<NodesProvider>().nodes;
final node = nodes.firstWhere((n) => n.id == _selectedTarget);
await context.read<ChatProvider>().sendText(text, toNode: node.nodeNum);
```

## 4. Qué provider usa cada vista

Los providers se registran en `main.dart` mediante `AppProviders` y se crean al arrancar la app (`lazy: false`), así que no se pierden mensajes llegados antes de abrir una pestaña. En la vista basta con importar:

```dart
import 'package:provider/provider.dart';
import '../../providers/chat_provider.dart'; // o el que toque
```

Regla general: `context.watch<X>()` dentro de `build` para leer estado y redibujar; `context.read<X>()` en callbacks (botones) para llamar a métodos.

| Vista | Provider |
|---|---|
| Nodos (`views/nodes/nodes_view.dart`, ya conectada; sirve de ejemplo) | `ConnectionProvider` y `NodesProvider` |
| Mapa | `NodesProvider` |
| Chat | `ChatProvider` (y `NodesProvider` para elegir destinatario) |
| SOS | `SosProvider` |

Ningún método de los providers lanza excepciones: los errores quedan en `errorMessage`.

### ConnectionProvider (vista Nodos)

| Miembro | Tipo | Significado |
|---|---|---|
| `status` | `ConnectionStatus` | Estado de la conexión con el nodo. |
| `isConnected` | `bool` | `status == connected`. |
| `isScanning` | `bool` | Hay un escaneo en marcha. |
| `devices` | `List<DiscoveredDevice>` | Nodos encontrados en el escaneo. |
| `connectedDevice` | `DiscoveredDevice?` | Dispositivo conectado; null sin conexión. |
| `errorMessage` | `String?` | Motivo del último fallo. |
| `needsSettings` | `bool` | El permiso está denegado de forma permanente: ofrecer `openSettings()`. |
| `startScan()` / `stopScan()` | `Future<void>` | Empieza o detiene el escaneo. |
| `connect(DiscoveredDevice)` | `Future<void>` | Conecta y descarga la configuración del nodo. |
| `disconnect()` | `Future<void>` | Cierra la conexión. |
| `openSettings()` | `Future<void>` | Abre los ajustes de la app en el sistema. |
| `clearError()` | `void` | Descarta el error. |

```dart
final connection = context.watch<ConnectionProvider>();
if (!connection.isConnected) {
  return const Center(child: Text('Conecta un nodo en la pestaña Nodos'));
}
```

### NodesProvider (vista Mapa)

| Miembro | Tipo | Significado |
|---|---|---|
| `nodes` | `List<MeshNode>` | Todos los nodos conocidos, incluido el propio. |
| `me` | `MeshNode?` | El nodo conectado a este móvil; null hasta la primera conexión. Tras desconectar conserva el último. |
| `others` | `List<MeshNode>` | Todos menos el propio. |
| `withPosition` | `List<MeshNode>` | Los que tienen `hasPosition` (se pueden pintar). |
| `byNum(int nodeNum)` | `MeshNode?` | Busca un nodo por su número. |

```dart
final nodes = context.watch<NodesProvider>().withPosition;
final markers = [
  for (final node in nodes)
    Marker(
      point: LatLng(node.latitude, node.longitude),
      child: Icon(
        node.isEmergency ? Icons.warning : Icons.cell_tower,
        color: node.isEmergency ? Colors.red : null,
      ),
    ),
];
```

Usa siempre `withPosition` (o comprueba `hasPosition`) antes de pintar: un nodo sin GPS tiene `latitude` y `longitude` a 0.

### ChatProvider (vista Chat)

| Miembro | Tipo | Significado |
|---|---|---|
| `messages` | `List<MeshMessage>` | Todos los mensajes (difusión y directos), por orden de llegada. Incluye los SOS. |
| `channels` | `List<MeshChannel>` | Canales del nodo conectado. |
| `errorMessage` | `String?` | Motivo del último envío fallido. |
| `broadcastMessages(int channel)` | `List<MeshMessage>` | Difusiones de un canal. |
| `directMessages(int nodeNum)` | `List<MeshMessage>` | Conversación directa con un nodo (en los dos sentidos). |
| `sendText(String text, {int? toNode, int channel = 0})` | `Future<bool>` | Envía; `false` si falla (motivo en `errorMessage`). |

```dart
// Lectura en build:
final chat = context.watch<ChatProvider>();
final mensajes = chat.broadcastMessages(0);

// Envío desde un botón:
final ok = await context.read<ChatProvider>().sendText(controller.text);
if (ok) controller.clear();
```

Cada mensaje propio aparece en la lista en cuanto se envía (`queued`) y se sustituye en el mismo sitio (mismo `id`) cuando cambia su estado; no hay que hacer nada para refrescarlo.

### SosProvider (vista SOS)

| Miembro | Tipo | Significado |
|---|---|---|
| `isActive` | `bool` | Este nodo tiene un SOS emitido y sin cancelar. |
| `isSending` | `bool` | Se está enviando; mientras, `send`/`cancel` no hacen nada. |
| `latitude` / `longitude` | `double?` | Posición del nodo propio (la que viaja en el SOS); null sin GPS. |
| `hasPosition` | `bool` | Hay posición. |
| `lastSignal` | `MeshMessage?` | Último SOS o cancelación enviado, con su `status` de entrega. |
| `errorMessage` | `String?` | Motivo del último fallo (por ejemplo, cancelar sin un SOS activo). |
| `alerts` | `List<EmergencyAlert>` | Alertas de otros nodos sin cancelar ni caducar, la más reciente última. |
| `send()` | `Future<bool>` | Envía el SOS. |
| `cancel()` | `Future<bool>` | Envía la cancelación. |

```dart
final sos = context.watch<SosProvider>();
ElevatedButton(
  onPressed: sos.isSending
      ? null
      : () => sos.isActive
          ? context.read<SosProvider>().cancel()
          : context.read<SosProvider>().send(),
  child: Text(sos.isActive ? 'Cancelar SOS' : 'Enviar SOS'),
);
```

Los SOS de otros nodos están en `SosProvider.alerts` (con `isVerified`, `latitude` y `longitude`). Además marcan el nodo con `MeshNode.isEmergency` en `NodesProvider` (con su posición, si la mandan) y llegan al chat como mensaje con `isSos`.

```dart
for (final alert in context.watch<SosProvider>().alerts)
  ListTile(
    title: Text(MeshNode.idFromNum(alert.originNode)),
    subtitle: Text(alert.hasPosition
        ? '${alert.latitude!.toStringAsFixed(4)}, ${alert.longitude!.toStringAsFixed(4)}'
        : 'Sin posición'),
    trailing: alert.isVerified ? null : const Text('No verificada'),
  );
```

## 5. Modelos (`app/lib/models/`)

`MeshMessage` y `MeshNode` son **tus modelos, ampliados**: se conservan tus campos, tipos, constructor y estados, y se añaden campos opcionales con valor por defecto. Tu `MeshProvider` y tu chat compilan sin cambios. Como tus campos no admiten null, la falta de dato se indica con flags (ver abajo).

### MeshNode

| Campo | Tipo | Origen | Significado |
|---|---|---|---|
| `id` | `String` | Carlos | Con la malla real, el número en texto: `"!a1b2c3d4"`. |
| `name` | `String` | Carlos | Nombre largo. Mientras no llega su ficha: `Nodo xxxx`. |
| `latitude`, `longitude` | `double` | Carlos | Solo válidas si `hasPosition`; si no, 0. |
| `batteryLevel` | `int` | Carlos | 0-100. Solo válido si `hasBattery`; si no, 0. |
| `snr` | `double` | Carlos | SNR (dB) del último paquete oído; 0 = desconocido. |
| `isGateway` | `bool` | Carlos | Siempre `false` con la placa real (solo los simuladores marcan uno). |
| `isEmergency` | `bool` | Carlos | Tiene un SOS activo. |
| `lastHeard` | `DateTime` | Carlos | Última vez que se le oyó; `MeshNode.neverHeard` si nunca. |
| `nodeNum` | `int` | Añadido | Número del nodo en Meshtastic; lo que usan `byNum`, `directMessages` y `sendText`. 0 en tus nodos simulados. |
| `shortName` | `String` | Añadido | Nombre corto; vacío si no se conoce. |
| `hopsAway` | `int?` | Añadido | Saltos hasta él; 0 = vecino directo; null = desconocido. |
| `isMe` | `bool` | Añadido | Es el nodo conectado a este móvil. |
| `hasPosition` | `bool` | Añadido | `latitude`/`longitude` son válidas. Por defecto `true`. |
| `hasBattery` | `bool` | Añadido | `batteryLevel` es válido. Por defecto `true`. |

También: `MeshNode.neverHeard` (constante para `lastHeard`), `MeshNode.unknown(nodeNum)` (nodo sin datos), `MeshNode.idFromNum(nodeNum)` y `copyWith(...)`.

Cómo mostrar un nodo sin perder los datos que faltan (como hace `nodes_view.dart`):

```dart
final details = [
  node.id,
  if (node.hasBattery) 'Batería ${node.batteryLevel}%',
  if (node.snr != 0) 'SNR ${node.snr.toStringAsFixed(1)} dB',
  if (!node.hasPosition) 'sin GPS',
].join(' • ');
final nuncaOido = node.lastHeard == MeshNode.neverHeard;
```

### MeshMessage

| Campo | Tipo | Origen | Significado |
|---|---|---|---|
| `id` | `String` | Carlos | Clave única en la app. Con la malla real, `"<senderId>_<packetId>"`. No es el id del paquete. |
| `senderId` | `String` | Carlos | Id en texto del remitente (`"!a1b2c3d4"`). |
| `senderName` | `String` | Carlos | Nombre del remitente al crear el mensaje. |
| `recipientId` | `String?` | Carlos | `MeshMessage.broadcastId` (`'broadcast'`) en difusión; id del destinatario en un directo. |
| `content` | `String` | Carlos | Texto. En un SOS, una descripción legible, por ejemplo `SOS · 41.38879, 2.11296` o `SOS cancelado` (ver sección 7). |
| `timestamp` | `DateTime` | Carlos | Hora de envío o de recepción en este móvil. |
| `isMe` | `bool` | Carlos | Enviado desde este móvil. |
| `status` | `MessageStatus` | Carlos | Estado de entrega (abajo). La capa real no lo modifica: emite una copia. |
| `isDirect` | getter | Carlos | `recipientId` no es null ni `broadcastId`. |
| `isEmergency` | getter | Carlos (ampliado) | `isSos`, o `senderId == 'sos_beacon'` (tu simulador). |
| `packetId` | `int` | Añadido | Id del paquete Meshtastic; 0 en mensajes simulados. |
| `senderNum` | `int` | Añadido | Número del remitente; 0 en tus mensajes simulados. |
| `recipientNum` | `int?` | Añadido | Número del destinatario; null en difusión. |
| `channel` | `int` | Añadido | Índice del canal. |
| `isSos` | `bool` | Añadido | Es un SOS o una cancelación. |

### MessageStatus

Tus cuatro valores, con este significado en la capa real:

| Valor | Significado |
|---|---|
| `queued` | Propio: todavía no se ha entregado al nodo por BLE. |
| `transmitted` | Propio: el nodo lo ha aceptado. No implica que ya haya salido por radio. |
| `ack` | Propio: acuse recibido (ver sección 6). También es el estado de **todo mensaje recibido** de otro nodo. |
| `failed` | Propio: no se pudo escribir en el nodo, el nodo no pudo encolarlo, la malla devolvió un error o se perdió la conexión antes de entregarlo al nodo. |

### MeshChannel

| Campo | Tipo | Significado |
|---|---|---|
| `index` | `int` | Índice del canal en el nodo; es el `channel` de los mensajes. |
| `name` | `String` | Vacío en el canal por defecto de Meshtastic. |
| `role` | `MeshChannelRole` | `primary` o `secondary`. |
| `isPrimary` | getter | `role == primary`. |
| `displayName` | getter | `name`, o `Primario` / `Canal N` si está vacío. Usar este para la interfaz. |

### ConnectionStatus

`disconnected` → `connecting` (enlace BLE) → `configuring` (descargando nodos y canales) → `connected`. Ante cualquier fallo o pérdida del enlace vuelve a `disconnected`. Getters: `isConnected` (solo `connected`) e `isBusy` (`connecting` o `configuring`). Solo se puede enviar en `connected`.

### DiscoveredDevice

Resultado del escaneo: `id` (Android: dirección MAC; iOS: UUID que asigna el sistema), `name` (anunciado o del sistema; «Nodo Meshtastic» si no hay) y `rssi` (dBm). Solo lo usa la vista Nodos.

## 6. Chat: difusión y mensajes directos

- **Difusión:** `sendText(texto, channel: n)` sin `toNode`. Llega a todos los nodos que tienen ese canal. Se lee con `broadcastMessages(n)`.
- **Directo:** `sendText(texto, toNode: nodo.nodeNum)`. En Meshtastic un mensaje directo **no es un canal**: es un paquete con destino `toNode` (viaja por el canal 0 salvo que se indique otro). Se lee con `directMessages(nodo.nodeNum)`.

Estados de entrega de un mensaje propio: `queued` → `transmitted` → `ack` o `failed`.

- En **difusión**, `ack` significa que algún nodo de la malla lo retransmitió (acuse implícito del firmware), **no** que alguien lo haya leído.
- En **directo**, `ack` significa que el destinatario lo confirmó. El acuse implícito de la malla no cuenta.
- Si nunca llega acuse, el mensaje se queda en `transmitted` (el firmware reintenta y, si se rinde, normalmente informa con un error que lo pasa a `failed`).

Conviene que los textos de ayuda de los iconos de estado reflejen esto (por ejemplo, `ack` en difusión no es «confirmado por el receptor»).

**Límite del texto:** 233 bytes en UTF-8 (no caracteres: una letra con tilde ocupa 2 bytes). Un texto vacío o más largo hace que `sendText` devuelva `false` con el motivo en `errorMessage`. Conviene limitar el campo de texto en la vista. El simulador no aplica este límite.

## 7. SOS en formato EMG1

Esta sección va dirigida también a Cristina (firmware) y Andrés (backend). El SOS viaja en EMG1, el formato del firmware de Cristina (`EmergencyWire.h`), que la app codifica con `core/emergency_codec.dart`. Todo lo que decide cómo se envía está en `app/lib/data/meshtastic/emergency_policy.dart`.

### Cómo se envía (`EmergencyPolicy`)

| Constante | Valor | Qué es |
|---|---|---|
| `portNum` | `PortNum.PRIVATE_APP` (256) | El puerto que reconoce el módulo de emergencias del firmware. |
| `priority` | `MeshPacket_Priority.ALERT` (110) | Prioridad en el nodo emisor (el firmware la fija igualmente). |
| `hopLimit` | 7 | TTL en saltos; 7 es el máximo del protocolo. |
| `channel` | 0 | Canal primario. |
| `severity` | 3 | Gravedad (1 a 3). |
| `expiresUnix` | 0 | Sin caducidad: la hora de las placas puede no ser fiable. |
| `text` | `SOS` | Texto tras las coordenadas. Corto, para que el paquete quepa junto con la firma. |

- **SOS:** un EMG1 de tipo ALERT, en difusión y con `want_ack`, con `originNode` = nuestro nodo e `id` aleatorio distinto de 0. Va en difusión porque Meshtastic solo firma las difusiones, y el firmware solo da prioridad en cada salto a las alertas firmadas.
- **Cancelación:** un EMG1 de tipo RESOLVED con el mismo `id` y `originNode`. El cliente recuerda el SOS activo (también tras reconectar con el mismo nodo). Sin un SOS activo, `cancelSos` lanza `StateError`.
- Un solo paquete por SOS y otro por cancelación; los reintentos los hace el firmware.

### La posición va en el texto (`EmergencyText`)

EMG1 no tiene campos de posición, así que las coordenadas van al principio del texto, con 5 decimales:

```text
@41.38879,2.11296 SOS    alerta con posición
SOS                      alerta sin GPS
```

### Recepción

Por `PRIVATE_APP` la app acepta:

- **ALERT:** solo si `originNode` coincide con el nodo que envía el paquete. Marca el nodo con `isEmergency`, toma la posición del texto y la publica en `alerts`.
- **RESOLVED:** con la misma regla de origen. Quita la marca y la alerta pasa a `status = resolved`.
- **REPLAY:** una alerta guardada que reenvía otro nodo; se acepta, pero nunca cuenta como verificada.

Además:

- Una alerta (origen + id) se procesa una sola vez, aunque llegue por varios caminos.
- Se ignoran las alertas caducadas, RECEIPT y FETCH (los gestiona el firmware), y todo lo que no es un EMG1 válido.
- `isVerified` sale de `MeshPacket.xeddsa_signed`: el firmware verificó la firma del emisor. Una alerta sin firma verificada puede ser una suplantación.
- En el chat cada SOS aparece como mensaje con `isSos` y un texto legible, con «no verificada» si no lo está.

### Para el firmware (Cristina)

- Las constantes de `EmergencyPolicy` son lo único que hay que tocar para cambiar prioridad, TTL, gravedad o texto.
- Hay que medir en la placa cuánto texto cabe con la firma; con coordenadas y «SOS», el EMG1 ocupa unos 40 bytes.

### Para el backend (Andrés)

El SOS llega por el **puerto 256 (`PRIVATE_APP`)** con la cabecera EMG1 de 20 bytes. Si el backend solo procesa mensajes de texto, no verá los SOS.

## 8. Limitaciones conocidas y pendiente

- **SOS:** si se cierra la app con un SOS activo, se pierde su id y ya no se puede cancelar desde la app. No se piden las alertas guardadas en el nodo (FETCH).
- **Sin persistencia:** el historial del chat y la lista de nodos viven en memoria; se pierden al cerrar la app. Al volver a conectar, la lista de nodos se sustituye por la que envía el nodo.
- **Sin reconexión automática:** si se pierde el enlace, el usuario tiene que volver a vincular desde la pestaña Nodos. Los mensajes que estaban en `transmitted` se quedan en ese estado.
- **`isGateway`** sin implementar (siempre `false`).
- El estado **«en espera»** de los nodos está sin definir.
- **Emparejamiento (PIN):** lo gestiona el sistema operativo; no se ha probado aún con la placa.
- **iOS** sin probar.
- Todo este código se ha escrito **sin poder compilarlo ni probarlo con hardware**.

## 9. Tests

```bash
cd app
flutter test
```

| Fichero | Qué cubre |
|---|---|
| `test/data/meshtastic_client_test.dart` | `MeshtasticClient` contra un transporte de mentira: descarga de configuración (nodos, posición, batería, canales, canal deshabilitado oculto); fallo por `TimeoutException` si el nodo no completa la configuración; recepción de un texto (estado `ack`); `sendText` (paquete con `want_ack`, `hop_limit` del nodo, id casado con el acuse, estados `queued` → `transmitted` → `ack`); error de routing → `failed`; SOS en EMG1 (ALERT con posición, RESOLVED con el mismo id, SOS activo tras reconectar); alertas recibidas (ALERT, RESOLVED, origen falso, repetidas, caducadas, datos que no son EMG1, sin firma y REPLAY); envío sin conexión (`StateError`); pérdida del enlace. |
| `test/data/emergency_policy_test.dart` | `EmergencyText`: posición en el texto (escribir y leer, fuera de rango), tamaño dentro de EMG1 y texto legible para el chat. |
| `test/emergency_codec_test.dart` | Códec EMG1 de Carlos con los vectores del firmware. |
| `test/widget_test.dart` | La app arranca con `FakeMeshRepository` y muestra las cuatro pestañas. |

Los tests no usan Bluetooth ni necesitan placa.
