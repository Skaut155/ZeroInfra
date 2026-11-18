import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mesh_message.dart';
import '../../services/mesh_provider.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _selectedTarget = 'broadcast';

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    context.read<MeshProvider>().sendMessage(
      text,
      recipientId: _selectedTarget,
    );
    _messageController.clear();
    _scrollToBottom();
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.queued:
        return const Tooltip(
          message: 'En cola BLE / Transfiriendo a placa',
          child: Icon(Icons.access_time, size: 14, color: Colors.amberAccent),
        );
      case MessageStatus.transmitted:
        return const Tooltip(
          message: 'Emitido por radio LoRa (TX)',
          child: Icon(
            Icons.wifi_tethering,
            size: 14,
            color: Colors.lightBlueAccent,
          ),
        );
      case MessageStatus.ack:
        return const Tooltip(
          message: 'ACK confirmado por el receptor',
          child: Icon(Icons.done_all, size: 14, color: Colors.greenAccent),
        );
      case MessageStatus.failed:
        return const Tooltip(
          message: 'Sin acuse de recibo (Fallo de enlace)',
          child: Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MeshProvider>();
    final peerNodes = provider.nodes
        .where((node) => node.id != provider.connectedNodeId)
        .toList();
    final messages = provider.getMessagesForChannel(_selectedTarget);

    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Theme.of(context).cardColor,
            child: Row(
              children: [
                const Icon(
                  Icons.hub_outlined,
                  size: 20,
                  color: Colors.deepOrange,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Canal:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedTarget,
                      items: [
                        const DropdownMenuItem(
                          value: 'broadcast',
                          child: Row(
                            children: [
                              Icon(
                                Icons.podcasts,
                                size: 18,
                                color: Colors.amberAccent,
                              ),
                              SizedBox(width: 8),
                              Text('Difusión General (Canal 0)'),
                            ],
                          ),
                        ),
                        ...peerNodes.map(
                          (node) => DropdownMenuItem(
                            value: node.id,
                            child: Row(
                              children: [
                                Icon(
                                  node.isGateway
                                      ? Icons.router
                                      : Icons.person_pin_circle_outlined,
                                  size: 18,
                                  color: Colors.blueAccent,
                                ),
                                const SizedBox(width: 8),
                                Text('P2P: ${node.name}'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _selectedTarget = value);
                        _scrollToBottom();
                      },
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Simular mensaje LoRa entrante',
                  icon: const Icon(
                    Icons.sim_card_download_outlined,
                    size: 20,
                    color: Colors.tealAccent,
                  ),
                  onPressed: () {
                    provider.simulateIncomingMessage(
                      fromNodeId: _selectedTarget == 'broadcast'
                          ? null
                          : _selectedTarget,
                      isDirect: _selectedTarget != 'broadcast',
                    );
                    _scrollToBottom();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      _selectedTarget == 'broadcast'
                          ? 'No hay mensajes en el canal de difusión.'
                          : 'Canal directo vacío con este nodo.',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Align(
                        alignment: message.isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.78,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: message.isEmergency
                                ? Colors.red[900]
                                : (message.isMe
                                      ? Colors.deepOrange[700]
                                      : Colors.grey[850]),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(12),
                              topRight: const Radius.circular(12),
                              bottomLeft: Radius.circular(
                                message.isMe ? 12 : 2,
                              ),
                              bottomRight: Radius.circular(
                                message.isMe ? 2 : 12,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: message.isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                            children: [
                              if (!message.isMe)
                                Text(
                                  message.senderName,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              Text(message.content),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.grey[400],
                                    ),
                                  ),
                                  if (message.isMe) ...[
                                    const SizedBox(width: 6),
                                    _buildStatusIcon(message.status),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey[800]!)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onSubmitted: (_) => _handleSend(),
                    decoration: InputDecoration(
                      hintText: _selectedTarget == 'broadcast'
                          ? 'Transmitir en canal difusión general...'
                          : 'Mensaje directo cifrado P2P...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.deepOrange),
                  onPressed: _handleSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
