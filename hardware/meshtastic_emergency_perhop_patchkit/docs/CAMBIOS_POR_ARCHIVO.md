# Cambios por archivo: prioridad en cada retransmisor

Base: Meshtastic 2.8.2.b48e1e0 + primer parche EMG1.

## 1. `src/mesh/NextHopRouter.cpp`

**Sección existente:** `NextHopRouter::perhapsRebroadcast(const meshtastic_MeshPacket *p)`.

**Ubicación exacta:** dentro del bloque que crea una copia para retransmitir, después de:

```cpp
meshtastic_MeshPacket *tosend = packetPool.allocCopy(*p);
if (!tosend)
    return true;
```

Y antes de la línea `LOG_INFO("Rebroadcast msg from %x", p->relay_node);`.

**Cambio:** añade `EmergencyRelayPriority::promoteRelay(*tosend)`. Modifica solo la prioridad de la copia local, que `FloodingRouter::send()` o `NextHopRouter::send()` añadirán después a la cola. Incluye la cabecera `EmergencyRelayPriority.h` tras `#include "NextHopRouter.h"`, bajo una bandera de compilación.

**Motivo:** es el punto común por el que pasan las retransmisiones de difusión y de siguiente salto del routing no opaco. El filtrado y autenticación por firma lo realiza Meshtastic antes de esta función. Las rutas opacas no se promocionan.

## 2. `src/mesh/Router.cpp`

**Sección existente:** `Router::sendLocal(meshtastic_MeshPacket *p, RxSource src)`.

**Ubicación:** antes de la llamada `coerceCoordinatePacketToPositionChannel(p)`.

**Cambio:** sustituye el bloque local de la primera versión de EMG1 por `EmergencyRelayPriority::promoteLocal(*p, getNodeNum())`. Comprueba que el NodeNum local esté en la lista autorizada. Admite `p->from == 0` porque PhoneAPI lo puede suministrar así antes de que `Router::send()` lo convierta al NodeNum local.

**Include:** dentro de `#if EMERGENCY_APP_PRIORITY`, cambia `EmergencyWire.h` por `EmergencyRelayPriority.h`.

## 3. `src/modules/optional/Emergency/EmergencyRelayPriority.h`

**Archivo nuevo**, al lado de `EmergencyConfig.h` y `EmergencyWire.h`.

- `authorized()` — busca el origen en la lista.
- `eligible()` — valida el `MeshPacket`, el formato EMG1 y la autenticación XEdDSA cuando se trata de un paquete recibido.
- `promoteRelay()` — asigna prioridad `ALERT` en retransmisión, sin reducir prioridades superiores (ACK).
- `promoteLocal()` — asigna prioridad `ALERT` al emisor local si está autorizado.

No implementa criptografía propia. Solo consume la bandera `xeddsa_signed` que el propio Router ya ha validado usando la clave pública autorizada.

## 4. `platformio.ini`

**Secciones existentes:** `[env:tbeam-emergency]` y `[env:tbeam-emergency-aging]`.

Añade en ambas:

```ini
-DEMERGENCY_PER_HOP_PRIORITY=1
```

No altera ni elimina `[env:tbeam]`.

## 5. Sin cambios

`EmergencyWire.h`, el formato de payload EMG1, `Emergency.cpp`, `EmergencyConfig.h` (salvo tu NodeNum), `MeshPacketQueue.cpp`, `RadioLibInterface.cpp` y Flutter. Los paquetes no llevan una prioridad por radio. Cada nodo decide su prioridad tras verificar el mensaje.

**Limitación:** esta elevación no se aplica a PKI DM opacos ni a tramas sin firma XEdDSA verificada. La firma no se emite necesariamente para mensajes unicast con el firmware estándar.
