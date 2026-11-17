import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Resultado de comprobar o pedir los permisos que necesita el BLE.
enum BlePermissionStatus {
  /// Todos los permisos necesarios están concedidos: se puede escanear y conectar.
  granted,

  /// Falta algún permiso, pero se puede volver a pedir.
  denied,

  /// Falta algún permiso y el sistema ya no mostrará el diálogo: el usuario
  /// tiene que concederlo desde los ajustes (ver `openAppSettings()` de
  /// permission_handler).
  permanentlyDenied,
}

/// Permisos del sistema operativo que hacen falta para escanear y conectar
/// por BLE. Dependen de la plataforma y de la versión de Android.
class PermissionService {
  // Primera versión de Android (12, API 31) con los permisos BLUETOOTH_SCAN y
  // BLUETOOTH_CONNECT.
  static const int _android12Sdk = 31;

  /// Lista de permisos que exige este móvil para usar BLE.
  ///
  /// - **Android 12 o superior:** escaneo y conexión Bluetooth. 
  /// - **Android 11 o inferior:** solo la ubicación (sin ella el escaneo BLE
  ///   no devuelve resultados). Los permisos Bluetooth antiguos se conceden
  ///   al instalar y no se piden en ejecución.
  /// - **iOS:** el permiso de Bluetooth.
  static Future<List<Permission>> _requiredPermissions() async {
    if (kIsWeb) return const <Permission>[];
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await DeviceInfoPlugin().androidInfo;
        if (info.version.sdkInt >= _android12Sdk) {
          return [Permission.bluetoothScan, Permission.bluetoothConnect];
        }
        return [Permission.location];
      case TargetPlatform.iOS:
        return [Permission.bluetooth];
      default:
        return const <Permission>[];
    }
  }

  // Resume el estado de varios permisos en uno solo.
  static BlePermissionStatus _combine(Iterable<PermissionStatus> statuses) {
    if (statuses.every((s) => s.isGranted)) {
      return BlePermissionStatus.granted;
    }
    // `restricted` (iOS, control parental...) tampoco se puede resolver
    // volviendo a pedir el permiso.
    if (statuses.any((s) => s.isPermanentlyDenied || s.isRestricted)) {
      return BlePermissionStatus.permanentlyDenied;
    }
    return BlePermissionStatus.denied;
  }

  /// Pide al sistema operativo los permisos necesarios para BLE (mostrando
  /// los diálogos que hagan falta) y devuelve el resultado.
  static Future<BlePermissionStatus> requestBluetoothPermissions() async {
    final permissions = await _requiredPermissions();
    if (permissions.isEmpty) return BlePermissionStatus.granted;
    final statuses = await permissions.request();
    return _combine(statuses.values);
  }

  /// Comprueba, sin mostrar ningún diálogo, exactamente los mismos permisos
  /// que pide [requestBluetoothPermissions].
  ///
  /// En Android, un permiso que nunca se ha pedido aparece como
  /// [BlePermissionStatus.denied]; el sistema solo informa de
  /// `permanentlyDenied` de forma fiable después de haberlo pedido.
  static Future<BlePermissionStatus> checkPermissions() async {
    final permissions = await _requiredPermissions();
    final statuses = <PermissionStatus>[];
    for (final permission in permissions) {
      statuses.add(await permission.status);
    }
    return _combine(statuses);
  }
}
