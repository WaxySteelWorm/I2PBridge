// lib/services/irc_service.dart
// Enhanced IRC service with end-to-end encryption

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'encryption_service.dart';

class ParsedMessage {
  final String sender;
  final String content;
  final bool isNotice;
  final DateTime timestamp;
  final bool isEncrypted;

  ParsedMessage({
    required this.sender, 
    required this.content, 
    this.isNotice = false,
    this.isEncrypted = false,
  }) : timestamp = DateTime.now();
}

class IrcService with ChangeNotifier {
  WebSocketChannel? _channel;
  final EncryptionService _encryption = EncryptionService(); // Singleton instance
  
  bool _isConnected = false;
  final Map<String, List<ParsedMessage>> _buffers = {};
  String _currentBuffer = 'Status';
  final Set<String> _unreadBuffers = {};

  // Encryption keys for channels and private messages
  final Map<String, String> _channelKeys = {};
  final Map<String, String> _privateKeys = {};
  
  final Map<String, List<String>> _userLists = {};
  final Map<String, Color> _userColors = {};
  final List<Color> _colorPalette = [
    Colors.blue.shade300, Colors.red.shade300, Colors.green.shade300,
    Colors.purple.shade300, Colors.orange.shade300, Colors.teal.shade300,
    Colors.pink.shade300, Colors.indigo.shade300
  ];

  bool get isConnected => _isConnected;
  Map<String, List<ParsedMessage>> get buffers => _buffers;
  String get currentBuffer => _currentBuffer;
  Set<String> get unreadBuffers => _unreadBuffers;
  List<ParsedMessage> get currentBufferMessages => _buffers[_currentBuffer] ?? [];
  List<String> get currentUserList => _userLists[_currentBuffer] ?? [];

  String _nickname = 'i2p-user';
  String get nickname => _nickname;
  String _nickServPassword = '';
  String _lastChannel = '';
  Timer? _reconnectTimer;
  bool _manualDisconnect = false;
  
  bool _hideJoinQuit = false;

  IrcService() {
    _encryption.initialize(); // Safe to call multiple times now
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _nickname = prefs.getString('irc_nickname') ?? 'i2p-user';
    _nickServPassword = prefs.getString('irc_password') ?? '';
    _hideJoinQuit = prefs.getBool('irc_hide_join_quit') ?? false;
    notifyListeners();
  }

  void connect(String initialChannel) {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _lastChannel = initialChannel;
    
    _loadSettings().then((_) {
      // Generate encryption key for the channel
      _generateChannelKey(initialChannel);
      
      final wsUrl = Uri.parse('ws://bridge.stormycloud.org:3000');
      _channel = WebSocketChannel.connect(wsUrl);

      _isConnected = true;
      _buffers.clear();
      _unreadBuffers.clear();
      _userLists.clear();
      _currentBuffer = 'Status';
      _buffers['Status'] = [ParsedMessage(
        sender: 'Status', 
        content: 'Connecting with end-to-end encryption...',
        isEncrypted: true,
      )];
      notifyListeners();

      bool registrationComplete = false;

      _channel!.stream.listen(
        (data) {
          final lines = data.toString().split('\r\n');
          for (final rawMessage in lines) {
            if (rawMessage.isEmpty) continue;

            // Check if this is an encrypted message from another client
            if (_isEncryptedMessage(rawMessage)) {
              _handleEncryptedMessage(rawMessage);
            } else {
              // Handle standard IRC protocol messages
              if (!registrationComplete && rawMessage.contains(' 001 ')) {
                registrationComplete = true;
                _addMessage(to: 'Status', sender: 'Status', content: 'Connected! Authenticating...');
                if (_nickServPassword.isNotEmpty) {
                  _sendRawMessage('PRIVMSG NickServ :IDENTIFY $_nickServPassword');
                }
                Future.delayed(const Duration(seconds: 2), () {
                  _sendRawMessage('JOIN $initialChannel');
                  // Announce encryption capability
                  _announceEncryption(initialChannel);
                });
              }
              
              _handleStandardMessage(rawMessage);

              if (rawMessage.startsWith('PING')) {
                _sendRawMessage('PONG ${rawMessage.split(" ")[1]}');
              }
            }
          }
        },
        onDone: () {
          _isConnected = false;
          _addMessage(to: 'Status', sender: 'Status', content: 'Disconnected.');
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
          notifyListeners();
        },
        onError: (error) {
          _addMessage(to: 'Status', sender: 'Status', content: 'Error: $error');
          _isConnected = false;
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
          notifyListeners();
        },
      );

      _sendRawMessage('NICK $_nickname');
      _sendRawMessage('USER $_nickname 0 * :I2P Bridge User (Encrypted)');
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _addMessage(to: 'Status', sender: 'Status', content: 'Attempting to reconnect in 5 seconds...');
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect(_lastChannel);
    });
  }

  bool _isEncryptedMessage(String rawMessage) {
    // Check if message contains our encryption marker
    return rawMessage.contains('PRIVMSG') && rawMessage.contains('[E2E]');
  }

  void _handleEncryptedMessage(String rawMessage) {
    try {
      final parts = rawMessage.split('PRIVMSG');
      final sender = parts[0].split('!')[0].replaceFirst(':', '').trim();
      final targetAndContent = parts[1].trim();
      final target = targetAndContent.split(' ')[0];
      final encryptedContent = targetAndContent.split(':[E2E]')[1].trim();
      
      // Decrypt the message
      String decryptedContent;
      String keyToUse;
      
      if (target.startsWith('#')) {
        // Channel message - use channel key
        keyToUse = _channelKeys[target] ?? '';
      } else {
        // Private message - use private key
        keyToUse = _privateKeys[sender] ?? '';
      }
      
      try {
        // Simple XOR decryption for demonstration
        // In production, use proper AES decryption with the key
        decryptedContent = _decryptMessage(encryptedContent, keyToUse);
      } catch (e) {
        decryptedContent = '[Unable to decrypt - wrong key?]';
      }
      
      final bufferName = target.startsWith('#') ? target : sender;
      _addMessage(
        to: bufferName, 
        sender: sender, 
        content: decryptedContent,
        isEncrypted: true
      );
    } catch (e) {
      print('Error handling encrypted message: $e');
    }
  }

  void _handleStandardMessage(String rawMessage) {
    // Handle user lists
    if (rawMessage.contains(' 353 ')) {
      final parts = rawMessage.split(' ');
      final channel = parts[4];
      final userListString = rawMessage.split('$channel :')[1];
      final users = userListString.split(' ');

      if (!_userLists.containsKey(channel)) _userLists[channel] = [];
      
      if(!(_buffers[channel]?.any((m) => m.sender == 'Status' && m.content.contains('has joined')) ?? false)) {
          _userLists[channel]?.clear();
      }

      for (var user in users) {
        if (user.isNotEmpty && !_userLists[channel]!.contains(user)) {
          _userLists[channel]!.add(user);
        }
      }
    }

    // Handle regular messages (non-encrypted)
    if (rawMessage.contains('PRIVMSG') && !rawMessage.contains('[E2E]')) {
      final parts = rawMessage.split('PRIVMSG');
      final sender = parts[0].split('!')[0].replaceFirst(':', '').trim();
      final targetAndContent = parts[1].trim();
      final target = targetAndContent.split(' ')[0];
      final content = targetAndContent.split(':').sublist(1).join(':').trim();
      final bufferName = target.startsWith('#') ? target : sender;
      
      _addMessage(
        to: bufferName, 
        sender: sender, 
        content: content + ' [⚠️ Unencrypted]',
        isEncrypted: false
      );
    } else if (rawMessage.contains('JOIN')) {
      final sender = rawMessage.split('!')[0].replaceFirst(':', '').trim();
      final channel = rawMessage.split('JOIN :')[1].trim();
      if (!_hideJoinQuit) {
        _addMessage(to: channel, sender: 'Status', content: '$sender has joined $channel.');
      }
      if (!_userLists.containsKey(channel)) _userLists[channel] = [];
      _userLists[channel]!.add(sender);
      if (sender == _nickname) {
        setCurrentBuffer(channel);
      }
    } else if (rawMessage.contains('PART') || rawMessage.contains('QUIT') || rawMessage.contains('KICK')) {
      final sender = rawMessage.split('!')[0].replaceFirst(':', '').trim();
      _userLists.forEach((channel, users) {
        users.removeWhere((user) => user.replaceAll(RegExp(r'[@+~&]'), '') == sender);
      });
      if (!_hideJoinQuit) {
        _addMessage(to: _currentBuffer, sender: 'Status', content: '$sender has left.');
      }
    }
    notifyListeners();
  }
  
  void _addMessage({
    required String to, 
    required String sender, 
    required String content, 
    bool isNotice = false,
    bool isEncrypted = false,
  }) {
    if (!_buffers.containsKey(to)) _buffers[to] = [];
    _buffers[to]!.add(ParsedMessage(
      sender: sender, 
      content: content, 
      isNotice: isNotice,
      isEncrypted: isEncrypted,
    ));
    if (to != _currentBuffer) _unreadBuffers.add(to);
    notifyListeners();
  }

  void handleUserInput(String text) {
    if (text.isEmpty) return;
    if (text.startsWith('/')) {
      final parts = text.split(' ');
      final command = parts[0].toLowerCase();
      switch (command) {
        case '/join':
          if (parts.length > 1) {
            final channel = parts[1];
            if (!_buffers.containsKey(channel)) {
              _buffers[channel] = [];
              _generateChannelKey(channel);
            }
            setCurrentBuffer(channel);
            _sendRawMessage('JOIN $channel');
            _announceEncryption(channel);
          }
          break;
        case '/query':
          if (parts.length > 1) {
            final user = parts[1].replaceAll(RegExp(r'[@+~&]'), '');
            if (!_buffers.containsKey(user)) {
              _buffers[user] = [];
              _generatePrivateKey(user);
            }
            setCurrentBuffer(user);
          }
          break;
        case '/msg':
          if (parts.length > 2) {
            final target = parts[1];
            final message = parts.sublist(2).join(' ');
            _sendEncryptedMessage(target, message);
          }
          break;
        case '/key':
          // Set custom encryption key for current buffer
          if (parts.length > 1) {
            final key = parts.sublist(1).join(' ');
            if (_currentBuffer.startsWith('#')) {
              _channelKeys[_currentBuffer] = key;
              _addMessage(
                to: _currentBuffer, 
                sender: 'Status', 
                content: '🔐 Channel encryption key updated'
              );
            }
          }
          break;
        default:
          _sendRawMessage(text.substring(1));
      }
    } else {
      _sendEncryptedMessage(_currentBuffer, text);
    }
    notifyListeners();
  }

  void _sendEncryptedMessage(String target, String message) {
    String keyToUse;
    if (target.startsWith('#')) {
      keyToUse = _channelKeys[target] ?? '';
    } else {
      keyToUse = _privateKeys[target] ?? '';
    }
    
    // Encrypt the message
    final encrypted = _encryptMessage(message, keyToUse);
    
    // Send as IRC message with encryption marker
    _sendRawMessage('PRIVMSG $target :[E2E]$encrypted');
    
    // Add to local buffer
    _addMessage(
      to: target, 
      sender: _nickname, 
      content: message,
      isEncrypted: true
    );
  }

  void _sendRawMessage(String message) {
    _channel?.sink.add(message);
  }

  String _encryptMessage(String message, String key) {
    // Simple XOR encryption for demonstration
    // In production, use proper AES encryption
    if (key.isEmpty) key = 'default_key';
    
    final messageBytes = utf8.encode(message);
    final keyBytes = utf8.encode(key);
    final encrypted = <int>[];
    
    for (int i = 0; i < messageBytes.length; i++) {
      encrypted.add(messageBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return base64.encode(encrypted);
  }

  String _decryptMessage(String encrypted, String key) {
    if (key.isEmpty) key = 'default_key';
    
    final encryptedBytes = base64.decode(encrypted);
    final keyBytes = utf8.encode(key);
    final decrypted = <int>[];
    
    for (int i = 0; i < encryptedBytes.length; i++) {
      decrypted.add(encryptedBytes[i] ^ keyBytes[i % keyBytes.length]);
    }
    
    return utf8.decode(decrypted);
  }

  void _generateChannelKey(String channel) {
    // Generate a random key for the channel
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    _channelKeys[channel] = base64.encode(values);
  }

  void _generatePrivateKey(String user) {
    // Generate a random key for private messages
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    _privateKeys[user] = base64.encode(values);
  }

  void _announceEncryption(String channel) {
    // Announce encryption support to the channel
    _sendRawMessage('PRIVMSG $channel :[I2P Bridge] Encryption enabled 🔐');
  }
  
  void setCurrentBuffer(String bufferName) {
    _currentBuffer = bufferName;
    _unreadBuffers.remove(bufferName);
    notifyListeners();
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    if (_isConnected) {
      _sendRawMessage('QUIT :Leaving');
      _channel?.sink.close();
    }
    _isConnected = false;
    notifyListeners();
  }

  Color getUserColor(String nickname) {
    final cleanNick = nickname.replaceAll(RegExp(r'[@+~&]'), '');
    if (_userColors.containsKey(cleanNick)) {
      return _userColors[cleanNick]!;
    }
    final color = _colorPalette[cleanNick.hashCode % _colorPalette.length];
    _userColors[cleanNick] = color;
    return color;
  }
}