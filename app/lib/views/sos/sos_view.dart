import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mesh_message.dart';
import '../../providers/connection_provider.dart';
import '../../providers/nodes_provider.dart';
import '../../providers/sos_provider.dart';

class SosView extends StatefulWidget {
  const SosView({super.key});

  @override
  State<SosView> createState() => _SosViewState();
}

class _SosViewState extends State<SosView> {
  String _statusText(MeshMessage signal) {
    switch (signal.status) {
      case MessageStatus.queued:
        return 'En cola local';
      case MessageStatus.transmitted:
        return 'Aceptado por el nodo local (BLE)';
      case MessageStatus.ack:
        return 'Retransmitido por la malla';
      case MessageStatus.failed:
        return 'Fallo de envio o entrega';
    }
  }

  Future<void> _sendOrCancel(SosProvider sos) async {
    final ok = sos.isActive
        ? await context.read<SosProvider>().cancel()
        : await context.read<SosProvider>().send();
    if (!mounted) return;
    if (!ok && sos.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sos.errorMessage!),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sos = context.watch<SosProvider>();
    final connection = context.watch<ConnectionProvider>();
    final emergencyNodes = context
        .watch<NodesProvider>()
        .others
        .where((n) => n.isEmergency)
        .toList();

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sos.isActive
                    ? Colors.red.withValues(alpha: 0.2)
                    : Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: sos.isActive ? Colors.red : Colors.amber,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    sos.isActive ? Icons.warning : Icons.info_outline,
                    color: sos.isActive ? Colors.red : Colors.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sos.isActive
                          ? 'SOS activo. La baliza se mantiene hasta cancelar.'
                          : 'Enviar SOS difundira una alerta de socorro por la malla.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: sos.isSending || !connection.isConnected
                  ? null
                  : () => _sendOrCancel(sos),
              style: ElevatedButton.styleFrom(
                backgroundColor: sos.isActive
                    ? Colors.red[800]
                    : Colors.redAccent,
                foregroundColor: Colors.white,
                fixedSize: const Size(220, 220),
                shape: const CircleBorder(),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.emergency_share, size: 70),
                  const SizedBox(height: 8),
                  Text(
                    sos.isActive ? 'CANCELAR SOS' : 'SOS',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estado local',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    if (sos.hasPosition)
                      Text(
                        'Lat: ${sos.latitude!.toStringAsFixed(5)}, Lon: ${sos.longitude!.toStringAsFixed(5)}',
                      )
                    else
                      const Text(
                        'Sin GPS (se enviará sin posición)',
                        style: TextStyle(color: Colors.amber),
                      ),
                    if (sos.lastSignal != null) ...[
                      const SizedBox(height: 8),
                      Text('Entrega: ${_statusText(sos.lastSignal!)}'),
                    ],
                  ],
                ),
              ),
            ),
            if (!connection.isConnected)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Conecta un nodo en la pestaña Nodos.',
                  style: TextStyle(color: Colors.amber),
                ),
              ),
            if (emergencyNodes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: SizedBox(
                  height: 100,
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      const Text(
                        'Alertas de nodos vecinos',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      for (final node in emergencyNodes)
                        Text(
                          '${node.name} (${node.id})${node.hasPosition ? ' - ${node.latitude.toStringAsFixed(4)}, ${node.longitude.toStringAsFixed(4)}' : ''}',
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
