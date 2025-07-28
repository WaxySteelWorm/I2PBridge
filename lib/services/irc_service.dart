import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

class ParsedMessage {
  final String sender;
  final String content;
  final bool isNotice;
  final DateTime timestamp;
  final bool isPrivate;

  ParsedMessage({
    required this.sender, 
    required this.content, 
    this.isNotice = false,
    this.isPrivate = false,
  }) : timestamp = DateTime.now();
}

class IrcService with ChangeNotifier {
  WebSocketChannel? _channel;
  
  // Encryption components
  Uint8List? _sessionKey;
  Uint8List? _sessionIV;
  bool _encryptionReady = false;
  
  bool _isConnected = false;
  final Map<String, List<ParsedMessage>> _buffers = {};
  String _currentBuffer = 'Status';
  final Set<String> _unreadBuffers = {};
  
  final Map<String, List<String>> _userLists = {};
  final Map<String, Color> _userColors = {};
  final List<Color> _colorPalette = [
    Colors.blue.shade300, Colors.red.shade300, Colors.green.shade300,
    Colors.purple.shade300, Colors.orange.shade300, Colors.teal.shade300,
    Colors.pink.shade300, Colors.indigo.shade300
  ];

  // SSL Pinning configuration
  static const String expectedPublicKeyHash = 'QaZ6GsvfR7eEgr/edwGzWpZlPJiFxBuvrNIba7bc8dE=';
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';

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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _nickname = prefs.getString('irc_nickname') ?? 'i2p-user';
    _nickServPassword = prefs.getString('irc_password') ?? '';
    _hideJoinQuit = prefs.getBool('irc_hide_join_quit') ?? false;
    notifyListeners();
  }

  HttpClient _createPinnedHttpClient() {
    final httpClient = HttpClient();
    httpClient.userAgent = appUserAgent;
    
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (host != 'bridge.stormycloud.org') {
        return false; // Only pin our specific domain
      }
      
      try {
        // Get the public key from the certificate
        final publicKeyBytes = cert.der;
        final publicKeyHash = sha256.convert(publicKeyBytes);
        final publicKeyHashBase64 = base64.encode(publicKeyHash.bytes);
        
        // Compare with expected hash
        return publicKeyHashBase64 == expectedPublicKeyHash;
      } catch (e) {
        print('Certificate validation error: $e');
        return false;
      }
    };
    
    return httpClient;
  }

  // Encryption methods
  String _encryptMessage(String message) {
    if (!_encryptionReady || _sessionKey == null || _sessionIV == null) {
      return message;
    }
    
    try {
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(_sessionKey!), _sessionIV!),
        null
      );
      cipher.init(true, params);
      
      final plaintext = utf8.encode(message);
      final encrypted = cipher.process(Uint8List.fromList(plaintext));
      
      return base64.encode(encrypted);
    } catch (e) {
      print('Encryption error: $e');
      return message;
    }
  }

  String _decryptMessage(String encryptedData) {
    if (!_encryptionReady || _sessionKey == null || _sessionIV == null) {
      return encryptedData;
    }
    
    try {
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(_sessionKey!), _sessionIV!),
        null
      );
      cipher.init(false, params);
      
      final encrypted = base64.decode(encryptedData);
      final decrypted = cipher.process(encrypted);
      
      return utf8.decode(decrypted);
    } catch (e) {
      print('Decryption error: $e');
      return '[Decryption Error]';
    }
  }

  void connect(String initialChannel) {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _lastChannel = initialChannel; // Store the channel to join
    
    _loadSettings().then((_) {
      // Create pinned HTTP client for WebSocket
      final httpClient = _createPinnedHttpClient();
      final wsUrl = Uri.parse('wss://bridge.stormycloud.org');
      _channel = IOWebSocketChannel.connect(wsUrl, customClient: httpClient);

      _isConnected = true;
      _buffers.clear();
      _unreadBuffers.clear();
      _userLists.clear();
      _currentBuffer = 'Status';
      _encryptionReady = false;
      
      _buffers['Status'] = [ParsedMessage(
        sender: 'Status', 
        content: 'Establishing secure connection...',
      )];
      notifyListeners();

      bool registrationComplete = false;
      bool hasJoinedChannel = false;

      _channel!.stream.listen(
        (data) {
          try {
            final jsonData = json.decode(data);
            
            // Handle encryption initialization
            if (jsonData['type'] == 'encryption_init') {
              _sessionKey = base64.decode(jsonData['key']);
              _sessionIV = base64.decode(jsonData['iv']);
              _encryptionReady = true;
              
              // Send acknowledgment
              _channel!.sink.add(json.encode({
                'type': 'encryption_ack'
              }));
              
              _addMessage(
                to: 'Status', 
                sender: 'Status', 
                content: '🔒 Encrypted connection established'
              );
              
              // Now send IRC registration
              _sendEncryptedMessage('NICK $_nickname');
              _sendEncryptedMessage('USER $_nickname 0 * :I2P Bridge User');
              return;
            }
            
            // Handle encrypted IRC messages
            if (jsonData['type'] == 'irc_message' && jsonData['encrypted'] == true) {
              final decrypted = _decryptMessage(jsonData['data']);
              final lines = decrypted.split('\r\n');
              
              for (final rawMessage in lines) {
                if (rawMessage.isEmpty) continue;
                
                if (!registrationComplete && (rawMessage.contains(' 001 ') || rawMessage.contains(' 376 ') || rawMessage.contains(' 422 '))) {
                  // 001 = Welcome, 376 = End of MOTD, 422 = No MOTD
                  registrationComplete = true;
                  _addMessage(to: 'Status', sender: 'Status', content: 'Connected successfully!');
                  
                  // Handle NickServ authentication if configured
                  if (_nickServPassword.isNotEmpty) {
                    _sendEncryptedMessage('PRIVMSG NickServ :IDENTIFY $_nickServPassword');
                  }
                  
                  // Join the initial channel after a short delay
                  if (!hasJoinedChannel && _lastChannel.isNotEmpty) {
                    hasJoinedChannel = true;
                    // Shorter delay for better UX
                    Future.delayed(const Duration(milliseconds: 500), () {
                      _addMessage(to: 'Status', sender: 'Status', content: 'Joining $_lastChannel...');
                      _sendEncryptedMessage('JOIN $_lastChannel');
                    });
                  }
                }
                
                _handleMessage(rawMessage);
                
                if (rawMessage.startsWith('PING')) {
                  _sendEncryptedMessage('PONG ${rawMessage.split(" ")[1]}');
                }
              }
            }
          } catch (e) {
            // Fallback for non-JSON messages (shouldn't happen)
            print('Message parsing error: $e');
          }
        },
        onDone: () {
          _isConnected = false;
          _encryptionReady = false;
          _addMessage(to: 'Status', sender: 'Status', content: 'Disconnected.');
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
          notifyListeners();
        },
        onError: (error) {
          _addMessage(to: 'Status', sender: 'Status', content: 'Error: $error');
          _isConnected = false;
          _encryptionReady = false;
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
          notifyListeners();
        },
      );
    });
  }

  void _sendEncryptedMessage(String message) {
    if (!_encryptionReady) {
      print('Encryption not ready, dropping message: $message');
      return;
    }
    
    final encrypted = _encryptMessage(message);
    _channel?.sink.add(json.encode({
      'encrypted': true,
      'data': encrypted
    }));
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _addMessage(to: 'Status', sender: 'Status', content: 'Attempting to reconnect in 5 seconds...');
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect(_lastChannel);
    });
  }

  void _handleMessage(String rawMessage) {
    // Server numeric messages should go to Status
    if (RegExp(r':\S+ \d{3} ').hasMatch(rawMessage)) {
      final match = RegExp(r':\S+ \d{3} \S+ :?(.*)').firstMatch(rawMessage);
      if (match != null) {
        final content = match.group(1) ?? rawMessage;
        if (content.trim().isNotEmpty) {
          _addMessage(to: 'Status', sender: 'Server', content: content.trim());
        }
      }
      return;
    }

    // Handle user lists
    if (rawMessage.contains(' 353 ')) {
      final parts = rawMessage.split(' ');
      if (parts.length > 4) {
        final channel = parts[4];
        final userListString = rawMessage.split('$channel :')[1];
        final users = userListString.split(' ');

        if (!_userLists.containsKey(channel)) _userLists[channel] = [];
        _userLists[channel]?.clear();

        for (var user in users) {
          if (user.isNotEmpty) {
            _userLists[channel]!.add(user);
          }
        }
      }
    }

    // Handle PRIVMSG
    if (rawMessage.contains('PRIVMSG')) {
      final parts = rawMessage.split('PRIVMSG');
      final sender = parts[0].split('!')[0].replaceFirst(':', '').trim();
      final targetAndContent = parts[1].trim();
      final target = targetAndContent.split(' ')[0];
      final content = targetAndContent.split(':').sublist(1).join(':').trim();
      
      final bufferName = target.startsWith('#') ? target : sender;
      
      _addMessage(
        to: bufferName, 
        sender: sender, 
        content: content,
        isPrivate: !target.startsWith('#')
      );
    } 
    // Handle JOIN
    else if (rawMessage.contains('JOIN')) {
      final parts = rawMessage.split('!');
      if (parts.isNotEmpty) {
        final sender = parts[0].replaceFirst(':', '').trim();
        final channelMatch = RegExp(r'JOIN :?(.+)').firstMatch(rawMessage);
        if (channelMatch != null) {
          final channel = channelMatch.group(1)?.trim() ?? '';
          if (!_hideJoinQuit && channel.isNotEmpty) {
            _addMessage(to: channel, sender: 'Status', content: '$sender has joined $channel.');
          }
          if (!_userLists.containsKey(channel)) _userLists[channel] = [];
          _userLists[channel]!.add(sender);
          if (sender == _nickname) {
            setCurrentBuffer(channel);
          }
        }
      }
    }
    // Handle PART/QUIT/KICK
    else if (rawMessage.contains('PART') || rawMessage.contains('QUIT') || rawMessage.contains('KICK')) {
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
    bool isPrivate = false,
  }) {
    if (!_buffers.containsKey(to)) _buffers[to] = [];
    _buffers[to]!.add(ParsedMessage(
      sender: sender, 
      content: content, 
      isNotice: isNotice,
      isPrivate: isPrivate,
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
            }
            setCurrentBuffer(channel);
            _sendEncryptedMessage('JOIN $channel');
          }
          break;
        case '/query':
          if (parts.length > 1) {
            final user = parts[1].replaceAll(RegExp(r'[@+~&]'), '');
            if (!_buffers.containsKey(user)) _buffers[user] = [];
            setCurrentBuffer(user);
          }
          break;
        case '/msg':
          if (parts.length > 2) {
            final target = parts[1];
            final message = parts.sublist(2).join(' ');
            _sendMessage(target, message);
          }
          break;
        case '/me':
          if (parts.length > 1) {
            final action = parts.sublist(1).join(' ');
            _sendEncryptedMessage('PRIVMSG $_currentBuffer :\x01ACTION $action\x01');
            _addMessage(to: _currentBuffer, sender: '* $_nickname', content: action);
          }
          break;
        default:
          // Send raw IRC command
          _sendEncryptedMessage(text.substring(1));
      }
    } else {
      _sendMessage(_currentBuffer, text);
    }
    notifyListeners();
  }

  void _sendMessage(String target, String message) {
    _sendEncryptedMessage('PRIVMSG $target :$message');
    _addMessage(
      to: target, 
      sender: _nickname, 
      content: message,
      isPrivate: !target.startsWith('#')
    );
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
      _sendEncryptedMessage('QUIT :Leaving');
      _channel?.sink.close();
    }
    _isConnected = false;
    _encryptionReady = false;
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