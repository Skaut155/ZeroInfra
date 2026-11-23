# ZeroInfra — Trabajo backend: subida de posiciones y recepción de SOS EMG1

## Qué tienes que hacer (resumen)

Queremos que la app Flutter conectada a una T-Beam intente enviar al servidor la **posición del nodo cada 10 minutos** mediante la conexión a Internet del móvil. En paralelo, cuando una persona envíe un SOS, las coordenadas irán dentro del **mismo mensaje EMG1 por LoRa**. Son dos vías independientes:

- **Telemetría a la IP del servidor:** Flutter → HTTPS → API/backend → base de datos → Grafana.
- **SOS sin Internet:** Flutter → Bluetooth → T-Beam → LoRa mesh → gateway/otro nodo. El texto EMG1 ya lleva la posición, cuando está disponible.

En la documentación pública de ZeroInfra (revisada el 23-11-2026), `backend/` utiliza o prevé Mosquitto, una base de datos, una API REST, Grafana y k3s. En `docs/BACKEND.md` se describen nodos k3s y pruebas, **no una API de ingestión de posiciones ya confirmada**. Esta guía es una propuesta de contrato para acordar con la persona que lleva Flutter, no una descripción de una API existente.

## 1. Contrato HTTP propuesto para Flutter

La API se puede exponer detrás de un gateway HTTPS en el clúster k3s:

```http
POST /api/v1/locations
Content-Type: application/json
Authorization: Bearer <token>
```

Ejemplo de cuerpo **ficticio**:

```json
{
  "node_id": "!82e09b4e",
  "latitude": 41.38879,
  "longitude": 2.11296,
  "source": "tbeam_meshtastic",
  "fix_at": null,
  "sent_at": "2026-11-23T17:00:00Z"
}
```

`node_id` identifica el nodo Meshtastic, no el teléfono; `source` identifica de dónde proceden las coordenadas. `sent_at` es el instante de creación de la petición HTTP, **no** el momento del fix GPS. Actualmente Flutter no conserva esa fecha. Se mantiene `fix_at = null` hasta que se exponga la hora de medición del GPS.

### Validaciones necesarias

- `latitude` real y finita entre -90 y 90; `longitude` entre -180 y 180. No convertir `0,0` automáticamente en «posición válida» por defecto; decidirlo a partir del indicador `hasPosition` en la app.
- `node_id` válido, pero **no confiar en este texto para autenticar la identidad**. Asociar el token al nodo/usuario autorizado y verificarlo en servidor.
- `sent_at` ISO-8601 UTC válido, con tolerancia al desfase del reloj; guardar siempre también `received_at` del servidor.
- `fix_at` opcional; tratar su ausencia como **antigüedad desconocida**, nunca como «medición actual».
- Limitar tamaño de peticiones, frecuencia, caducidad, número de peticiones en cola y acceso a los datos.
- Usar HTTPS y token fuera del código/repo. Cuando se accede por IP literal, el certificado debe ser válido también para esa IP o utilizar un nombre DNS confiable.
- Responder con 2xx solo tras aceptar el dato en la capa de persistencia. Devolver 400/422 para datos inválidos, 401/403 para acceso no permitido, 429 para límites y 5xx para fallos temporales.

Ejemplo de respuesta:

```json
{
  "accepted": true,
  "server_received_at": "2026-11-23T17:00:01Z"
}
```

Si queréis reintentos duraderos, acordar un `report_id` UUID generado una sola vez por medición/intento persistido, y hacer `UNIQUE(report_id)` en servidor. Sin idempotencia, reenviar peticiones fallidas puede duplicar puntos del mapa. La referencia Flutter del paquete todavía **no implementa** almacenamiento local ni ese `report_id`.

## 2. Esquema de almacenamiento sugerido

Tabla `node_locations`:

| Columna | Tipo sugerido | Observaciones |
|---|---|---|
| `id` | UUID / serial | Id interno |
| `node_id` | VARCHAR(9) | Ej. `!82e09b4e` |
| `latitude`, `longitude` | DOUBLE PRECISION | Coordenadas WGS84 |
| `source` | TEXT | `tbeam_meshtastic` / futuro `phone_gps` |
| `fix_at` | TIMESTAMPTZ nullable | Momento real de medición, si conocido |
| `sent_at` | TIMESTAMPTZ nullable | Momento declarado por el móvil |
| `received_at` | TIMESTAMPTZ NOT NULL | Hora fiable del servidor |
| `user_id`/`device_id` | Referencia autenticada | Según el sistema de identidades existente |
| `report_id` | UUID nullable UNIQUE | Solo cuando haya cola offline con idempotencia |

Usar un índice `(node_id, received_at DESC)` para consultar la última posición recibida. En los mapas, distinguir posición del nodo y posición del usuario. Aplicar política de retención y controles de acceso: se trata de datos sensibles.

## 3. No confundir telemetría HTTP con los SOS LoRa

El envío HTTP cada diez minutos **no es** un paquete Meshtastic ni requiere utilizar `PRIVATE_APP`. No debe generarse una alerta EMG1 por cada subida GPS. La app debe hacerlo solo cuando está habilitado compartir ubicación y cuando dispone de posición y acceso a la IP.

Los SOS recibidos mediante gateway sí usan:

```text
MeshPacket.decoded.portnum = 256  (PRIVATE_APP)
MeshPacket.decoded.payload = [20 bytes EMG1 v1] + [texto UTF-8]
Ejemplo del texto: @41.38879,2.11296 SOS
```

Si el gateway ya recibe `MeshPacket` y lo publica a MQTT, añadir una ruta de procesamiento para `PRIVATE_APP`: validar magic `EMG1`, versión 1, longitudes, tipo y procedencia; extraer el prefijo `@lat,lon ` si existe. **No interpretar todos los paquetes de PRIVATE_APP como EMG1 sin comprobar su cabecera.**

### Eventos sugeridos

- `ALERT` (`kind=1`): almacenar/abrir incidente, `severity=1..3`, `originNode`, `alert_id`, ubicación si hay.
- `RESOLVED` (`kind=3`): buscar por `(originNode, alert_id)` y marcar incidente como resuelto. No borrar la alerta.
- `REPLAY` (`kind=5`): recuperar alerta almacenada; deduplicar usando `(originNode, alert_id)`, no `MeshPacket.id`.
- `RECEIPT` (`kind=2`) y `FETCH` (`kind=4`): control de protocolo; no crear incidentes nuevos.

El prefijo usa cinco decimales: `@-33.45000,-70.66670 SOS`. Un prefijo malformado no debe invalidar el texto del SOS; se considera sin posición. Si hay GPS sin dato de edad, etiquetar «última ubicación conocida» o «hora de medición desconocida».

### Autenticidad

Un `NodeNum` en el payload no demuestra autenticidad. Guardar `signature_verified` si el gateway expone la verificación criptográfica real de Meshtastic, y distinguir eventos verificados/no verificados. Un campo `xeddsa_signed` falso o ausente no impide registrar una posible petición de ayuda, pero no debe clasificarse como origen autenticado.

### MQTT vs HTTP: evitar duplicar eventos

El mismo SOS puede llegar por el gateway MQTT y por otra ruta. Deduplicar `(originNode, alert_id)` para incidentes. Las publicaciones periódicas de posición por HTTP no deben duplicarse como SOS.

Los topic MQTT, la estructura real de los mensajes del gateway, la base de datos y los servicios k3s actuales **deben acordarse con el equipo backend**; no están definidos por este paquete.

## 4. Seguridad y operación

- Mostrar y almacenar ubicaciones solo para usuarios/servicios con permiso; no publicarlas sin autenticación ni en dashboards públicos.
- Consentimiento activo desde Flutter y opción de detener las publicaciones; especificar cuánto tiempo se guarda la información.
- Cifrar transporte HTTPS, rotar credenciales y evitar tokens en logs o `git`.
- Soportar cortes de Internet: API idempotente y límites por usuario; si la app acumula datos offline, distinguir `fix_at`, `sent_at` y `received_at`.
- No exigir Internet para permitir un SOS; **la alerta LoRa es independiente del backend**.

## 5. Pruebas de aceptación del backend

1. `POST` válido y autenticado: 2xx y registro consultable.
2. Latitud 100, longitud 200, campos NaN, JSON inválido: 400/422 y sin escritura.
3. Sin token / token inválido: 401/403.
4. `fix_at: null`: se conserva como desconocido, sin convertirlo en la hora actual.
5. Reintento del mismo `report_id`: un único registro.
6. Consumo de incidentes EMG1: `ALERT`, `RESOLVED`, `REPLAY` deduplicados.
7. Cuando el móvil está sin Internet: el SOS por LoRa sigue funcionando.

### Referencias del proyecto

- [README de ZeroInfra](https://github.com/Skaut155/ZeroInfra)
- [docs/BACKEND.md](https://github.com/Skaut155/ZeroInfra/blob/main/docs/BACKEND.md)
- [Formato y comportamiento SOS en Flutter](https://github.com/Skaut155/ZeroInfra/blob/main/docs/APP_CAPA_DATOS.md)
