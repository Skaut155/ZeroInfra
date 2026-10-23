import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();

  // Posición inicial centrada en el Campus Nord (FIB - UPC)
  static final LatLng _myLocation = LatLng(41.38879, 2.11296);

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
                    backgroundColor: _getNodeColor(node['type']).withOpacity(0.2),
                    child: Icon(_getNodeIcon(node['type']), color: _getNodeColor(node['type'])),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          node['name'],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Tipo: ${node['type'].toString().toUpperCase()}',
                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  if (node['type'] == 'sos')
                    const Chip(
                      label: Text('EMERGENCIA', style: TextStyle(color: Colors.white, fontSize: 11)),
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
                      const Text('Batería', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${node['battery']}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Señal SNR', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('${node['snr']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    children: [
                      const Text('Coordenadas', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(
                        '${(node['position'] as LatLng).latitude.toStringAsFixed(4)}, ${(node['position'] as LatLng).longitude.toStringAsFixed(4)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
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
    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation,
              initialZoom: 16.0,
              maxZoom: 18.0,
              minZoom: 12.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.pti.zeroinfra',
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                child: Row(
                  children: [
                    const Icon(Icons.hub, color: Colors.deepOrange, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Red LoRa: 4 nodos visibles',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Malla Activa',
                        style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Botón flotante para recentrar mapa en la posición actual
          Positioned(
            bottom: 20,
            right: 16,
            child: FloatingActionButton.small(
              backgroundColor: Theme.of(context).colorScheme.primary,
              onPressed: () {
                _mapController.move(_myLocation, 16.0);
              },
              child: const Icon(Icons.my_location, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}