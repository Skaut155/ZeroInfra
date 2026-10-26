// Referencia: https://pub.dev/packages/flutter_blue_plus#getting-started
//Guía: https://meshtastic.org/docs/development/device/client-api/

import 'dart:async';
import 'dart:io'; // <-- Requerido para Platform.isAndroid
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/meshtastic_ble.dart';

/// Servicio de bajo nivel para hablar con un nodo Meshtastic por BLE.
///
/// Esta clase gestiona exclusivamente el intercambio de **bytes crudos** (`List<int>`)
/// siguiendo el protocolo GATT y el patrón de "Timbre y Buzón" del firmware:
/// - **Escaneo y Conexión:** Localiza el nodo mediante su UUID de servicio, establece
///   el enlace BLE, negocia el MTU (en Android) y descubre sus endpoints críticos.
/// - **Buzón (`fromRadio`):** Característica de lectura de donde se extraen los paquetes binarios.
/// - **Timbre (`fromNum`):** Característica de notificación que avisa cuándo hay datos pendientes.
/// - **Escritura (`toRadio`):** Canal por el cual la app envía tramas hacia el nodo.
///
/// Flujo de uso típico:
/// 1. [initialize] una vez al arrancar la app.
/// 2. [startScan] y escuchar [scanResults] para mostrar los nodos cercanos.
/// 3. [connect] con el dispositivo elegido por el usuario.
/// 4. [writeToRadio] para enviar paquetes al nodo.
/// 5. [disconnect] al terminar y [dispose] al destruir el servicio.

class MeshtasticBleService {
  // UUID del servicio y de las características de Meshtastic. Se guardan como
  // [Guid] (no como texto) para compararlos sin depender del formato.
  // Los valores reales deben verificarse con nRF Connect (guía, paso 2).
  final Guid _serviceGuid = Guid(AppConstants.meshtasticUUID);
  final Guid _toRadioGuid = Guid(AppConstants.writeToRadioUUID);
  final Guid _fromRadioGuid = Guid(AppConstants.readFromRadioUUID);
  final Guid _fromNumGuid = Guid(AppConstants.fromNumUUID);


  BluetoothDevice? _device;
  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromRadio;
  BluetoothCharacteristic? _fromNum;

  // Suscripción al estado del adaptador Bluetooth del móvil (encendido,
  // apagado...). Se guarda para poder cancelarla y evitar duplicados.
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  //Controlador (tubería/pipe) por el que se añade cualquier notificación sobre el estado de la conexión
  final _connectionController = StreamController<BluetoothConnectionState>.broadcast();
  //Pipe de salida hacia la interfaz gráfica
  Stream<BluetoothConnectionState> get connectionStateStream =>_connectionController.stream;

  //Pipe por la que se añaden los bytes a leer que llegan desde fromRadio 
  //(punto de entrada de datos a procesar). Añadimos .broadcast() para indicar que 
  // varios puntos pueden escuchar (añadir a la pipe) fromRadio. únicamente el servicio
  // añade datos (fromRadioController)
  final _fromRadioController = StreamController<List<int>>.broadcast();
  // Pipe de salida de datos por la que únicamente se recibe y leen bytes
  //(punto de salida de los datos).
  Stream<List<int>> get fromRadioStream => _fromRadioController.stream;

  //flag para indicar que se está leyendo en fromRadio y evitar lecturas concurrentes simultánias
  bool _isReading = false;


  // Comprueba que el móvil soporta Bluetooth y empieza a vigilar el estado
  // del adaptador.
  Future<bool> initialize() async {
    if (!await FlutterBluePlus.isSupported) {
      debugPrint('Bluetooth no soportado en este dispositivo');
      return false;
    }
    await _adapterSub?.cancel();
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      debugPrint('Estado del Bluetooth: $state');
      if (state != BluetoothAdapterState.on) _clear();
    });
    return true;
  }

  // Resultados del escaneo en curso.
  ///
  // Usa `onScanResults`, que se vacía entre escaneos, de modo que la lista
  // que ve la interfaz nunca mezcla resultados de un escaneo anterior.
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.onScanResults;

  // Escanea buscando solo dispositivos que anuncian el servicio Meshtastic.
  //
  // Espera hasta 5 segundos a que el Bluetooth esté encendido; si no lo
  // está, lanza un `TimeoutException`. 
  Future<void> startScan({Duration timeout = const Duration(seconds: 15)}) async {
    await FlutterBluePlus.adapterState
        .where((s) => s == BluetoothAdapterState.on)
        .first
        .timeout(const Duration(seconds: 5));
    await FlutterBluePlus.startScan(
      withServices: [_serviceGuid],
      timeout: timeout,
    );
  }
  /// Detiene el escaneo en curso.
  Future<void> stopScan() => FlutterBluePlus.stopScan();


  /**  Conecta un dispositivo y encuentra los endoints de Meshtastic: `toRadio`, `fromRadio` y `fromNum` 
  param: device -> dispositivo que el usuario ha seleccionado para conectarse al BLE*/
  Future<void> connect(BluetoothDevice device) async {
    await FlutterBluePlus.stopScan(); //deja de buscar/Escanear dispositivos


    final sub = device.connectionState.listen((state) {
      _connectionController.add(state);
      if (state == BluetoothConnectionState.disconnected) _clear();
    });

    device.cancelWhenDisconnected(sub, delayed: true, next: true);

   
    try {
      await device.connect();

      // En Android (MTU) a 512 bytes para que los mensajes Protobuf viajen sin fragmentarse.
      // En iOS no es necesario ya que el SO negocia el MTU automáticamente.
      if (Platform.isAndroid) {
        await device.requestMtu(512);
      }

      // Tras conectar, la tabla GATT del periférico está en blanco en la memoria del móvil
      // Hay que volver a descubrir los servicios después de cada conexión.
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == _serviceGuid, //buscamos el UUID del servicio principal de Meshtastic
        orElse: () =>
            throw StateError('El dispositivo no ofrece el servicio Meshtastic'),
      );

      for (final c in service.characteristics) {
        if (c.uuid == _toRadioGuid) {
          _toRadio = c;
        } else if (c.uuid == _fromRadioGuid) {
          _fromRadio = c;
        } else if (c.uuid == _fromNumGuid) {
          _fromNum = c;
        }
      }
      //si no se ha podido encontrar alguno de los servicios, desconectamos
      if (_toRadio == null || _fromRadio == null || _fromNum == null) {
        throw StateError('Faltan características de Meshtastic en el nodo');
      }

       //Escribir en el descriptor CCCD de la placa en el chip BLE para suscribir 
       //el móvil a las notificaciones de la característica _fromNum
       await _fromNum!.setNotifyValue(true);
       //Escucha el stream de notificaciones -> avisa de cuando hay un valor en _fromNum
       final fromNumSub = _fromNum!.onValueReceived.listen((_) {
        _drainFromRadio();
        });
        device.cancelWhenDisconnected(fromNumSub, delayed: true, next: true);
        await _drainFromRadio();
        /**
        Guarda la referencia del dispositivo en el estado de la clase solo después de que todas 
        las etapas anteriores hayan tenido éxito, dejando el servicio formalmente en estado conectado
         */
        _device = device;

    } catch (e) {
      debugPrint('Error al conectar con el nodo BLE: $e');
      await device.disconnect().catchError((_) {}); //forzar desconexión 
      _clear();
      rethrow;
    }
  }

  /*Envia bytes al nodo `ToRadio` usando escritura con respuesta */
  Future<void> writeToRadio(List<int> bytes) async {
    final c = _toRadio;
    if (c == null) {
      throw StateError('No hay característica toRadio. ¿Estás conectado?');
    }
    await c.write(bytes);
  }

  /// Desconecta del nodo actual. No hace nada si no hay ninguno.
  Future<void> disconnect() async => _device?.disconnect();

  /*limpia la conexión en caso de error o desconexión*/
  void _clear() {
    _toRadio = null;
    _fromRadio = null;
    _fromNum = null;
    _device = null;
    _isReading = false;
  }

  // Libera los recursos del servicio.
  Future<void> dispose() async {
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _device?.disconnect().catchError((_) {});
    _clear();
    await _connectionController.close();
    await _fromRadioController.close();
  }

  // Vaciar los paquetes pendientes del buffer fromRadio (endpoint de lectura)
  Future<void> _drainFromRadio() async{ 
    final characteristic = _fromRadio;
    if(characteristic == null || _isReading ) return;
    _isReading = true;
    
    try{
        while(true){
            final bytes = await characteristic.read();
            if(bytes.isEmpty) break;
            if(!_fromRadioController.isClosed) _fromRadioController.add(bytes);
        }
    } catch (e){
        debugPrint("Error al leer de fromRadio: $e");
    }finally{
        _isReading = false;
    }
  }
  

  
}