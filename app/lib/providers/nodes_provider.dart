import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mesh_repository.dart';
import '../models/mesh_node.dart';

/// Nodos de la malla para la vista Mapa (y la lista de la vista Nodos).
///
/// Refleja `MeshRepository.nodes` y notifica con cada cambio de cualquier
/// nodo (posición, batería, SOS...). Sin conexión, la lista se queda como
/// estaba.
class NodesProvider extends ChangeNotifier {
  NodesProvider(this._repository) {
    _nodes = _repository.nodes;
    _subscription = _repository.nodesStream.listen((nodes) {
      _nodes = nodes;
      notifyListeners();
    });
  }

  final MeshRepository _repository;
  late final StreamSubscription<List<MeshNode>> _subscription;
  late List<MeshNode> _nodes;

  /// Todos los nodos conocidos, incluido el propio.
  List<MeshNode> get nodes => _nodes;

  /// El nodo conectado a este móvil; null antes de la primera conexión.
  /// Tras desconectar conserva el último nodo conocido.
  MeshNode? get me {
    for (final node in _nodes) {
      if (node.isMe) return node;
    }
    return null;
  }

  /// Todos menos el propio.
  List<MeshNode> get others => _nodes.where((n) => !n.isMe).toList();

  /// Los nodos que se pueden pintar en el mapa.
  List<MeshNode> get withPosition =>
      _nodes.where((n) => n.hasPosition).toList();

  /// El nodo con ese [MeshNode.nodeNum], o null si no se conoce.
  MeshNode? byNum(int nodeNum) {
    for (final node in _nodes) {
      if (node.nodeNum == nodeNum) return node;
    }
    return null;
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
