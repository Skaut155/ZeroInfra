/// Papel del canal en el nodo. Meshtastic tiene un único canal primario.
enum MeshChannelRole { primary, secondary }

/// Canal de radio configurado en el nodo conectado.
///
/// Los mensajes de difusión van por un canal; lo lista `ChatProvider`.
class MeshChannel {
  const MeshChannel({
    required this.index,
    required this.name,
    required this.role,
  });

  /// Índice del canal en el nodo (0-7); es el `channel` de los mensajes.
  final int index;
  /// Vacío en el canal por defecto de Meshtastic.
  final String name;
  final MeshChannelRole role;

  bool get isPrimary => role == MeshChannelRole.primary;

  /// Nombre para la interfaz: [name] o, si está vacío, uno genérico.
  String get displayName {
    if (name.isNotEmpty) return name;
    return isPrimary ? 'Primario' : 'Canal $index';
  }
}
