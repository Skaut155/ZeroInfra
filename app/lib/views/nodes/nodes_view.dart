import 'package:flutter/material.dart';

class NodesView extends StatefulWidget {
  const NodesView({super.key});

  @override
  State<NodesView> createState() => _NodesViewState();
}

class _NodesViewState extends State<NodesView> {
  bool _isScanning = false;
  String? _connectedDeviceId = 'Meshtastic_ESP32_A4F2';

  final List<Map<String, dynamic>> _mockDevices = [
    {
      'name': 'Meshtastic_ESP32_A4F2',
      'id': '24:6F:28:B1:A4:F2',
      'rssi': -68,
      'battery': 88,
      'isGateway': false,
    },
  ];

  void _toggleScan() {
    setState(() {
      _isScanning = !_isScanning;
    });

    if (_isScanning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buscando nodos Meshtastic cercanos por Bluetooth...'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _connectedDeviceId != null
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.red.withValues(alpha: 0.15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: _connectedDeviceId != null ? Colors.green : Colors.red,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    _connectedDeviceId != null
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    size: 36,
                    color: _connectedDeviceId != null
                        ? Colors.green
                        : Colors.red,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _connectedDeviceId != null
                              ? 'Nodo local enlazado'
                              : 'Sin conexion a placa LoRa',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _connectedDeviceId ??
                              'Escanea para vincular un nodo ESP32',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_connectedDeviceId != null)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _connectedDeviceId = null;
                        });
                      },
                      child: const Text(
                        'Desconectar',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nodos Detectados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _toggleScan,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(_isScanning ? 'Buscando...' : 'Escanear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._mockDevices.map((device) {
            final isConnected = device['name'] == _connectedDeviceId;
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: device['isGateway']
                      ? Colors.purple[800]
                      : Colors.blueGrey[800],
                  child: Icon(
                    device['isGateway'] ? Icons.router : Icons.radio,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  device['name'],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'MAC: ${device['id']} • RSSI: ${device['rssi']} dBm',
                ),
                trailing: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected ? Colors.green[800] : null,
                  ),
                  onPressed: () {
                    setState(() {
                      _connectedDeviceId = device['name'];
                    });
                  },
                  child: Text(isConnected ? 'Activo' : 'Vincular'),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
