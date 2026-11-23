# Prioridad EMG1 en cada retransmisor — parche incremental para Meshtastic

**Objetivo:** conceder `MeshPacket_Priority_ALERT` (110) a paquetes `EMG1 ALERT` en **cada retransmisor que pueda descifrar y verificar criptográficamente el mensaje**, antes de insertarlo en la cola TX. Sin nuevas cabeceras de radio y sin cambiar el protocolo EMG1 usado por Flutter.

**Base:** firmware Meshtastic **2.8.2.b48e1e0**, con el primer `meshtastic_emergency_patchkit` ya aplicado (incluidos `EmergencyWire.h`, `EmergencyConfig.h`, los cambios de `Router.cpp` y los entornos `tbeam-emergency`). Este paquete es **incremental**: no ejecutes el `apply.py` antiguo de nuevo ni copies un repositorio completo encima del tuyo.

## 1. Qué hace y qué no

Un nodo intermediario **eleva la prioridad local** solo si se cumplen simultáneamente estas condiciones:

1. Su firmware recibe el paquete, lo descifra correctamente y el firmware **ha verificado la firma XEdDSA** del emisor (`xeddsa_signed` local verdadero).
2. El `from` figura en `EMERGENCY_AUTHORIZED_ORIGINS[]` y no es cero ni broadcast.
3. El `Data.portnum` es `PRIVATE_APP` (256) y `EmergencyWire::parse` reconoce `EMG1`, versión 1, tipo `ALERT`, gravedad válida e identificador válido.
4. El campo `originNode` de EMG1 coincide con `MeshPacket.from`.
5. Es un relay normal de la ruta de NextHopRouter (tanto difusión/flooding como siguiente salto) que **ya estaba autorizado a retransmitir**.

Entonces el nodo asigna `priority=ALERT` a **su copia de retransmisión**. No toca la firma, el payload, los campos LoRa, `hop_limit`, `tx_after`, los reintentos ni CAD. El ACK de protocolo sigue por encima (`ACK=120`, `ALERT=110`).

Si NO puede verificar la firma, o no comparte la clave del canal, **retransmite siguiendo la política original sin elevar prioridad** (si el propio firmware decide retransmitir); no fuerza una descodificación insegura. Por eso la garantía es condicional: *cada salto que reconoce y verifica la alerta*, no cualquier nodo de Internet o de una red ajena.

**Requisitos de seguridad:** la lista de NodeNum por sí sola NO autentica un emisor. El diseño requiere la señal de firma XEdDSA **ya verificada por Meshtastic** y asociada a una clave pública aceptada de manera autoritativa por el nodo. No aceptes un campo de firma incluido en el mensaje como prueba de autenticidad. No es garantía absoluta de identidad sin una política de confianza de claves apropiada.

**Aclaración importante:** en Meshtastic 2.8.2 sin licencia de radioaficionado, el código original firma los **broadcasts** que caben con la firma; los unicast normales no reciben automáticamente esa firma. Por tanto, la mejora funciona principalmente en **ALERT broadcast**. Los unicast normales pueden seguir entregándose, pero no tendrán elevación de prioridad en relays si no llevan firma verificada. Las alertas demasiado grandes tampoco pueden firmarse si el protocolo excede el límite de radio. Usa un texto de prueba breve y confirma los logs.

## 2. Aplicación

Desde `~/git-repos` crea un commit de tu estado actual, o al menos una copia de seguridad, antes de aplicar:

```bash
cd ~/git-repos/firmware
git status --short
git rev-parse HEAD
# Cuando tengas todos los cambios revisados, crea un commit de tu versión funcional.
```

Descomprime este ZIP en `~/git-repos/meshtastic_emergency_perhop_patchkit` y haz una comprobación SIN ESCRIBIR:

```bash
cd ~/git-repos
python3 meshtastic_emergency_perhop_patchkit/tools/apply_per_hop.py firmware/
```

Si aparece `COMPROBACIÓN OK`:

```bash
python3 meshtastic_emergency_perhop_patchkit/tools/apply_per_hop.py firmware/ --apply
cd firmware
git diff --check
```

El aplicador crea una copia de los **archivos originales que modifica** en `.emergency_perhop_backups/` (no se añaden automáticamente a Git). No vuelve a ejecutar el primer parche y se niega a actuar si los anclajes no coinciden.

**Configuración:** conserva en `src/modules/optional/Emergency/EmergencyConfig.h` tu lista real de orígenes autorizados, p. ej. `{0x1a21fd32, ...}`. Pon la misma lista en cada T-Beam experimental.

**Compila primero, no flashees hasta que funcione:**

```bash
pio run -e tbeam-emergency
```

Después de confirmar `SUCCESS`, si tu dispositivo es realmente el T-Beam del entorno seleccionado:

```bash
pio run -e tbeam-emergency -t upload --upload-port /dev/ttyACM0
```

Si tu puerto cambió, averígualo con `pio device list` y sustituye `/dev/ttyACM0`.

## 3. Archivos modificados y ubicación

| Archivo | Función / sección | Cambio |
|---|---|---|
| **Nuevo** `src/modules/optional/Emergency/EmergencyRelayPriority.h` | `authorized`, `eligible`, `promoteLocal`, `promoteRelay` | Política de autorización, validación EMG1 y promoción con firma verificada en retransmisión |
| `src/mesh/NextHopRouter.cpp` | Includes iniciales | Añade `EmergencyRelayPriority.h` bajo `#if EMERGENCY_PER_HOP_PRIORITY` |
| `src/mesh/NextHopRouter.cpp` | `NextHopRouter::perhapsRebroadcast()`, justo **después de** `packetPool.allocCopy(*p)` y antes de `LOG_INFO("Rebroadcast...")` | Da prioridad `ALERT` a la copia TX autenticada |
| `src/mesh/Router.cpp` | Includes de `EMERGENCY_APP_PRIORITY` | Sustituye `EmergencyWire.h` por `EmergencyRelayPriority.h` |
| `src/mesh/Router.cpp` | `Router::sendLocal()`, antes de `coerceCoordinatePacketToPositionChannel(p)` | Mantiene prioridad local solo si el NodeNum local está autorizado, también cuando PhoneAPI usa `from=0` |
| `platformio.ini` | `[env:tbeam-emergency]` | Añade `-DEMERGENCY_PER_HOP_PRIORITY=1` |
| `platformio.ini` | `[env:tbeam-emergency-aging]` | Añade `-DEMERGENCY_PER_HOP_PRIORITY=1` |

**No cambia:** `EmergencyWire.h`, `Emergency.cpp`, `EmergencyConfig.h` (salvo tu lista), `MeshPacketQueue.cpp`, `RadioLibInterface.cpp`, el protocolo EMG1, Flutter ni los servicios BLE.

## 4. Cómo probar que realmente prioriza cada salto

1. Instala la variante nueva en los nodos retransmisores y configura las claves de canal/NodeNum correspondientes.
2. Comprueba que el relay conoce/ha validado la **clave pública de la identidad emisora**. Meshtastic autentica el paquete con XEdDSA si la firma está disponible y una clave fiable permite verificarla.
3. Envía desde el origen un `ALERT broadcast` **breve** mediante `emergency_cli.py` (sin `--mirror-chat`).
4. En el retransmisor, abre el monitor serie y localiza:
   `EMG_RELAY_PRIORITY,from=...,mesh_id=...,priority=110`.
5. En otra prueba, retira el origen de `EMERGENCY_AUTHORIZED_ORIGINS` en un relay, recompílalo y verifica que **no** aparece esa promoción. Prueba también un paquete no firmado o uno que no sea `ALERT`.
6. Realiza pruebas de congestión controladas de baja carga, respetando límites de airtime. Compara los tiempos en cola antes y después.

Los logs son metadatos de clasificación, **no pruebas de que un destinatario recibió el mensaje**. Para demostrar mejora necesitas PDR/latencia medidos en los extremos.

## 5. Pruebas locales sin hardware

Para probar la política C++ con una lista de ejemplo y mocks:

```bash
python3 tests/run_tests.py /ruta/al/firmware/src/modules/optional/Emergency/EmergencyWire.h
```

Verifican: mensaje firmado autorizado, emisor no autorizado, origen suplantado, firma ausente, paquete opaco, PKI, tipo incorrecto, cabecera inválida, prioridad ACK conservada, y `from=0` para envíos locales vía PhoneAPI.

No equivalen a compilar ni a ejecutar el firmware real. **La integración requiere un `pio run -e tbeam-emergency` y pruebas con las placas.**

## 6. Limitaciones / mejoras futuras

- Retransmisores sin clave de canal o sin clave pública de confianza del emisor no elevan prioridad.
- En el firmware actual, los unicast normalmente no van firmados; no podemos prometer prioridad por salto para unicast EMG1 sin cambiar el esquema de autenticación.
- No hay nuevas reglas de frecuencia, más canales o saltos, ni tratamiento especial que pueda eludir límites regionales.
- La aplicación Flutter debe mostrar los niveles de gravedad EMG1 y el estado de recepción por separado: la prioridad de cola es un parámetro **local del nodo**, no un campo transmitido.
- El módulo `Emergency.cpp` anterior admite mensajes con controles de NodeNum y canal, pero **no exige por sí solo** firma verificada para presentar una alerta. Si necesitas impedir que una aplicación muestre alertas no autenticadas, esa validación es un cambio aparte que hay que coordinar con Flutter.

El código es una ampliación **experimental**. No lo utilices como canal único en una situación real de emergencia.
