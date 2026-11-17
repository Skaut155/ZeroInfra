import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/permissions/permission_service.dart';
import '../../models/discovered_device.dart';
import '../mesh_repository.dart';
import 'mesh_transport.dart';
import 'meshtastic_ble_service.dart';

/// [MeshTransport] real: adapta [MeshtasticBleService] (flutter_blue_plus) a
/// la interfaz que usa `MeshtasticClient`.
///
/// Pide los permisos de Bluetooth antes de cada escaneo o conexión y
/// traduce sus fallos a [MeshPermissionException] y [StateError].
class BleMeshTransport implements MeshTransport {
  BleMeshTransport([MeshtasticBleService? service])
      : _service = service ?? MeshtasticBleService();

  final MeshtasticBleService _service;
  // Dispositivos vistos en el escaneo, por id, para conectar sin buscarlos.
  final Map<String, BluetoothDevice> _seen = {};
  bool _initialized = false;

  // Se llama antes de cada escaneo o conexión y no al arrancar la app, para
  // que los diálogos de permisos salgan cuando el usuario usa el Bluetooth.
  Future<void> _ensureReady() async {
    final permission = await PermissionService.requestBluetoothPermissions();
    if (permission != BlePermissionStatus.granted) {
      throw MeshPermissionException(
        permanentlyDenied: permission == BlePermissionStatus.permanentlyDenied,
      );
    }
    if (!_initialized) {
      if (!await _service.initialize()) {
        throw StateError('Este dispositivo no soporta Bluetooth');
      }
      _initialized = true;
    }
  }

  @override
  Stream<List<DiscoveredDevice>> get scanResults =>
      _service.scanResults.map((results) => results.map(_toDevice).toList());

  // Si el anuncio no trae nombre, usa el del sistema o uno genérico.
  DiscoveredDevice _toDevice(ScanResult result) {
    final id = result.device.remoteId.str;
    _seen[id] = result.device;
    final advName = result.advertisementData.advName;
    final platformName = result.device.platformName;
    return DiscoveredDevice(
      id: id,
      name: advName.isNotEmpty
          ? advName
          : (platformName.isNotEmpty ? platformName : 'Nodo Meshtastic'),
      rssi: result.rssi,
    );
  }

  @override
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  @override
  Future<void> startScan() async {
    await _ensureReady();
    try {
      await _service.startScan();
    } on TimeoutException {
      throw StateError('El Bluetooth está apagado');
    }
  }

  @override
  Future<void> stopScan() => _service.stopScan();

  @override
  Future<void> connect(String deviceId) async {
    await _ensureReady();
    // fromId permite reconectar a un nodo conocido sin volver a escanear.
    await _service.connect(_seen[deviceId] ?? BluetoothDevice.fromId(deviceId));
  }

  @override
  Future<void> disconnect() => _service.disconnect();

  @override
  Stream<bool> get linkState => _service.connectionStateStream
      .where((s) =>
          s == BluetoothConnectionState.connected ||
          s == BluetoothConnectionState.disconnected)
      .map((s) => s == BluetoothConnectionState.connected);

  @override
  Stream<List<int>> get fromRadioStream => _service.fromRadioStream;

  @override
  Future<void> writeToRadio(List<int> bytes) => _service.writeToRadio(bytes);

  @override
  Future<void> drainFromRadio() => _service.drainFromRadio();

  @override
  Future<void> dispose() => _service.dispose();
}
