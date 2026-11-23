# Estructura general: qué hace esta primera propuesta

## Qué incorpora `meshtastic_emergency_patchkit`

- Instrumentación de cola TX: aceptados, rechazados, expulsados, cancelados, enviados desde cola, pico de ocupación y espera media/máxima. Métricas RX de aceptados y descartados, CAD ocupado/libre, inicios TX, ACK/NAK y mensajes fiables.
- Reconocimiento local de los paquetes experimentales `ALERT` y asignación de prioridad Meshtastic `ALERT` **en el nodo origen**.
- Módulo `Emergency` opcional con formato `EMG1`, caducidad, deduplicación de alertas por identificador de aplicación y origen, lista de emisores admitidos, recibos directos de aplicación, retención temporal en RAM (8 alertas) y recuperación mediante peticiones directas `FETCH`.
- Política de *aging* de cola estrictamente optativa, que no eleva mensajes normales por encima de prioridad 99 ni modifica las prioridades originales almacenadas.
- Dos entornos PlatformIO propios para T-Beam, con MQTT deshabilitado por bandera de compilación. No se eliminan código GPS, BLE, radio, routing, cifrado ni módulos del firmware original.

## Qué NO incorpora y por qué

- **Ni modifica CSMA/CAD, el backoff ni las reglas de flood/next-hop.** Esos cambios requieren una línea base experimental, compatibilidad y verificación de la normativa radioeléctrica; el manual original recomienda medir antes de intervenir.
- **No garantiza recepción ni alta disponibilidad.** El acuse de aplicación confirma procesamiento local del módulo, no lectura humana. Los recibos solo se emiten en unicast, con limitación de frecuencia.
- **No propaga la prioridad ALERT a través de cabeceras LoRa.** La prioridad es local; cambiar el protocolo en aire comprometería compatibilidad. Los retransmisores estándar siguen aplicando su propia política.
- **No conserva alertas después de reiniciar.** El almacén de 8 alertas es volátil, con antigüedad máxima de una hora en RAM, y devuelve una alerta por petición como máximo.
- **No implementa una prueba de identidad criptográfica del origen.** Una lista de NodeNum no evita la falsificación de IDs. No lo uses para emergencias reales sin autenticación y validación adicionales.
- **No demuestra menor latencia ni mayor fiabilidad.** Se necesitan mediciones comparadas y tests con las placas para sostener cualquiera de esas afirmaciones.

Consulta `docs/CAMBIOS_POR_ARCHIVO.md` para la localización exacta de todos los cambios y sus puntos de inserción.