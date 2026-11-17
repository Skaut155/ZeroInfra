// Referencia: https://pub.dev/packages/flutter_blue_plus#getting-started
// Guía: https://meshtastic.org/docs/development/device/client-api/

import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/meshtastic_ble.dart';

/// Servicio de bajo nivel para hablar con un nodo Meshtastic por BLE.
///
/// Esta clase gestiona exclusivamente el intercambio de **bytes crudos** (`List<int>`)
/// siguiendo el protocolo GATT y el patrón de "Timbre y Buzón" del firmware:
/// - **Escaneo y Conexión:** Localiza el nodo mediante su UUID de servicio, establece
///   el enlace BLE (en Android, `connect()` ya negocia el MTU) y descubre sus
///   endpoints críticos.
/// - **Buzón (`fromRadio`):** Característica de lectura de donde se extraen los paquetes binarios.
/// - **Timbre (`fromNum`):** Característica de notificación que avisa cuándo hay datos pendientes.
/// - **Escritura (`toRadio`):** Canal por el cual la app envía tramas hacia el nodo.
///
/// Flujo de uso típico:
/// 1. [initialize] una vez al arrancar la app.
/// 2. [startScan] y escuchar [scanResults] para mostrar los nodos cercanos.
/// 3. Suscribirse a [fromRadioStream] y a [connectionStateStream].
/// 4. [connect] con el dispositivo elegido por el usuario.
/// 5. [writeToRadio] para enviar paquetes al nodo y [drainFromRadio] para
///    forzar el primer vaciado del buzón (tras enviar `want_config_id`).
/// 6. [disconnect] al terminar y [dispose] al destruir el servicio.
class MeshtasticBleService {
  // UUID del servicio y de las características de Meshtastic. Se guardan como
  // Guid (no como texto) para compararlos sin depender del formato.
  // Coinciden con los publicados en la Client API de Meshtastic; conviene
  // confirmarlos contra la placa real con nRF Connect (guía, paso 2).
  final Guid _serviceGuid = Guid(AppConstants.meshtasticUUID);
  final Guid _toRadioGuid = Guid(AppConstants.writeToRadioUUID);
  final Guid _fromRadioGuid = Guid(AppConstants.readFromRadioUUID);
  final Guid _fromNumGuid = Guid(AppConstants.fromNumUUID);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _toRadio;
  BluetoothCharacteristic? _fromRadio;

  // Suscripción al estado del adaptador Bluetooth del móvil (encendido,
  // apagado...). Se guarda para poder cancelarla y evitar duplicados.
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  // Suscripción al estado de conexión del dispositivo del intento de conexión
  // en curso (o de la conexión establecida). Se guarda para cancelarla de
  // forma explícita: al fallar un intento, al conectar con otro nodo y en
  // [dispose]. Así nunca quedan listeners duplicados de intentos anteriores.
  StreamSubscription<BluetoothConnectionState>? _connSub;

  // Número del intento de conexión actual. Cada llamada a [connect] (y
  // [dispose]) lo incrementa; un listener de un intento anterior compara su
  // número con este y, si no coincide, ignora el evento.
  int _attempt = 0;

  // true mientras [connect] está en marcha; evita dos conexiones simultáneas.
  bool _isConnecting = false;

  // Controlador (tubería/pipe) por el que se añade cualquier notificación sobre
  // el estado de la conexión.
  final _connectionController =
      StreamController<BluetoothConnectionState>.broadcast();

  /// Estado de la conexión con el nodo, para la interfaz gráfica.
  Stream<BluetoothConnectionState> get connectionStateStream =>
      _connectionController.stream;

  // Pipe por la que se añaden los bytes que llegan desde fromRadio (punto de
  // entrada de los datos a procesar). Únicamente este servicio añade datos.
  // Es `.broadcast()` para que varios puntos de la app puedan ESCUCHAR a la
  // vez. Ojo: un stream broadcast no guarda nada; lo que se emita cuando no
  // hay ningún oyente se pierde, así que hay que suscribirse antes de conectar.
  final _fromRadioController = StreamController<List<int>>.broadcast();

  /// Bytes leídos de `fromRadio` (un evento por paquete). Los errores de
  /// lectura llegan como eventos de error de este mismo stream.
  Stream<List<int>> get fromRadioStream => _fromRadioController.stream;

  // Flag para indicar que se está leyendo de fromRadio y evitar lecturas
  // concurrentes. Solo lo baja el `finally` de [drainFromRadio].
  bool _isReading = false;
  // Flag para indicar que ha llegado un aviso mientras se estaba vaciando el
  // buzón: hay que dar otra vuelta al terminar.
  bool _drainAgain = false;

  /// Comprueba que el móvil soporta Bluetooth y empieza a vigilar el estado
  /// del adaptador.
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

  /// Resultados del escaneo en curso.
  ///
  /// Usa `onScanResults`, que se vacía entre escaneos, de modo que la lista
  /// que ve la interfaz nunca mezcla resultados de un escaneo anterior.
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.onScanResults;

  /// Escanea buscando solo dispositivos que anuncian el servicio Meshtastic.
  ///
  /// Espera hasta 5 segundos a que el Bluetooth esté encendido; si no lo
  /// está, lanza un `TimeoutException`.
  Future<void> startScan({
    Duration timeout = const Duration(seconds: 15),
  }) async {
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

  /// Conecta con [device] (el que el usuario ha seleccionado) y encuentra los
  /// endpoints de Meshtastic: `toRadio`, `fromRadio` y `fromNum`.
  ///
  /// - Si ya se está conectado a ese mismo dispositivo, no hace nada.
  /// - Si se está conectado a otro, lo desconecta primero.
  /// - Si ya hay otra llamada a [connect] en marcha, lanza un `StateError`.
  ///
  /// Si algo falla, deja el servicio desconectado y relanza la excepción.
  Future<void> connect(BluetoothDevice device) async {
    if (_isConnecting) {
      throw StateError('Ya hay una conexión en curso');
    }
    final current = _device;
    if (current != null && current.remoteId == device.remoteId) return;

    _isConnecting = true;
    // A partir de aquí, los listeners de intentos anteriores quedan obsoletos.
    final attempt = ++_attempt;
    // true mientras la interfaz ha recibido un `connected` de este intento y
    // todavía no su `disconnected` correspondiente.
    var sawConnected = false;

    try {
      await FlutterBluePlus.stopScan(); // deja de buscar/escanear dispositivos

      // Cancelar la suscripción de un intento o conexión anterior ANTES de
      // desconectar, para que su `disconnected` tardío no borre el estado de
      // la conexión nueva.
      await _connSub?.cancel();
      _connSub = null;
      if (current != null) {
        try {
          await current.disconnect();
        } catch (_) {
          // Ya estaba desconectado: no hay nada que hacer.
        }
        _clear();
        _emitConnectionState(BluetoothConnectionState.disconnected);
      }

      // Se escucha el estado ANTES de conectar para no perder ningún evento.
      // `connectionState` emite el estado actual nada más suscribirse, y en un
      // dispositivo aún sin conectar ese estado es `disconnected`: no es una
      // desconexión real, así que se ignora hasta haber visto un `connected`.
      _connSub = device.connectionState.listen((state) {
        if (attempt != _attempt) return; // evento de un intento anterior
        if (state == BluetoothConnectionState.connected) {
          sawConnected = true;
        } else if (state == BluetoothConnectionState.disconnected &&
            !sawConnected) {
          return;
        }
        _emitConnectionState(state);
        if (state == BluetoothConnectionState.disconnected) {
          // Desconexión real: limpiar y soltar esta suscripción. La interfaz
          // ya ha sido avisada, así que el `catch` no debe repetir el aviso.
          sawConnected = false;
          _clear();
          final sub = _connSub;
          _connSub = null;
          unawaited(sub?.cancel());
        }
      });

      // En Android, `connect()` ya pide por defecto un MTU de 512 bytes (su
      // parámetro `mtu`), para que los mensajes Protobuf viajen sin
      // fragmentarse; no hay que llamar además a `requestMtu`. En iOS el SO
      // negocia el MTU automáticamente.
      await device.connect();

      // Tras conectar, la tabla GATT del periférico está en blanco en la memoria del móvil.
      // Hay que volver a descubrir los servicios después de cada conexión.
      final services = await device.discoverServices();
      final service = services.firstWhere(
        (s) => s.uuid == _serviceGuid, // UUID del servicio principal de Meshtastic
        orElse: () =>
            throw StateError('El dispositivo no ofrece el servicio Meshtastic'),
      );

      BluetoothCharacteristic? toRadio;
      BluetoothCharacteristic? fromRadio;
      BluetoothCharacteristic? fromNum;
      for (final c in service.characteristics) {
        if (c.uuid == _toRadioGuid) {
          toRadio = c;
        } else if (c.uuid == _fromRadioGuid) {
          fromRadio = c;
        } else if (c.uuid == _fromNumGuid) {
          fromNum = c;
        }
      }
      // Si falta alguna de las tres características, se aborta la conexión
      // (el `catch` de abajo desconecta).
      if (toRadio == null || fromRadio == null || fromNum == null) {
        throw StateError('Faltan características de Meshtastic en el nodo');
      }

      // Escribe en el descriptor CCCD de fromNum para suscribir el móvil a
      // sus notificaciones.
      await fromNum.setNotifyValue(true);
      // Escucha el stream de notificaciones: cada aviso de fromNum significa
      // que hay paquetes pendientes en fromRadio.
      final fromNumSub = fromNum.onValueReceived.listen((_) {
        drainFromRadio();
      });
      // flutter_blue_plus cancela esta suscripción al desconectarse el
      // dispositivo. (`delayed` y `next` solo son para suscripciones a
      // `connectionState` creadas antes de conectar.)
      device.cancelWhenDisconnected(fromNumSub);

      // Si el nodo se ha desconectado durante la preparación, no dar la
      // conexión por buena.
      if (attempt != _attempt || !device.isConnected) {
        throw StateError('El nodo se desconectó durante la conexión');
      }

      // Se guardan las referencias en el estado de la clase solo después de
      // que todas las etapas anteriores hayan tenido éxito, dejando el
      // servicio formalmente en estado conectado.
      _toRadio = toRadio;
      _fromRadio = fromRadio;
      _device = device;
    } catch (e) {
      debugPrint('Error al conectar con el nodo BLE: $e');
      if (attempt == _attempt) {
        // Soltar el listener de este intento fallido para que no se acumule.
        await _connSub?.cancel();
        _connSub = null;
      }
      try {
        await device.disconnect(); // forzar desconexión
      } catch (_) {
        // No se había llegado a conectar.
      }
      if (attempt == _attempt) {
        _clear();
        // La suscripción ya está cancelada: si la interfaz llegó a ver
        // `connected`, hay que avisarle a mano de que se ha desconectado.
        if (sawConnected) {
          _emitConnectionState(BluetoothConnectionState.disconnected);
        }
      }
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  /// Envía bytes al nodo por `toRadio` usando escritura con respuesta.
  Future<void> writeToRadio(List<int> bytes) async {
    final c = _toRadio;
    if (c == null) {
      throw StateError('No hay característica toRadio. ¿Estás conectado?');
    }
    await c.write(bytes);
  }

  /// Desconecta del nodo actual. No hace nada si no hay ninguno.
  Future<void> disconnect() async => _device?.disconnect();

  // Publica un estado de conexión hacia la interfaz (si el stream sigue abierto).
  void _emitConnectionState(BluetoothConnectionState state) {
    if (!_connectionController.isClosed) _connectionController.add(state);
  }

  // Olvida la conexión en caso de error o desconexión.
  //
  // No toca `_isReading` ni `_drainAgain` a propósito: si hay un vaciado en
  // marcha, es su `finally` quien los libera. Si se bajaran aquí, podría
  // arrancar un segundo vaciado en paralelo con el que aún no ha terminado.
  void _clear() {
    _toRadio = null;
    _fromRadio = null;
    _device = null;
  }

  /// Libera los recursos del servicio. No se puede volver a usar después.
  Future<void> dispose() async {
    _attempt++; // invalida cualquier listener o intento de conexión pendiente
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _connSub?.cancel();
    _connSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {
      // Ya estaba desconectado.
    }
    _clear();
    await _connectionController.close();
    await _fromRadioController.close();
  }

  /// Vacía los paquetes pendientes del buzón `fromRadio`: lee repetidamente
  /// hasta que el nodo devuelve una lectura vacía y publica cada paquete en
  /// [fromRadioStream].
  ///
  /// Se llama sola con cada aviso de `fromNum`. El cliente debe llamarla
  /// además una vez tras enviar `want_config_id`, para el vaciado inicial.
  /// Si ya hay un vaciado en marcha, no lee en paralelo: deja anotado que hay
  /// que repetir y vuelve enseguida.
  ///
  /// Los errores de lectura no se lanzan: se publican como error en
  /// [fromRadioStream].
  Future<void> drainFromRadio() async {
    if (_isReading) {
      _drainAgain = true; // llegó un aviso mientras leíamos: repetir al terminar
      return;
    }
    _isReading = true;

    try {
      do {
        // Se baja la bandera ANTES de leer: si llega otro aviso durante esta
        // vuelta, la volverá a subir y se dará exactamente una vuelta más.
        _drainAgain = false;

        final characteristic = _fromRadio;
        if (characteristic == null) return; // sin conexión: nada que leer

        try {
          while (true) {
            final bytes = await characteristic.read();
            if (!identical(characteristic, _fromRadio)) {
              // La conexión se cerró o se sustituyó mientras leíamos: estos
              // bytes ya no interesan. Si hay una conexión nueva, se vacía esa.
              _drainAgain = _fromRadio != null;
              break;
            }
            if (bytes.isEmpty) break; // buzón vacío
            if (!_fromRadioController.isClosed) _fromRadioController.add(bytes);
          }
        } catch (e, st) {
          if (identical(characteristic, _fromRadio)) {
            // Error real de la conexión actual: avisar a quien escucha y parar.
            debugPrint('Error al leer de fromRadio: $e');
            if (!_fromRadioController.isClosed) {
              _fromRadioController.addError(e, st);
            }
            _drainAgain = false;
          } else {
            // La lectura falló porque la conexión ya no existe: no es un
            // error que deba ver la app. Si hay una conexión nueva, se vacía.
            _drainAgain = _fromRadio != null;
          }
        }
      } while (_drainAgain);
    } finally {
      _isReading = false;
      _drainAgain = false;
    }
  }
}
