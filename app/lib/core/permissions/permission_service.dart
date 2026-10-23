import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  
  /// Solicita los permisos necesarios para BLE y ubicación al sistema operativo
  static Future<bool> requestBluetoothPermissions() async {
    // 1. Agrupamos los permisos que Android e iOS exigen para escanear y conectar por BLE
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // Necesario en muchas versiones de Android para el escaneo BLE
    ].request();

    // 2. Verificamos si todos los permisos solicitados han sido concedidos
    bool allGranted = statuses.values.every((status) => status.isGranted);

    // 3. Devolvemos true si podemos continuar, o false si falta alguno
    return allGranted;
  }

  /// Comprueba de forma rápida si los permisos ya estaban concedidos previamente
  static Future<bool> checkPermissions() async {
    bool scanGranted = await Permission.bluetoothScan.isGranted;
    bool connectGranted = await Permission.bluetoothConnect.isGranted;
    
    return scanGranted && connectGranted;
  }
}