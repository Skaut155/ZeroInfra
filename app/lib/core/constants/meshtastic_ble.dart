/// Constantes generales de la app y de Meshtastic sobre BLE (UUID del servicio
/// y de sus características, y dirección de broadcast de la malla).
class AppConstants {
  
  static const String appName = "ZeroInfra";
  
  /// Dirección de destino para enviar a toda la malla (broadcast).
  static const int broadcastAddress = 0xFFFFFFFF;

  /// UUID del servicio Meshtastic.
  static const String meshtasticUUID = "6ba1b218-15a8-461f-9fa8-5dcae273eafd";

  /// UUID de `toRadio` (escritura: la app envía paquetes al nodo).
  static const String writeToRadioUUID = "f75c76d2-129e-4dad-a1dd-7866124401e7"; 

  /// UUID de `fromRadio` (lectura: paquetes que el nodo tiene para la app).
  static const String readFromRadioUUID = "2c55e69e-4993-11ed-b878-0242ac120002";  

  /// UUID de `fromNum` (leer, notificar y escribir): avisa de que hay
  /// paquetes pendientes en `fromRadio`.
  static const String fromNumUUID = "ed9da18c-a800-4f66-a670-aa7547e34453";

  /// UUID extra por el que el nodo notifica sus registros de depuración del
  /// firmware (LogRecord protobuf).
  static const String logRecordUUID = "5a3d6e49-06e6-4423-9944-e9de8cdf9547";
}
