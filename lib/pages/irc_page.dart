// lib/pages/irc_page.dart
// This version adds command handling (/join), fixes channel redirection bugs,
// and filters out the server's MOTD for a cleaner interface.

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// A simple data class for parsed IRC messages
class ParsedMessage {
  final String sender;
  final String content;
  final bool isNotice;

  ParsedMessage({required this.sender, required this.content, this.isNotice = false});
}

class IrcPage extends StatefulWidget {
  const IrcPage({super.key});

  @override
  State<IrcPage> createState() => _IrcPageState();
}

class _IrcPageState extends State<IrcPage> {
  final TextEditingController _nickController = TextEditingController(text: 'i2p-user');
  final TextEditingController _channelController = TextEditingController(text: '#i2p-help');
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  final List<ParsedMessage> _messages = [];

  // --- NEW STATE VARIABLES ---
  String _currentChannel = ''; // To track the actual channel we are in
  bool _hasFinishedJoin = false; // To filter out MOTD messages

  void _connect() {
    final wsUrl = Uri.parse('ws://bridge.stormycloud.org:3000');
    _channel = WebSocketChannel.connect(wsUrl);

    setState(() {
      _isConnected = true;
      _messages.clear();
      _hasFinishedJoin = false; // Reset on new connection
      _addMessage(sender: 'Status', content: 'Connecting to IRC via bridge...');
    });

    _channel!.stream.listen(
      (rawMessage) {
        // Wait for registration (001) before trying to join
        if (rawMessage.contains(' 001 ')) {
          _addMessage(sender: 'Status', content: 'Connected! Joining channel...');
          _sendMessageToSocket('JOIN ${_channelController.text}');
        }
        
        _handleMessage(rawMessage);

        if (rawMessage.startsWith('PING')) {
          final pingData = rawMessage.split(' ')[1];
          _sendMessageToSocket('PONG $pingData');
        }
      },
      onDone: () {
        setState(() {
          _addMessage(sender: 'Status', content: 'Disconnected from server.');
          _isConnected = false;
        });
      },
      onError: (error) {
        setState(() {
          _addMessage(sender: 'Status', content: 'Error: $error');
          _isConnected = false;
        });
      },
    );

    _sendMessageToSocket('NICK ${_nickController.text}');
    _sendMessageToSocket('USER ${_nickController.text} 0 * :I2P Bridge User');
  }

  void _handleMessage(String rawMessage) {
    // --- FEATURE: Filter MOTD ---
    // IRC code 366 indicates "End of /NAMES list."
    if (rawMessage.contains(' 366 ')) {
      setState(() {
        _hasFinishedJoin = true;
      });
    }

    if (rawMessage.contains('PRIVMSG')) {
      final parts = rawMessage.split('PRIVMSG');
      final sender = parts[0].split('!')[0].replaceFirst(':', '').trim();
      final content = parts[1].split(':').sublist(1).join(':').trim();
      _addMessage(sender: sender, content: content);
    } else if (rawMessage.contains('NOTICE')) {
       final parts = rawMessage.split('NOTICE');
       final content = parts[1].split(':').sublist(1).join(':').trim();
       _addMessage(sender: 'Notice', content: content, isNotice: true);
    } else if (rawMessage.contains('JOIN')) {
       final sender = rawMessage.split('!')[0].replaceFirst(':', '').trim();
       // --- BUG FIX: Track current channel ---
       final channel = rawMessage.split('JOIN :')[1].trim();
       setState(() {
         _currentChannel = channel;
       });
       _addMessage(sender: 'Status', content: '$sender has joined $channel.');
    } else if (rawMessage.contains('PART')) {
       final sender = rawMessage.split('!')[0].replaceFirst(':', '').trim();
       _addMessage(sender: 'Status', content: '$sender has left the channel.');
    }
  }
  
  void _addMessage({required String sender, required String content, bool isNotice = false}) {
      setState(() {
          _messages.add(ParsedMessage(sender: sender, content: content, isNotice: isNotice));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
  }

  void _disconnect() {
    _channel?.sink.close();
    setState(() {
      _isConnected = false;
    });
  }

  void _sendMessageToSocket(String message) {
    _channel?.sink.add(message);
  }

  // Renamed to handle both commands and messages
  void _handleUserInput() {
    if (_messageController.text.isEmpty) return;

    final text = _messageController.text;

    // --- FEATURE: Command Parsing ---
    if (text.startsWith('/')) {
      final parts = text.split(' ');
      final command = parts[0].toLowerCase();

      if (command == '/join' && parts.length > 1) {
        final channel = parts[1];
        _sendMessageToSocket('JOIN $channel');
        _addMessage(sender: 'Status', content: 'Attempting to join $channel...');
        setState(() {
          _hasFinishedJoin = false; // Reset for the new channel
          _messages.clear(); // Clear messages from old channel
        });
      } else {
        _addMessage(sender: 'Error', content: 'Unknown command: $command');
      }
    } else {
      // It's a regular chat message
      final message = 'PRIVMSG $_currentChannel :$text';
      _sendMessageToSocket(message);
      _addMessage(sender: _nickController.text, content: text);
    }
    _messageController.clear();
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: _isConnected ? _buildChatView() : _buildConnectionView(),
    );
  }

  Widget _buildConnectionView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.connect_without_contact, size: 80, color: Colors.grey),
        const SizedBox(height: 24),
        TextField(
          controller: _nickController,
          decoration: const InputDecoration(
            labelText: 'Nickname',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _channelController,
          decoration: const InputDecoration(
            labelText: 'Channel',
            border: OutlineInputBorder(),
            hintText: '#channel',
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _connect,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Connect', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                
                // Only show messages after the join process is complete
                if (!_hasFinishedJoin && msg.sender != 'Status') {
                  return const SizedBox.shrink(); // Render nothing
                }

                if (msg.isNotice || msg.sender == 'Status') {
                    return Text(
                        '--- ${msg.content} ---',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    );
                }
                return RichText(
                    text: TextSpan(
                        style: DefaultTextStyle.of(context).style,
                        children: <TextSpan>[
                            TextSpan(text: '${msg.sender}: ', style: const TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: msg.content),
                        ],
                    ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Send a message or /join #channel',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _handleUserInput(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _handleUserInput,
              style: IconButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: _disconnect,
          child: const Text('Disconnect'),
        )
      ],
    );
  }
}
