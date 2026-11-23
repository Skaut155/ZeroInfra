import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mesh_repository.dart';
import '../models/emergency_alert.dart';
import '../models/mesh_message.dart';
import '../models/mesh_node.dart';

/// Estado de la vista SOS: enviar y cancelar el SOS del nodo propio, y las
/// alertas activas de otros nodos ([alerts]).
///
/// Los SOS recibidos también marcan el nodo con [MeshNode.isEmergency]
/// (`NodesProvider`) y llegan como mensajes al chat (`ChatProvider`).
class SosProvider extends ChangeNotifier {
  SosProvider(this._repository) {
    _me = _findMe(_repository.nodes);
    _subscriptions = [
      _repository.nodesStream.listen((nodes) {
        _me = _findMe(nodes);
        notifyListeners();
      }),
      _repository.alerts.listen((_) => notifyListeners()),
      _repository.messages.listen((message) {
        if (message.isMe && message.isSos) {
          _lastSignal = message;
          notifyListeners();
        }
      }),
    ];
  }

  final MeshRepository _repository;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  MeshNode? _me;
  MeshMessage? _lastSignal;
  bool _isSending = false;
  String? _errorMessage;

  static MeshNode? _findMe(List<MeshNode> nodes) {
    for (final node in nodes) {
      if (node.isMe) return node;
    }
    return null;
  }

  /// true mientras este nodo tiene un SOS emitido y sin cancelar.
  bool get isActive => _me?.isEmergency ?? false;
  /// true mientras se escribe el SOS en el nodo; evita envíos dobles.
  bool get isSending => _isSending;
  /// Posición del nodo conectado (la que viaja en el SOS); null sin GPS.
  double? get latitude => hasPosition ? _me?.latitude : null;
  double? get longitude => hasPosition ? _me?.longitude : null;
  bool get hasPosition => _me?.hasPosition ?? false;
  /// Último SOS o cancelación enviado, con su estado de entrega.
  MeshMessage? get lastSignal => _lastSignal;
  /// Motivo del último fallo; null si el último envío fue bien.
  String? get errorMessage => _errorMessage;
  /// Alertas EMG1 de otros nodos sin cancelar ni caducar, la más reciente
  /// última. [EmergencyAlert.isVerified] indica si la firma es válida.
  List<EmergencyAlert> get alerts => _repository.activeAlerts;

  /// Envía un SOS (un solo paquete; los reintentos son cosa del firmware).
  /// Devuelve false si falla o si ya hay un envío en curso.
  Future<bool> send() => _run(_repository.sendSos);

  /// Envía la cancelación del SOS. Mismo comportamiento que [send].
  Future<bool> cancel() => _run(_repository.cancelSos);

  Future<bool> _run(Future<MeshMessage> Function() action) async {
    if (_isSending) return false;
    _isSending = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on StateError catch (e) {
      _errorMessage = e.message;
      return false;
    } catch (e) {
      _errorMessage = 'No se pudo enviar el SOS: $e';
      return false;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
