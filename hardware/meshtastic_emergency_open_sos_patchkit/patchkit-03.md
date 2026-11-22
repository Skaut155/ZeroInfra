# Parche incremental OPEN-SOS: cualquier nodo puede solicitar ayuda

**Destinatario:** firmware Meshtastic 2.8.2 (rama experimental), **después** de aplicar `meshtastic_emergency_patchkit v2` y `meshtastic_emergency_perhop_patchkit`. **No ejecutar sobre el firmware oficial limpio.**

## Qué cambia

- Se elimina `EMERGENCY_AUTHORIZED_ORIGINS[]` de `EmergencyConfig.h`.
- `Emergency.cpp` acepta mensajes EMG1 provenientes de **cualquier NodeNum válido** (distinto de `0` y `0xffffffff`), en lugar de exigir que esté inscrito en una lista. Se conserva la validación del formato, la coherencia `originNode == from` para `ALERT` y `RESOLVED`, deduplicación, caducidad, caché y límites de respuestas.
- `EmergencyRelayPriority.h` permite que **cualquier** nodo con NodeNum válido tenga prioridad `ALERT` al enviar un SOS local. Para un **retransmisor**, exige además que el paquete haya sido descifrado, sea `PRIVATE_APP=256`, sea un `EMG1 ALERT` válido y que Meshtastic haya **verificado** una firma XEdDSA (`xeddsa_signed`). No se da prioridad a mensajes opacos, sin firma verificable, ni a ACK/paquetes convencionales.
- Se actualiza el comentario de `Router.cpp` para reflejar la nueva política.

**No cambia:** la cabecera de radio Meshtastic, la cabecera EMG1 (20 B), el código de Flutter, `NextHopRouter.cpp`, `platformio.ini`, las colas, el `aging`, los ACK, CAD ni los límites de radio.

**Seguridad:** aceptar cualquier NodeNum hace posible que más dispositivos pidan ayuda, pero un NodeNum **no autentica** a una persona y puede suplantarse si no hay protección criptográfica. Los retransmisores solo elevan prioridad con firma XEdDSA *ya verificada* por el firmware y una clave pública vinculada a la identidad del emisor. Un mensaje sin firma aún puede procesarse y reenviarse con prioridad normal (si Meshtastic lo admite), y las alertas falsas siguen siendo posibles. Los nodos que no conocen la clave del canal no podrán interpretar EMG1 para elevar su prioridad. Usar canales cifrados, controles de acceso a BLE y alertar sobre mensajes no verificados en Flutter.

## Instalación en el submódulo de ZeroInfra

**1. Haz commit o guarda tus cambios actuales** en el repositorio de firmware. Se comprueba que Git esté limpio salvo que indiques `--allow-dirty`.

Ejemplo, tras descomprimir este paquete en `~/git-repos/meshtastic_emergency_open_sos_patchkit`:

```bash
cd ~/git-repos/ZeroInfra/hardware/firmware
git status
# Si tienes modificaciones pendientes, haz commit o guárdalas antes de continuar.
```

**2. Comprobación SIN modificar archivos:**

```bash
python3 ~/git-repos/meshtastic_emergency_open_sos_patchkit/tools/apply_open_sos.py \
    ~/git-repos/ZeroInfra/hardware/firmware --show-diff
```

**3. Aplicación (solo cuando la comprobación sea correcta):**

```bash
python3 ~/git-repos/meshtastic_emergency_open_sos_patchkit/tools/apply_open_sos.py \
    ~/git-repos/ZeroInfra/hardware/firmware --apply
```

Guarda copias originales en `.emergency_open_sos_backups/` dentro del firmware. **No hagas `git add .` indiscriminadamente**: no subas la carpeta de backups. Si ya hay cambios pendientes y entiendes los riesgos, puedes especificar `--allow-dirty`, pero se recomienda hacer un commit primero.

**4. Pruebas locales y compilación:**

```bash
cd ~/git-repos/ZeroInfra/hardware/firmware
python3 ~/git-repos/meshtastic_emergency_open_sos_patchkit/tests/run_tests.py .
git diff --check
pio run -e tbeam-emergency
```

Compila el entorno `tbeam-emergency-aging` aparte, solo para comparar experimentalmente el algoritmo de aging:

```bash
pio run -e tbeam-emergency-aging
```

**5. Flasheo opcional, después de `SUCCESS`:**

```bash
pio device list
pio run -e tbeam-emergency -t upload --upload-port /dev/ttyACM0
```

Cambia `/dev/ttyACM0` por el puerto real. Repite en los nodos en los que quieras probar la política por salto.

**6. Guarda los commits en los dos repositorios:**

```bash
# Dentro del submódulo
cd ~/git-repos/ZeroInfra/hardware/firmware
git add src/modules/optional/Emergency/EmergencyConfig.h \
        src/modules/optional/Emergency/Emergency.cpp \
        src/modules/optional/Emergency/EmergencyRelayPriority.h \
        src/mesh/Router.cpp
git commit -m 'feat: allow open SOS while requiring signed relay priority'
git push

# En el repo principal
cd ../..
git add hardware/firmware
git commit -m 'chore: update emergency firmware submodule'
git push
```

## Casos de prueba recomendados en las T-Beam

1. Enviar un `EMG1 ALERT` desde un NodeNum que **antes no estuviese** en la lista. El receptor debería registrarlo mediante `EMG_APP_RX` (si el canal y la versión son compatibles).
2. Enviar un mensaje `TEXT_MESSAGE_APP` y comprobar que sigue funcionando sin clasificación como SOS.
3. Probar un ALERT firmado y verificable. En un relay equipado con este parche, buscar `EMG_RELAY_PRIORITY` y `priority=110`.
4. Probar un ALERT sin firma verificable. Puede llegar como SOS, pero el relay no debe emitir el registro de promoción.
5. Probar un mensaje EMG1 malformado; no debe ser considerado alerta.
6. Comparar `tbeam-emergency` con `tbeam-emergency-aging` con tráfico moderado y medido, respetando normativa local.

## Nota sobre aging

El aging del parche anterior **no se modifica**. `EmergencyQueuePolicy::effective(original, waitMs)` añade `floor(waitMs/4000)` puntos a prioridades inferiores a 100, con un máximo de +25 y techo de 99. `HIGH`=100, `ALERT`=110 y `ACK`=120 permanecen fuera del aging. Está desactivado en `tbeam-emergency` y activado solo en `tbeam-emergency-aging`. La reordenación entre selección y extracción merece validación en hardware.

## Archivos modificados (4)

| Archivo | Cambio |
|---|---|
| `src/modules/optional/Emergency/EmergencyConfig.h` | Reemplaza la allowlist con `EmergencyOriginPolicy::validNodeNum()` |
| `src/modules/optional/Emergency/Emergency.cpp` | Elimina `authorized()` y valida NodeNum para recepción y REPLAY |
| `src/modules/optional/Emergency/EmergencyRelayPriority.h` | Elimina `authorized()`, mantiene XEdDSA obligatoria para relays |
| `src/mesh/Router.cpp` | Actualiza el comentario de clasificación local |

Este es un **parche experimental no certificado para emergencias reales**. No garantiza latencia, cobertura, entrega o autenticidad de las alertas; el flujo de detección en Flutter debe tratar las firmas y los recibos de manera explícita.
