/* Define los UUIDs de BLE  */
class AppConstants {
  // 'static' significa que la variable pertenece a la clase en sí, 
  // no necesitas crear una instancia (un objeto) para usarla.
  // 'const' indica que su valor es fijo y se conoce en tiempo de compilación.
  static const String appName = "ZeroInfra";
  
  /* Identificador para enviar broadcast*/
  static const int broadcastAddress = 0xFFFFFFFF;

  /* UUID servicio Meshtastic */
  static const String meshtasticUUID = "6ba1b218-15a8-461f-9fa8-5dcae273eafd";

  /* UUID toRadio */
  static const String writeToRadioUUID = "f75c76d2-129e-4dad-a1dd-7866124401e7"; 

  /* UUID fromRadio */
  static const String readFromRadioUUID = "2c55e69e-4993-11ed-b878-0242ac120002";  

  /* UUID fromNum --> leer, notificar y escribir */
  static const String fromNUmUUID = "ed9da18c-a800-4f66-a670-aa7547e34453";

  /*UUID extra para escribir notificaciones para depurar firmware (LogRecord protobuf)*/
  static const String logRecordUUID = "5a3d6e49-06e6-4423-9944-e9de8cdf9547";
}