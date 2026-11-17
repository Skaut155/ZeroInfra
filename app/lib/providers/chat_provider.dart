import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/mesh_repository.dart';
import '../models/mesh_channel.dart';
import '../models/mesh_message.dart';

/// Estado de la vista Chat: historial de mensajes, canales y envío de texto.
///
/// Acumula todo lo que emite `MeshRepository.messages` desde el arranque
/// (también los SOS) y sustituye cada mensaje propio al cambiar su estado.
class ChatProvider extends ChangeNotifier {
  ChatProvider(this._repository) {
    _channels = _repository.channels;
    _subscriptions = [
      _repository.messages.listen(_onMessage),
      _repository.channelsStream.listen((channels) {
        _channels = channels;
        notifyListeners();
      }),
    ];
  }

  final MeshRepository _repository;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  // Historial en memoria, por orden de llegada (aún no se guarda en disco).
  final List<MeshMessage> _messages = [];
  // Posición de cada mensaje en [_messages], por [MeshMessage.id] (no por id
  // de paquete).
  final Map<String, int> _indexByKey = {};
  late List<MeshChannel> _channels;
  String? _errorMessage;

  /// Todos los mensajes, de difusión y directos, por orden de llegada.
  List<MeshMessage> get messages => List.unmodifiable(_messages);
  /// Canales del nodo conectado, para elegir por dónde difundir.
  List<MeshChannel> get channels => _channels;
  /// Motivo del último envío fallido; se borra al intentar otro envío.
  String? get errorMessage => _errorMessage;

  /// Mensajes de difusión del canal [channel], en orden de llegada.
  List<MeshMessage> broadcastMessages(int channel) => _messages
      .where((m) => !m.isDirect && m.channel == channel)
      .toList();

  /// Conversación directa con el nodo [nodeNum] (en los dos sentidos).
  List<MeshMessage> directMessages(int nodeNum) => _messages
      .where((m) =>
          m.isDirect &&
          (m.isMe ? m.recipientNum == nodeNum : m.senderNum == nodeNum))
      .toList();

  /// [toNode] null = difusión por [channel]. Devuelve false si falla; el
  /// motivo queda en [errorMessage]. El estado de entrega se sigue en
  /// [messages].
  Future<bool> sendText(String text, {int? toNode, int channel = 0}) async {
    _errorMessage = null;
    try {
      await _repository.sendText(text, toNode: toNode, channel: channel);
      return true;
    } on StateError catch (e) {
      _errorMessage = e.message;
    } on ArgumentError catch (e) {
      _errorMessage = '${e.message}';
    } catch (e) {
      _errorMessage = 'No se pudo enviar el mensaje: $e';
    }
    notifyListeners();
    return false;
  }

  // Añade un mensaje nuevo o sustituye el que ya había con el mismo id (los
  // propios se reemiten al cambiar su estado de entrega).
  void _onMessage(MeshMessage message) {
    final key = message.id;
    final index = _indexByKey[key];
    if (index == null) {
      _indexByKey[key] = _messages.length;
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
