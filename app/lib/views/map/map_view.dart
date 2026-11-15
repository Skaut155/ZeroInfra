import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'package:latlong2/latlong.dart';

import '../../services/map/map_cache_service.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  String? _cacheStorePath;
  bool _isDownloadingArea = false;
  double _downloadProgress = 0;

  // Posición inicial centrada en el Campus Nord (FIB - UPC)
  static final LatLng _myLocation = LatLng(41.38879, 2.11296);

  @override
  void initState() {
    super.initState();
    _initCacheStore();
  }

  Future<void> _initCacheStore() async {
    final path = await MapCacheService.getCachePath();
    if (mounted) {
      setState(() => _cacheStorePath = path);
    }
  }

  void _zoomIn() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom < 18.0) {
      _mapController.move(
        _mapController.camera.center,
        (currentZoom + 1.0).clamp(11.0, 18.0),
      );
    }
  }

  void _zoomOut() {
    final currentZoom = _mapController.camera.zoom;
    if (currentZoom > 11.0) {
      _mapController.move(
        _mapController.camera.center,
        (currentZoom - 1.0).clamp(11.0, 18.0),
      );
    }
  }

  Future<void> _downloadCurrentArea() async {
    setState(() {
      _isDownloadingArea = true;
      _downloadProgress = 0.0;
    });

    try {
      final center = _mapController.camera.center;
      final result = await MapCacheService.preDownloadPyramidalAroundLocation(
        centerLat: center.latitude,
        centerLon: center.longitude,
        tacticalRadiusKm: 1.5,
        regionalRadiusKm: 20.0,
        onProgress: (current, total) {
          if (mounted && total > 0) {
            setState(() => _downloadProgress = current / total);
          }
        },
      );

      if (!mounted) return;

      setState(() => _isDownloadingArea = false);

      if (result.failed > 0 &&
          result.downloaded == 0 &&
          result.alreadyCached == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Error: Sin conexión a Internet. Conéctate a Wi-Fi o datos para precargar el mapa.',
            ),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
          ),
        );
      } else if (result.failed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Descarga parcial: ${result.downloaded} nuevas, ${result.alreadyCached} en caché, ${result.failed} fallidas.',
            ),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Caché piramidal completada: contexto regional (20 km) y detalle local (1,5 km). ${result.downloaded} teselas nuevas (${result.alreadyCached} ya estaban guardadas).',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _isDownloadingArea = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo precargar la zona actual: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleClearCache() async {
    try {
      final sizeMB = await MapCacheService.getCacheSizeMB();
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Borrar mapas offline'),
          content: Text(
            sizeMB > 0.01
                ? 'Se liberarán ${sizeMB.toStringAsFixed(2)} MB de almacenamiento local.\n\n¿Deseas eliminar todas las teselas descargadas?'
                : 'El almacenamiento de mapas ya está vacío o no contiene teselas.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            if (sizeMB > 0.01)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text(
                  'Borrar',
                  style: TextStyle(color: Colors.white),
                ),
              ),
          ],
        ),
      );

      if (confirm != true) return;
      await MapCacheService.clearCache();
      if (!mounted) return;

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caché de mapas eliminada correctamente.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo borrar la caché de mapas: $error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Nodos simulados en el mapa mientras se conectan las tramas GPS de LoRa
  final List<Map<String, dynamic>> _mockNodes = [
    {
      'name': 'Mi Nodo (ESP32)',
      'position': LatLng(41.38879, 2.11296),
      'type': 'self',
      'battery': 88,
      'snr': '8.5 dB',
    },
    {
      'name': 'Gateway MQTT (Vertex)',
      'position': LatLng(41.38980, 2.11450),
      'type': 'gateway',
      'battery': 100,
      'snr': '11.2 dB',
    },
    {
      'name': 'Repetidor Malla (A5)',
      'position': LatLng(41.38720, 2.11180),
      'type': 'repeater',
      'battery': 64,
      'snr': '4.1 dB',
    },
    {
      'name': 'Alerta SOS Activa',
      'position': LatLng(41.38650, 2.11520),
      'type': 'sos',
      'battery': 42,
      'snr': '-2.3 dB',
    },
  ];

  Color _getNodeColor(String type) {
    switch (type) {
      case 'self':
        return Colors.blueAccent;
      case 'gateway':
        return Colors.purpleAccent;
      case 'repeater':
        return Colors.greenAccent;
      case 'sos':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  IconData _getNodeIcon(String type) {
    switch (type) {
      case 'self':
        return Icons.my_location;
      case 'gateway':
        return Icons.router;
      case 'repeater':
        return Icons.cell_tower;
      case 'sos':
        return Icons.warning;
      default:
        return Icons.radio;
    }
  }

  void _showNodeDetails(Map<String, dynamic> node) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getNodeColor(node['type'])
                        .withOpacity(0.2),
                    child: Icon(
                      _getNodeIcon(node['type']),
                      color: _getNodeColor(node['type']),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node['name'],
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Tipo: ${node['type'].toString().toUpperCase()}',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (node['type'] == 'sos')
                    const Chip(
                      label: Text(
                        'EMERGENCIA',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      backgroundColor: Colors.redAccent,
                    ),
                ],
              ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Batería',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${node['battery']}%',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text(
                        'Señal SNR',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${node['snr']}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      const Text(
                        'Coordenadas',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(node['position'] as LatLng).latitude.toStringAsFixed(4)}, ${(node['position'] as LatLng).longitude.toStringAsFixed(4)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_cacheStorePath == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 16.0,
              maxZoom: 18.0,
              minZoom: 11.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pti.zeroinfra',
                tileProvider: CachedTileProvider(
                  maxStale: const Duration(days: 365),
                  store: FileCacheStore('$_cacheStorePath/dio_store'),
                ),
              ),
              MarkerLayer(
                markers: _mockNodes.map((node) {
                  final position = node['position'] as LatLng;
                  final type = node['type'] as String;
                  return Marker(
                    point: position,
                    width: 50,
                    height: 50,
                    child: GestureDetector(
                      onTap: () => _showNodeDetails(node),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        decoration: BoxDecoration(
                          color: _getNodeColor(type),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _getNodeColor(type).withOpacity(0.5),
                              blurRadius: type == 'sos' ? 12 : 6,
                              spreadRadius: type == 'sos' ? 4 : 1,
                            ),
                          ],
                        ),
                        child: Icon(
                          _getNodeIcon(type),
                          color: Colors.black87,
                          size: 26,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // Tarjeta flotante superior con estado de red
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Theme.of(context).cardColor.withOpacity(0.92),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14.0,
                  vertical: 10.0,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.hub, color: Colors.deepOrange, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Red LoRa: 4 nodos visibles',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Descargar zona para uso offline',
                      icon: _isDownloadingArea
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.download_for_offline_outlined,
                              color: Colors.blueAccent,
                            ),
                      onPressed: _isDownloadingArea
                          ? null
                          : _downloadCurrentArea,
                    ),
                    IconButton(
                      tooltip: 'Borrar mapas guardados',
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: _isDownloadingArea ? null : _handleClearCache,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Malla Activa',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_isDownloadingArea)
            Positioned(
              top: 76,
              left: 20,
              right: 20,
              child: LinearProgressIndicator(
                value: _downloadProgress,
                backgroundColor: Colors.black54,
                color: Colors.greenAccent,
              ),
            ),

          // Botonera de control cartográfico
          Positioned(
            bottom: 24,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_in',
                  tooltip: 'Acercar mapa',
                  backgroundColor: Theme.of(context).cardColor
                      .withOpacity(0.95),
                  onPressed: _zoomIn,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'btn_zoom_out',
                  tooltip: 'Alejar mapa',
                  backgroundColor: Theme.of(context).cardColor
                      .withOpacity(0.95),
                  onPressed: _zoomOut,
                  child: const Icon(Icons.remove, color: Colors.white),
                ),
                const SizedBox(height: 14),
                FloatingActionButton.small(
                  heroTag: 'btn_recenter',
                  tooltip: 'Centrar en Campus Nord',
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  onPressed: () => _mapController.move(_myLocation, 16.0),
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
