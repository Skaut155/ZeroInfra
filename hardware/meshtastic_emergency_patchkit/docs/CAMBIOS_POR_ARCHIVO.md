# Mapa exacto de cambios · ficheros, funciones y puntos de inserción

**Tipo:** `MOD` significa función o sección preexistente editada; `NUEVO` significa archivo, tipo o función nueva. Los anclajes son nombres de símbolos/líneas identificables, no números de línea fijos. `tools/apply.py` aborta si falta un anclaje. Esta referencia corresponde al contenido del paquete experimental, no a modificaciones ya ejecutadas en tus dispositivos.

## 1. Archivos originales modificados

| Ruta en `firmware/` | Tipo | Sección existente / lugar exacto | Qué añade o modifica |
|---|---|---|---|
| `src/mesh/MeshPacketQueue.h` | MOD + NUEVO | **Antes de** `class MeshPacketQueue` y **después de** los `#include`: nuevo `struct EmergencyQueueStats`; en miembros privados, **junto a** `std::vector<meshtastic_MeshPacket *> queue`; en API pública, **después de** `MeshPacketQueue(size_t)` | Estadísticas agregadas, vector paralelo `queuedAt`, `bestReadyIndex()` y getter `getEmergencyStats()` |
| `src/mesh/MeshPacketQueue.cpp` | MOD + NUEVO | `#include "MeshPacketQueue.h"` (añade otro include). **Sustituye constructor** `MeshPacketQueue::MeshPacketQueue()` y añade `bestReadyIndex()` inmediatamente después, **antes de** `MeshPacketQueue::empty()` | Inicialización de arrays y política de selección con aging solo si se habilita |
| `src/mesh/MeshPacketQueue.cpp` | MOD | `MeshPacketQueue::enqueue()` | Aplica `fixPriority()` antes de ordenar, anota hora, entradas, rechazos, expulsiones y tamaño máximo |
| `src/mesh/MeshPacketQueue.cpp` | MOD | `MeshPacketQueue::dequeue()` y `MeshPacketQueue::getFront()` | Selecciona el mismo candidato; mide tiempo en cola al desencolar |
| `src/mesh/MeshPacketQueue.cpp` | MOD | `MeshPacketQueue::remove(NodeNum,PacketId,...)` | Mantiene sincronizado `queuedAt` y cuenta cancelaciones |
| `src/mesh/MeshPacketQueue.cpp` | MOD | `MeshPacketQueue::replaceLowerPriorityPacket()` | Mantiene sincronizado `queuedAt` en sus tres rutas de sustitución, sin cambiar los criterios actuales de descarte |
| `src/mesh/RadioLibInterface.h` | MOD | **Inmediatamente después de** `MeshPacketQueue txQueue = MeshPacketQueue(MAX_TX_QUEUE);` | Contadores `emergencyCadBusy`, `emergencyCadFree`, `emergencyTxStarted` |
| `src/mesh/RadioLibInterface.cpp` | MOD | **Dentro de** la rama CAD de `RadioLibInterface::handle...` que imprime `LOG_DEBUG_RADIO("CAD busy")` / `LOG_DEBUG_RADIO("CAD free")` | Contabiliza las decisiones de CAD sin alterar el algoritmo ni los tiempos |
| `src/mesh/RadioLibInterface.cpp` | MOD | `RadioLibInterface::startSend()` **después de** `lastTxStart = Time::getMillis()` y **antes de** `printPacket("Started Tx", txp)` | Cuenta inicios de transmisión aceptados por el driver |
| `src/mesh/RadioLibInterface.cpp` | MOD | **Al comienzo** de `RadioLibInterface::periodicRadioMaintenance()` | Emite registro `EMG_TXQ` con métricas TX, latencias de cola y CAD; compilación condicionada por `EMERGENCY_METRICS` |
| `src/mesh/Router.cpp` | MOD | **Después del** `#include "Router.h"`, **antes del siguiente include** | Incluye `EmergencyWire.h` cuando la clasificación está activa |
| `src/mesh/Router.cpp` | MOD | `Router::sendLocal()` **inmediatamente antes de** `coerceCoordinatePacketToPositionChannel(p)` | Reconoce mensajes `EMG1` de tipo `ALERT` originados localmente y asigna `meshtastic_MeshPacket_Priority_ALERT` |
| `src/mesh/Router.cpp` | MOD | `Router::enqueueReceivedMessage()` **al principio**, en rama `if (old_p)` y **justo antes de** `setReceivedMessage()` | Cuenta recibidos y descartes al llenarse `fromRadioQueue`; registros `EMG_RXQ` |
| `src/mesh/ReliableRouter.cpp` | MOD | **Tras** `#include "ReliableRouter.h"` y **antes del resto de includes**, y en `ReliableRouter::send()` donde comprueba `if (p->want_ack)` | Contadores de envíos fiables |
| `src/mesh/ReliableRouter.cpp` | MOD | Función de recepción donde figura `LOG_DEBUG("Received a %s...stopping retransmissions", ...)` | Contadores `emergencyAckEvents` y `emergencyNakEvents` sin cambiar ACK/NAK |
| `platformio.ini` | NUEVO | **Al final del fichero**, después de la última sección existente | Crea `[env:tbeam-emergency]` y `[env:tbeam-emergency-aging]` extendiendo el entorno `tbeam` y activando macros propias |

**Nota sobre ubicaciones:** no existe una «sección de CAD» con cabecera propia; el bloque se encuentra dentro del manejo del evento `TRANSMIT_DELAY_COMPLETED` en `RadioLibInterface.cpp`. No se reemplaza la función completa.

## 2. Archivos nuevos que debes añadir

| Ruta | Tipo | Ubicación exacta / entre qué elementos | Función |
|---|---|---|---|
| `src/mesh/EmergencyQueuePolicy.h` | NUEVO | Junto a `MeshPacketQueue.h` y `MeshPacketQueue.cpp`. Se incluye **inmediatamente después de** `#include "MeshPacketQueue.h"` en `MeshPacketQueue.cpp` | Función `EmergencyQueuePolicy::effective(priority, waitMs)` que limita el incremento de prioridades normales |
| `src/modules/optional/Emergency/Emergency.h` | NUEVO | Carpeta nueva `optional/Emergency/`, en paralelo a otros módulos opcionales | Declara `void setupEmergency()` |
| `src/modules/optional/Emergency/EmergencyConfig.h` | NUEVO | Misma carpeta; la incluye `Emergency.cpp` **tras** `Emergency.h` y **antes de** `EmergencyWire.h` | Lista de NodeNum admitidos, límites de RAM, expiración de caché y enfriamiento de recibos |
| `src/modules/optional/Emergency/EmergencyWire.h` | NUEVO | Misma carpeta, incluida **tras** `EmergencyConfig.h` en `Emergency.cpp`, y desde `Router.cpp` cuando corresponda | Tipos, serializador y parser de paquete de aplicación propio `EMG1` |
| `src/modules/optional/Emergency/Emergency.cpp` | NUEVO | Misma carpeta, descubierto automáticamente mediante `bin/optional-modules.py` | Implementación `EmergencyModule`, deduplicación, retención temporal, `FETCH`, `REPLAY`, `RECEIPT`, logs |

**Registro del módulo sin editar `Modules.cpp`:** la herramienta existente `bin/optional-modules.py` detecta la carpeta `Emergency/` por `Emergency.h`, genera el include de su cabecera y registra `setupEmergency()`. La llamada de inicialización sucede en `Modules.cpp` dentro de `OPTIONAL_MODULES_SETUP()`; en la rama revisada está **después de inicializar `Watchdog` y antes de `routingModule = new RoutingModule()`**. No es necesario insertar manualmente código entre esas dos secciones; el sistema de registro lo hace. En `env:tbeam` normal, `setupEmergency()` queda vacío si `EMERGENCY_ENABLE_MODULE` no se define.

## 3. Archivos auxiliares del paquete que no se copian al firmware

| Ruta en este ZIP | Sección | Contenido |
|---|---|---|
| `tools/apply.py` | `TARGETS` y `main()` | Detecta anclajes, comprueba el Git limpio, aplica los cambios y copia el overlay |
| `tools/emergency_cli.py` | `encode()`, `decode()` y `main()` | Codifica y decodifica `EMG1`, escucha y opcionalmente envía mediante la librería Python Meshtastic |
| `tests/test_wire.cpp` | `main()` | Pruebas locales del formato, validaciones y caducidad |
| `tests/test_cli.py` | pruebas de `encode/decode` | Verifica compatibilidad básica entre formatos Python y C++ |
| `tests/test_patch_anchors.py` | casos para cada archivo | Comprueba las funciones transformadoras con fragmentos representativos del código original |
| `tests/stubs/` | estructuras mínimas | Permite comprobar sintaxis C++ del módulo sin acceder al firmware real; no sustituye a sus cabeceras |

## 4. Alcance exacto frente a los siete capítulos de modificaciones del manual

| Capítulo del manual | Estado de la implementación |
|---|---|
| 1. Medir colas, descartes y ACK | **Implementado parcialmente:** agregados de TX/RX, CAD, inicio TX, ACK/NAK; faltan métricas completas de entregas extremo a extremo, PDR y RSSI/SNR por mensaje |
| 2. Prioridad para alertas | **Implementado localmente** en `Router::sendLocal`; **no** se propaga de forma automática a todos los retransmisores |
| 3. Fairness y tratamiento de colas llenas | **Implementado** aging con opción independiente; conserva la política original de sustitución. Se debe validar en hardware |
| 4. Confirmación a nivel de aplicación | **Implementado** recibo limitado en unicast, diferenciado del ACK/NAK de routing; el emisor puede inspeccionar la recepción con la herramienta de escucha |
| 5. Módulo propio | **Implementado** el módulo `Emergency` con formato propietario, caducidad, deduplicación, acceso controlado por lista de NodeNum y almacén RAM |
| 6. Backoff, routing y colisiones | **Instrumentado para medir**, pero **no se modifican** CAD, duty cycle, hop limit, next-hop ni managed flooding; el manual recomienda un experimento independiente antes de hacerlo |
| 7. Simplificar y optimizar | **Implementado parcialmente:** configuración separada para `tbeam` y bandera de compilación para desactivar MQTT. No se eliminan drivers, GPS, BLE ni código necesario de Meshtastic |

## 5. Advertencias de integración

1. `MeshPacketQueue` necesita mantener `queue` y `queuedAt` sincronizados en todas las rutas de borrado. Si tu versión introduce un método nuevo que modifica la cola, hay que instrumentarlo también.
2. La política aging puede cambiar el paquete elegido entre la selección previa al CAD y el desencolado si el orden efectivo varía por el tiempo. Por eso **está desactivada en `tbeam-emergency`** y se ofrece solo como experimento.
3. `PRIVATE_APP=256` es una etiqueta para aplicaciones privadas experimentales; los demás nodos Meshtastic no comparten el nuevo esquema `EMG1` automáticamente. La retransmisión mesh de un paquete no implica que reconozcan su urgencia.
4. `EMERGENCY_AUTHORIZED_ORIGINS[]` es una lista de NodeNum y **no aporta autenticación criptográfica**. No usarla como único control para alertas auténticas.
5. El almacenamiento temporal ocupa RAM, se pierde al reiniciar y no constituye una garantía de entrega diferida.
6. Antes de editar el firmware, verifica sus dependencias y crea una rama Git. Concluye la validación mediante `pio run -e tbeam-emergency` en tu equipo.
