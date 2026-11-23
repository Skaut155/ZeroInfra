// Código de referencia para copiar a app/lib/data/location_uplink_service.dart
// cuando el backend haya implementado POST /api/v1/locations.
// No se instala automáticamente. Requiere consentimiento y app activa en primer plano.
// Ya existe package:http en pubspec.yaml del repositorio.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mesh_repository.dart';

class LocationUplinkService {
  LocationUplinkService({
    required MeshRepository repository,
    required Uri endpoint,
    required Future<String?> Function() bearerToken,
    http.Client? client,
  })  : _repository = repository,
        _endpoint = endpoint,
        _bearerToken = bearerToken,
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    if (_endpoint.scheme != 'https') {
      throw ArgumentError('El endpoint de ubicación debe usar HTTPS');
    }
  }

  final MeshRepository _repository;
  final Uri _endpoint;
  final Future<String?> Function() _bearerToken;
  final http.Client _client;
  final bool _ownsClient;
  Timer? _timer;
  bool _uploading = false;

  static const interval = Duration(minutes: 10);

  // Solo llamar desde la UI tras consentimiento explícito y con el backend configurado.
  // La ejecución en background exige una integración nativa adicional.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) {
      unawaited(uploadOnce());
    });
    // Opcional: enviar inmediatamente tras activar el seguimiento si se desea.
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> uploadOnce() async {
    if (_uploading) return false;
    _uploading = true;
    try {
      final nodes = _repository.nodes;
      final me = nodes.where((node) => node.isMe).firstOrNull;
      if (me == null || !me.hasPosition) return false;
      if (!me.latitude.isFinite ||
          !me.longitude.isFinite ||
          me.latitude.abs() > 90 ||
          me.longitude.abs() > 180) {
        return false;
      }
      final token = await _bearerToken();
      if (token == null || token.isEmpty) return false;
      final sentAt = DateTime.now().toUtc().toIso8601String();
      // La capa de datos actual NO conserva la hora del fix GPS.
      // Por eso fix_at=null: sent_at NO debe confundirse con la hora de medición.
      final payload = {
        'node_id': me.id,
        'latitude': me.latitude,
        'longitude': me.longitude,
        'source': 'tbeam_meshtastic',
        'fix_at': null,
        'sent_at': sentAt,
      };
      final response = await _client
          .post(_endpoint,
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } on TimeoutException {
      return false;
    } on Exception {
      // No imprimir coordenadas ni credenciales en logs.
      return false;
    } finally {
      _uploading = false;
    }
  }

  void dispose() {
    stop();
    if (_ownsClient) _client.close();
  }
}
