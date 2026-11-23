# ZeroInfra — Trabajo Flutter: GPS periódico + SOS con coordenadas en EMG1 v1

## Qué tienes que hacer (resumen para el compañero)

La idea es que la app recoja la posición que ya conoce de la T-Beam por Bluetooth. Mientras el usuario tenga activado el seguimiento y la app esté funcionando, cada **10 minutos** intentará mandar esa posición al backend por Internet. Por otro lado, cuando pulse **SOS**, la ubicación debe viajar **dentro del mismo mensaje EMG1** que se envía por LoRa, no como otro mensaje de posición ni como una copia en el chat.

**Ojo: esta segunda parte ya está programada en ZeroInfra `main`** a fecha de revisión (23-11-2026). `MeshtasticClient.sendSos()` toma las coordenadas del nodo propio, `EmergencyText.encode()` las añade al comienzo del texto y `EmgCodec` lo envía por `PRIVATE_APP=256`. El parche entregado solo refuerza la validación del GPS y limita el tamaño del texto para dejar margen a las firmas. **No hay que crear otro códec, rehacer BLE ni cambiar `EmergencyWire.h`.**

Lo que **sí falta** es implementar y conectar el servicio de publicación periódica al backend; hay un ejemplo en `reference/location_uplink_service.dart`, pero **no se activa automáticamente** porque requiere una URL real, autenticación y consentimiento del usuario. No confundas recibir coordenadas del nodo con tener una medición GPS reciente: la capa de datos actual no conserva la hora del fix.

## 1. Archivos reales y responsabilidades

El código inspeccionado está en [Skaut155/ZeroInfra](https://github.com/Skaut155/ZeroInfra):

| Archivo | Estado / qué hacer |
|---|---|
| `app/lib/data/meshtastic/emergency_policy.dart` | **Ya existe** `EmergencyText.encode()` (`@lat,lon SOS`). El parche añade comprobación de rango, `isFinite` y límite de texto de 120 bytes UTF-8. |
| `app/lib/data/meshtastic/meshtastic_client.dart` | **Ya existe** `sendSos()`: extrae `self` de `_nodes`, usa `hasPosition`, construye `EmgMessage(ALERT)` y envía un único `PRIVATE_APP`. No hace falta cambiar este recorrido para la opción A. |
| `app/lib/core/emergency_codec.dart` | **Ya existe**: cabecera EMG1 de 20 B + texto de hasta 160 B. No cambiar. |
| `app/lib/providers/sos_provider.dart` | **Ya existe** `send()`; mostrar si el SOS tiene ubicación, o indicar «Sin ubicación». |
| `app/lib/models/mesh_node.dart` | Ya guarda `latitude`, `longitude`, `hasPosition`; **no guarda la fecha del fix GPS**. Extenderlo si necesitáis criterio de frescura. |
| `app/lib/data/mesh_repository.dart` | Ya expone `nodes` y `nodesStream`; reutilizar para seguimiento, sin abrir otra conexión BLE. |
| `app/lib/data/location_uplink_service.dart` | **Por añadir**: tomar posición propia y enviar HTTP al endpoint cada 10 min. Hay implementación de referencia en este paquete. |
| `app/lib/providers/` y ajustes de UI | **Por integrar**: consentimiento, activar/desactivar seguimiento, estado del último intento y errores. |
| `app/test/data/emergency_gps_patch_test.dart` | Lo añade el parche: prueba SOS+GPS en un único EMG1, GPS inválido y límite UTF-8. |

## 2. Contrato exacto del SOS (opción A)

Por LoRa se usa un `MeshPacket` Meshtastic normal con `decoded.portnum = PRIVATE_APP (256)` y `decoded.payload` como bytes EMG1:

```text
EMG1 v1 (20 bytes de cabecera) + texto UTF-8

Con GPS: @41.38879,2.11296 SOS
Sin GPS: SOS
```

`EmergencyText.encode(latitude: ..., longitude: ...)` crea el texto, y `EmgCodec.encode()` añade la cabecera binaria. Es **un único paquete SOS**, no dos paquetes. No se cambia el formato EMG1 ni se exige un nuevo `PortNum`. Flutter receptor ya usa `EmergencyText.position()` y `EmergencyText.body()` para separar la posición del contenido. El backend también puede reutilizar esas reglas.

El parche limita **solo el texto que construye `EmergencyText.encode`** a 120 B UTF-8, como presupuesto conservador; el máximo absoluto del texto EMG1 v1 sigue siendo **160 B**. La firma XEdDSA y otros campos Protobuf también consumen espacio: 120 B no garantiza que el firmware firme el paquete. Comprobar con logs `EMG_RELAY_DIAG` / `sig_ok` y `prior_after` en el receptor.

**No inventar un fix:** con `hasPosition=false`, o si solo se conoce una coordenada o está fuera de rango, el SOS se debe emitir igual, pero sin posición. Si se sospecha que el fix es antiguo, no presentar el SOS como ubicación «actual».

## 3. Envío periódico a la IP del servidor

Este envío **no viaja por LoRa**. La ruta es:

```text
T-Beam GPS → BLE → MeshRepository/NodesProvider → Flutter → HTTPS → backend ZeroInfra
```

Los datos se obtienen del nodo `node.isMe` en `MeshRepository.nodes`, comprobando `hasPosition`. `node.lastHeard` **no es** necesariamente la hora del fix GPS. No asignar `fix_at = DateTime.now()` solo para completar un campo.

### Contrato provisional con backend

Hasta que el equipo de backend confirme la API, proponemos:

```http
POST https://SERVIDOR:PUERTO/api/v1/locations
Content-Type: application/json
Authorization: Bearer <token>
```

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

La ruta anterior **es una propuesta y no está confirmada como endpoint existente**. IP, puerto, certificado TLS y token se configurarán por entorno, sin meter credenciales en Git. Si no hay Internet, registrar el fallo sin generar paquetes LoRa adicionales. Para tolerancia a cortes, añadir cola local persistente, backoff e idempotencia (ver `README_BACKEND.md`).

### Implementación de referencia

El paquete incluye `reference/location_uplink_service.dart`. Para probarlo:

1. Copiarlo a `app/lib/data/location_uplink_service.dart` después de acordar el endpoint.
2. Crear una instancia **única** asociada al `MeshRepository` real, inyectando `Uri` y un proveedor de token. `http` ya figura en `app/pubspec.yaml`.
3. Mostrar una opción explícita de **Compartir ubicación con el backend** (apagada por defecto) y explicar el destino y frecuencia.
4. Cuando se active y la app tenga conectividad/nodo, llamar a `start()`. Al desactivar o salir, `stop()` y cuando se destruya, `dispose()`.
5. Consultar `uploadOnce()` para una prueba manual; debe devolver `false` ante posición ausente, token vacío o error HTTP.
6. Incorporar un estado visible: último intento, último éxito, última respuesta de error y sincronizaciones pendientes. El archivo de referencia no persiste esos estados ni los reintentos.

`Timer.periodic(Duration(minutes: 10))` solo garantiza intentos aproximados **mientras el proceso Flutter está activo**. Android puede suspenderlo en segundo plano. Si hace falta seguimiento con pantalla bloqueada, hace falta diseñar y justificar un servicio foreground de Android, permisos de ubicación/actividad y notificación persistente. `WorkManager` no sirve para intervalos periódicos exactos de diez minutos (mínimo ordinario 15 minutos). Esto es otra tarea: **no se incluye automáticamente en el parche**.

### Hora y antigüedad de la ubicación (pendiente)

Es importante conservar `fix_at`, la hora proporcionada por la fuente GPS, si existe. Ahora `MeshNode` no la expone. Para añadirla sin confundirla con la hora de recepción del paquete:

- Revisar los campos de `Position` en los Protobuf fijados por ZeroInfra (por ejemplo, `time` cuando sea fiable).
- Extender `MeshNode` con `DateTime? positionFixAt`; propagarlo desde `MeshtasticClient._withPosition()` y desde `NodeInfo.position`.
- Aplicar un umbral de frescura acordado (p. ej., 5 min) al SOS y al backend. La política de fecha/hora debe manejar reloj no sincronizado.
- Si solo hay una ubicación antigua, mostrarla como **última ubicación conocida** y permitir SOS sin bloquearlo. No falsear la frescura.

No se ha implementado todavía este punto porque requeriría ajustar el modelo y más tests. Lo importante es no asumir que `hasPosition=true` significa «GPS fijado ahora».

## 4. Pruebas entre dos T-Beam

1. Desde `ZeroInfra/` ejecutar el aplicador en dry-run y `--apply` (ver `README_PATCH.md`).
2. `cd app && dart format ... && flutter test && flutter analyze`.
3. En A, conectada por USB, enviar un SOS con coordenadas usando `tools/emg1_gps_cli.py --send`.
4. En B, conectada por BLE a ZeroInfra, comprobar que `SosProvider.alerts` muestra las coordenadas, texto, ID y severidad. También se puede escuchar por CLI USB, pero no abrir simultáneamente el puerto serie en dos programas.
5. Enviar un SOS sin GPS y verificar que no falla.
6. En los logs de B, observar `EMG_APP_RX` y, para promoción por salto, `EMG_RELAY_DIAG`: la recepción **no garantiza** que se haya aplicado prioridad 110. Con dos nodos no puedes medir una ruta de varios saltos.
7. Iniciar el servicio HTTP de manera explícita con servidor de pruebas. Validar 2xx, ausencia de Internet, posición ausente y apagado del seguimiento.

### Qué NO hacer

- No modificar `EmergencyWire.h`, el puerto 256 ni la firma para incluir GPS.
- No enviar un segundo `POSITION_APP` cada vez que se pulsa SOS.
- No publicar la IP del backend, el token o posiciones reales en los logs ni en el repositorio.
- No atribuir al GPS precisión centimétrica porque el texto tenga cinco decimales; los decimales son formato, no precisión de medida.

## 5. Referencias del código inspeccionado

- [EmergencyPolicy / EmergencyText](https://github.com/Skaut155/ZeroInfra/blob/main/app/lib/data/meshtastic/emergency_policy.dart)
- [MeshtasticClient.sendSos](https://github.com/Skaut155/ZeroInfra/blob/main/app/lib/data/meshtastic/meshtastic_client.dart)
- [Guía de datos existente](https://github.com/Skaut155/ZeroInfra/blob/main/docs/APP_CAPA_DATOS.md)
- [Backend (estado actual)](https://github.com/Skaut155/ZeroInfra/blob/main/docs/BACKEND.md)
