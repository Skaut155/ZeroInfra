/// Estado de la conexión entre el móvil y su nodo Meshtastic.
///
/// Recorre `disconnected → connecting → configuring → connected`; ante
/// cualquier fallo o pérdida del enlace vuelve a [disconnected]. Lo expone
/// `ConnectionProvider` (vista Nodos).
enum ConnectionStatus {
  /// Sin enlace con ningún nodo. No se puede enviar nada.
  disconnected,
  /// Estableciendo el enlace BLE.
  connecting,
  /// Enlace BLE listo; descargando configuración, canales y nodos del nodo.
  configuring,
  /// Configuración descargada: se pueden enviar mensajes y SOS.
  connected;

  bool get isConnected => this == ConnectionStatus.connected;

  /// true mientras la conexión está en curso ([connecting] o [configuring]).
  bool get isBusy =>
      this == ConnectionStatus.connecting ||
      this == ConnectionStatus.configuring;
}
