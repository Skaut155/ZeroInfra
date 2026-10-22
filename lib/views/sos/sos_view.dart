import 'package:flutter/material.dart';

class SosView extends StatefulWidget {
  const SosView({super.key});

  @override
  State<SosView> createState() => _SosViewState();
}

class _SosViewState extends State<SosView> {
  bool _isEmergencyActive = false;

  void _triggerEmergency() {
    setState(() {
      _isEmergencyActive = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Colors.redAccent,
        content: Text(
          'ALERTA SOS EMITIDA: Baliza prioritaria difundida en la malla LoRa',
        ),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _cancelEmergency() {
    setState(() {
      _isEmergencyActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _isEmergencyActive
                    ? Colors.red.withValues(alpha: 0.2)
                    : Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isEmergencyActive ? Colors.red : Colors.amber,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEmergencyActive ? Icons.warning : Icons.info_outline,
                    color: _isEmergencyActive ? Colors.red : Colors.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _isEmergencyActive
                          ? 'Baliza de auxilio activa. Emitindo coordenadas GPS de forma repetitiva.'
                          : 'El botón SOS envía un paquete de socorro con prioridad máxima a todos los nodos.',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            GestureDetector(
              onLongPress: _triggerEmergency,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isEmergencyActive
                      ? Colors.red[800]
                      : Colors.redAccent,
                  boxShadow: [
                    BoxShadow(
                      color:
                          (_isEmergencyActive ? Colors.red : Colors.redAccent)
                              .withValues(alpha: 0.5),
                      blurRadius: _isEmergencyActive ? 40 : 20,
                      spreadRadius: _isEmergencyActive ? 12 : 4,
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.emergency_share, size: 70, color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'SOS',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'Manten pulsado',
                      style: TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                  ],
                ),
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
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Coordenadas fijadas (GPS)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Precision: ±4m',
                          style: TextStyle(color: Colors.green, fontSize: 12),
                        ),
                      ],
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Text(
                          'Lat: 41.3879° N',
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                        Text(
                          'Lon: 2.1699° E',
                          style: TextStyle(color: Colors.grey[300]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isEmergencyActive)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
                onPressed: _cancelEmergency,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancelar transmision de emergencia'),
              ),
          ],
        ),
      ),
    );
  }
}
