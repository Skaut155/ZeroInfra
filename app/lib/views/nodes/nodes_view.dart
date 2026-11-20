import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/connection_status.dart';
import '../../models/discovered_device.dart';
import '../../models/mesh_node.dart';
import '../../providers/connection_provider.dart';
import '../../providers/nodes_provider.dart';

/// Pestaña Nodos: escaneo BLE, conexión con el nodo propio y lista de nodos
/// de la malla.
///
/// Usa [ConnectionProvider] y [NodesProvider]; sirve de ejemplo de cómo
/// conectar una vista a los providers.
class NodesView extends StatelessWidget {
  const NodesView({super.key});

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionProvider>();
    final meshNodes = context.watch<NodesProvider>().nodes;
    final error = connection.errorMessage;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(connection: connection),
          if (error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(
              message: error,
              onOpenSettings:
                  connection.needsSettings ? connection.openSettings : null,
              onDismiss: connection.clearError,
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nodos detectados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                // No se escanea mientras hay una conexión en marcha.
                onPressed: connection.status.isBusy
                    ? null
                    : (connection.isScanning
                        ? connection.stopScan
                        : connection.startScan),
                icon: connection.isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(connection.isScanning ? 'Detener' : 'Escanear'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (connection.devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                connection.isScanning
                    ? 'Buscando nodos Meshtastic cercanos...'
                    : 'Pulsa «Escanear» para buscar nodos Meshtastic cercanos.',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ),
          for (final device in connection.devices)
            _DeviceTile(device: device, connection: connection),
          if (meshNodes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Nodos en la malla (${meshNodes.length})',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final node in meshNodes) _MeshNodeTile(node: node),
          ],
        ],
      ),
    );
  }
}

// Tarjeta superior con el estado de la conexión BLE.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.connection});

  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    final status = connection.status;
    final Color color;
    final IconData icon;
    final String title;
    switch (status) {
      case ConnectionStatus.connected:
        color = Colors.green;
        icon = Icons.bluetooth_connected;
        title = 'Nodo local enlazado';
      case ConnectionStatus.connecting:
        color = Colors.amber;
        icon = Icons.bluetooth_searching;
        title = 'Conectando...';
      case ConnectionStatus.configuring:
        color = Colors.amber;
        icon = Icons.sync;
        title = 'Descargando configuración del nodo...';
      case ConnectionStatus.disconnected:
        color = Colors.red;
        icon = Icons.bluetooth_disabled;
        title = 'Sin conexión a placa LoRa';
    }

    return Card(
      color: color.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 36, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    connection.connectedDevice?.name ??
                        'Escanea para vincular un nodo',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
            if (status.isConnected)
              TextButton(
                onPressed: connection.disconnect,
                child: const Text(
                  'Desconectar',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onDismiss,
    this.onOpenSettings,
  });

  final String message;
  final VoidCallback onDismiss;
  // null si el error no se resuelve desde los ajustes del sistema.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.red.withValues(alpha: 0.15),
      child: ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.redAccent),
        title: Text(message),
        trailing: onOpenSettings != null
            ? TextButton(
                onPressed: onOpenSettings,
                child: const Text('Abrir ajustes'),
              )
            : IconButton(icon: const Icon(Icons.close), onPressed: onDismiss),
      ),
    );
  }
}

// Un dispositivo BLE encontrado en el escaneo.
class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device, required this.connection});

  final DiscoveredDevice device;
  final ConnectionProvider connection;

  @override
  Widget build(BuildContext context) {
    final isActive = connection.connectedDevice?.id == device.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blueGrey[800],
          child: const Icon(Icons.radio, color: Colors.white),
        ),
        title: Text(
          device.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text('ID: ${device.id} • RSSI: ${device.rssi} dBm'),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isActive ? Colors.green[800] : null,
          ),
          // Solo se puede vincular estando desconectado.
          onPressed: connection.status == ConnectionStatus.disconnected
              ? () => connection.connect(device)
              : null,
          child: Text(isActive ? 'Activo' : 'Vincular'),
        ),
      ),
    );
  }
}

// Un nodo de la malla, tal como lo conoce el nodo conectado.
class _MeshNodeTile extends StatelessWidget {
  const _MeshNodeTile({required this.node});

  final MeshNode node;

  @override
  Widget build(BuildContext context) {
    final details = [
      node.id,
      if (node.hasBattery) 'Batería ${node.batteryLevel}%',
      if (node.snr != 0) 'SNR ${node.snr.toStringAsFixed(1)} dB',
      if (!node.hasPosition) 'sin GPS',
    ].join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
          node.isEmergency
              ? Icons.warning
              : (node.isMe ? Icons.my_location : Icons.cell_tower),
          color: node.isEmergency ? Colors.redAccent : null,
        ),
        title: Text(node.isMe ? '${node.name} (este nodo)' : node.name),
        subtitle: Text(details),
      ),
    );
  }
}
