import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/mesh_message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/connection_provider.dart';
import '../../providers/nodes_provider.dart';

class ChatView extends StatefulWidget {
  const ChatView({super.key});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  int _selectedChannel = 0;
  int? _selectedNodeNum;

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

  Future<void> _handleSend({int? toNode}) async {
    final text = _messageController.text;
    if (text.trim().isEmpty) return;
    final bytes = utf8.encode(text).length;
    if (bytes > 233) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El mensaje supera el limite de 233 bytes UTF-8.'),
        ),
      );
      return;
    }
    final ok = await context.read<ChatProvider>().sendText(
      text,
      toNode: toNode,
      channel: _selectedChannel,
    );
    if (!mounted) return;
    if (ok) {
      _messageController.clear();
      setState(() {});
      _scrollToBottom();
    } else {
      final error = context.read<ChatProvider>().errorMessage;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Widget _buildStatusIcon(MeshMessage message) {
    final status = message.status;
    switch (status) {
      case MessageStatus.queued:
        return const Tooltip(
          message: 'En cola local (pendiente de entregar al nodo)',
          child: Icon(Icons.access_time, size: 14, color: Colors.amberAccent),
        );
      case MessageStatus.transmitted:
        return const Tooltip(
          message: 'Aceptado por el nodo local (BLE)',
          child: Icon(
            Icons.wifi_tethering,
            size: 14,
            color: Colors.lightBlueAccent,
          ),
        );
      case MessageStatus.ack:
        return Tooltip(
          message: message.isDirect
              ? 'Confirmado por el destinatario'
              : 'Retransmitido por la malla (acuse implícito)',
          child: Icon(Icons.done_all, size: 14, color: Colors.greenAccent),
        );
      case MessageStatus.failed:
        return const Tooltip(
          message: 'Fallo de envio o entrega',
          child: Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final nodes = context.watch<NodesProvider>();
    final connection = context.watch<ConnectionProvider>();
    final peerNodes = nodes.others;
    final channels = chat.channels;
    final hasChannelZero = channels.any((channel) => channel.index == 0);
    final effectiveNodeNum =
        _selectedNodeNum != null &&
            peerNodes.any((node) => node.nodeNum == _selectedNodeNum)
        ? _selectedNodeNum
        : null;
    final messages = effectiveNodeNum == null
        ? chat.broadcastMessages(_selectedChannel)
        : chat.directMessages(effectiveNodeNum);
    final byteCount = utf8.encode(_messageController.text).length;
    final selectedValue = effectiveNodeNum == null
        ? 'channel_$_selectedChannel'
        : 'node$effectiveNodeNum';

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
                      value: selectedValue,
                      items: [
                        if (!hasChannelZero)
                          const DropdownMenuItem(
                            value: 'channel_0',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.podcasts,
                                  size: 18,
                                  color: Colors.amberAccent,
                                ),
                                SizedBox(width: 8),
                                Text('Primario'),
                              ],
                            ),
                          ),
                        ...channels.map(
                          (channel) => DropdownMenuItem(
                            value: 'channel_${channel.index}',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.podcasts,
                                  size: 18,
                                  color: Colors.amberAccent,
                                ),
                                const SizedBox(width: 8),
                                Text('Difusión: ${channel.displayName}'),
                              ],
                            ),
                          ),
                        ),
                        ...peerNodes.map(
                          (node) => DropdownMenuItem(
                            value: 'node${node.nodeNum}',
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
                        setState(() {
                          if (value.startsWith('channel_')) {
                            _selectedChannel =
                                int.tryParse(
                                  value.substring('channel_'.length),
                                ) ??
                                0;
                            _selectedNodeNum = null;
                          } else if (value.startsWith('node')) {
                            _selectedNodeNum = int.tryParse(
                              value.substring('node'.length),
                            );
                          }
                        });
                        _scrollToBottom();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      effectiveNodeNum == null
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
                                    _buildStatusIcon(message),
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _messageController,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => connection.isConnected
                            ? _handleSend(toNode: effectiveNodeNum)
                            : null,
                        decoration: InputDecoration(
                          hintText: effectiveNodeNum == null
                              ? 'Transmitir en canal difusión general...'
                              : 'Mensaje directo cifrado P2P...',
                          border: InputBorder.none,
                        ),
                      ),
                      Text(
                        '$byteCount / 233 bytes UTF-8',
                        style: TextStyle(
                          fontSize: 10,
                          color: byteCount > 233
                              ? Colors.redAccent
                              : Colors.grey[500],
                        ),
                      ),
                      if (!connection.isConnected)
                        const Text(
                          'Conecta un nodo en la pestaña Nodos.',
                          style: TextStyle(fontSize: 11, color: Colors.amber),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.deepOrange),
                  onPressed: connection.isConnected
                      ? () => _handleSend(toNode: effectiveNodeNum)
                      : null,
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
