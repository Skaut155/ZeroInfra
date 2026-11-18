# Definiciones Protobuf (Meshtastic)

## 1. Origen y Versión
- **Versión del Firmware de referencia:** 2.7.26 (flasheado en las placas LilyGO T-Beam del equipo).
- **Origen:** Repositorio oficial de Meshtastic (`meshtastic/protobufs`), sincronizado con el submódulo del firmware.

---

## 2. Descripción de los Ficheros `.proto` Incluidos
Los esquemas se encuentran en la carpeta `protos/meshtastic/` y se dividen en los siguientes componentes clave:

- **`mesh.proto`**: El núcleo de la estructura de datos. Define los paquetes principales de intercambio (`ToRadio`, `FromRadio`, `MeshPacket`), además de estructuras esenciales como información de nodos (`NodeInfo`, `MyNodeInfo`), datos de usuario (`User`) y coordenadas geográficas (`Position`).
- **`portnums.proto`**: Define los números de puerto (`PortNum`) que actúan como identificadores de tipo de aplicación o servicio dentro de los paquetes de la malla (por ejemplo, texto, telemetría, posición, etc.).
- **`config.proto`**: Contiene las configuraciones globales del dispositivo y de los módulos de radio (como parámetros de LoRa, Bluetooth, Wi-Fi, pantalla o energía).
- **`module_config.proto`**: Especifica la configuración de los módulos adicionales instalados en el nodo (como MQTT, Serial, External Notification o capacidades de ATAK).
- **`telemetry.proto`**: Estructuras encargadas de empaquetar las métricas de los sensores del nodo (batería, temperatura, humedad, voltajes, etc.).
- **`channel.proto`**: Define los canales de radio, claves de cifrado y ajustes de los canales de comunicación de la malla.
- **`device_ui.proto`**: Parámetros relacionados con la interfaz de usuario en la pantalla integrada de la placa.
- **`xmodem.proto`**: Protocolo de transferencia de ficheros por lotes utilizado para tareas de mantenimiento o actualización del firmware.
- **`field_metadata.proto`** y **`atak.proto`**: Dependencias auxiliares requeridas por los esquemas de configuración y metadatos en las versiones recientes de firmware.

---

## 3. Preparación del Entorno y Cómo Regenerar el Código

### Requisitos previos
Para compilar los ficheros `.proto` a clases de Dart, necesitas tener instalado en el sistema el compilador `protobuf-compiler` y el plugin de Dart.

\`\`\`bash
sudo apt install protobuf-compiler
\`\`\`

El código Dart para la aplicación móvil se genera automáticamente ejecutando el script en la raíz del proyecto:
\`\`\`bash
protoc --proto_path=protos --dart_out=app/lib/generated protos/meshtastic/mesh.proto protos/meshtastic/portnums.proto protos/meshtastic/telemetry.proto protos/meshtastic/config.proto protos/meshtastic/module_config.proto protos/meshtastic/channel.proto protos/meshtastic/device_ui.proto protos/meshtastic/xmodem.proto protos/meshtastic/field_metadata.proto protos/meshtastic/atak.proto
\`\`\`
*(El código Dart generado en `/app/lib/generated/`).*

Si al ejecutar comandos de Dart/Flutter obtienes un error indicando que no se encuentra el comando `protoc-gen-dart`, asegúrate de añadir la ruta del caché de pub a las variables de entorno de tu terminal (`PATH`):

```bash
export PATH="$PATH":"$HOME/.pub-cache/bin"
```