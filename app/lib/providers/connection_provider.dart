import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../data/mesh_repository.dart';
import '../models/connection_status.dart';
import '../models/discovered_device.dart';

/// Estado de la vista Nodos: escaneo BLE, conexión con el nodo y errores.
///
/// Convierte las excepciones de `MeshRepository` en [errorMessage] (y
/// [needsSettings] si hay que ir a los ajustes); sus métodos no lanzan.
class ConnectionProvider extends ChangeNotifier {
  ConnectionProvider(this._repository) {
    _status = _repository.status;
    _subscriptions = [
      _repository.statusStream.listen((status) {
        _status = status;
        if (status == ConnectionStatus.disconnected) _connectedDevice = null;
        notifyListeners();
      }),
      _repository.scanResults.listen((devices) {
        _devices = devices;
        notifyListeners();
      }),
      _repository.isScanning.listen((scanning) {
        _isScanning = scanning;
        notifyListeners();
      }),
    ];
  }

  final MeshRepository _repository;
  late final List<StreamSubscription<dynamic>> _subscriptions;

  late ConnectionStatus _status;
  List<DiscoveredDevice> _devices = const [];
  bool _isScanning = false;
  DiscoveredDevice? _connectedDevice;
  String? _errorMessage;
  bool _needsSettings = false;

  ConnectionStatus get status => _status;
  bool get isConnected => _status.isConnected;
  /// true mientras hay un escaneo en marcha.
  bool get isScanning => _isScanning;
  /// Nodos encontrados en el último escaneo.
  List<DiscoveredDevice> get devices => _devices;
  /// Dispositivo conectado; null si no hay conexión.
  DiscoveredDevice? get connectedDevice => _connectedDevice;
  /// Motivo del último fallo, para mostrarlo; null si la última acción fue bien.
  String? get errorMessage => _errorMessage;
  /// true: el permiso está denegado de forma permanente; ofrecer [openSettings].
  bool get needsSettings => _needsSettings;

  Future<void> startScan() => _run(_repository.startScan);

  Future<void> stopScan() => _run(_repository.stopScan);

  /// Conecta con [device] y descarga su configuración (puede tardar segundos).
  Future<void> connect(DiscoveredDevice device) async {
    final ok = await _run(() => _repository.connect(device.id));
    if (ok && _status.isConnected) {
      _connectedDevice = device;
      notifyListeners();
    }
  }

  Future<void> disconnect() => _run(_repository.disconnect);

  /// Abre los ajustes de la app en el sistema para conceder los permisos.
  Future<void> openSettings() => openAppSettings();

  /// Descarta el error mostrado.
  void clearError() {
    _errorMessage = null;
    _needsSettings = false;
    notifyListeners();
  }

  // Ejecuta una acción del repositorio y convierte sus errores en un mensaje
  // para la interfaz. Devuelve true si terminó sin error.
  Future<bool> _run(Future<void> Function() action) async {
    _errorMessage = null;
    _needsSettings = false;
    notifyListeners();
    try {
      await action();
      return true;
    } on MeshPermissionException catch (e) {
      _errorMessage = 'Faltan permisos de Bluetooth para buscar nodos.';
      _needsSettings = e.permanentlyDenied;
    } on TimeoutException catch (e) {
      _errorMessage = e.message ?? 'El nodo no responde.';
    } on StateError catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'No se pudo completar la operación: $e';
    }
    notifyListeners();
    return false;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }
}
