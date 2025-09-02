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
import 'package:provider/provider.dart';
import 'auth_service.dart';
import 'debug_service.dart';

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
  AuthService? _authService;
  
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

  // SSL Pinning configuration - Updated to use certificate fingerprint
  static const String expectedCertFingerprint = 'AO5T/CbxDzIBFkUp6jLEcAk0+ZxeN06uaKyeIzIE+E0=';
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
  String _lastServer = 'irc2p';
  Timer? _reconnectTimer;
  Timer? _registrationTimer;
  bool _manualDisconnect = false;
  DateTime? _connectionTime;
  
  bool _hideJoinQuit = false;
  
  // MOTD loading state
  bool _isLoadingMOTD = false;
  List<String> _motdBuffer = [];
  bool get isLoadingMOTD => _isLoadingMOTD;
  
  // Track channels expecting NAMES response
  Set<String> _channelsAwaitingNames = {};

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

  // SECURITY IMPROVEMENT: Pin the certificate SHA-256 fingerprint
  String _getCertificateFingerprint(X509Certificate cert) {
    final certDer = cert.der;
    final fingerprint = sha256.convert(certDer);
    return base64.encode(fingerprint.bytes);
  }

  HttpClient _createPinnedHttpClient() {
    final httpClient = HttpClient();
    httpClient.userAgent = appUserAgent;
    
    httpClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (host != 'bridge.stormycloud.org') {
        return false; // Only pin our specific domain
      }
      
      try {
        // SECURITY FIX: Use certificate fingerprint instead of raw DER
        final certificateFingerprint = _getCertificateFingerprint(cert);
        
        // Compare with expected certificate fingerprint
        return certificateFingerprint == expectedCertFingerprint;
      } catch (e) {
        DebugService.instance.logIrc('Certificate validation error: $e');
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
      DebugService.instance.logIrc('Encryption error: $e');
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
      DebugService.instance.logIrc('Decryption error: $e');
      return '[Decryption Error]';
    }
  }

  void setAuthService(AuthService authService) {
    _authService = authService;
  }
  
  Future<void> connect(String initialChannel, {String server = 'irc2p'}) async {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _lastChannel = initialChannel; // Store the channel to join
    _lastServer = server; // Store the server for reconnection
    
    debugPrint('IRC: Starting connection process to server: $server');
    await _loadSettings();
    
    try {
      // Ensure we have authentication
      if (_authService == null) {
        debugPrint('IRC: AuthService is null!');
        _addMessage(to: 'Status', sender: 'Error', content: 'Authentication service not available');
        notifyListeners();
        return;
      }
      
      debugPrint('IRC: Ensuring authentication...');
      
      try {
        await _authService!.ensureAuthenticated();
      } catch (authError) {
        debugPrint('IRC: Authentication failed: $authError');
        String errorMessage = '❌ Authentication failed';
        
        if (authError.toString().contains('Invalid API key')) {
          errorMessage = '❌ Invalid API key. Please check your API key in settings.';
        } else if (authError.toString().contains('expired')) {
          errorMessage = '❌ Session expired. Please close and reopen the app.';
        } else if (authError.toString().contains('disabled')) {
          errorMessage = '❌ Your API key has been disabled. Please contact support.';
        } else if (authError.toString().contains('Rate limit')) {
          errorMessage = '❌ Too many attempts. Please try again later.';
        } else {
          errorMessage = '❌ ${authError.toString().replaceAll('Exception: ', '')}';
        }
        
        _addMessage(to: 'Status', sender: 'Error', content: errorMessage);
        _manualDisconnect = true; // Don't auto-reconnect for auth errors
        notifyListeners();
        return;
      }
      
      final token = _authService!.token;
      
      if (token == null) {
        debugPrint('IRC: Token is null after authentication!');
        _addMessage(to: 'Status', sender: 'Error', content: '❌ Authentication failed. Please check your API key in settings.');
        _manualDisconnect = true;
        notifyListeners();
        return;
      }
      
      debugPrint('IRC: Got JWT token, connecting to WebSocket...');
      debugPrint('IRC: Token length: ${token.length}');
      
      // Create pinned HTTP client for WebSocket
      final httpClient = _createPinnedHttpClient();
      // Include token and server in WebSocket URL as query parameters
      final wsUrl = Uri.parse('wss://bridge.stormycloud.org?token=$token&server=$server');
      debugPrint('IRC: WebSocket URL: ${wsUrl.toString().replaceAll(token, '[TOKEN]')}, Server: $server');
      _channel = IOWebSocketChannel.connect(wsUrl, customClient: httpClient);

      // Don't set _isConnected yet - wait for successful authentication
      _buffers.clear();
      _unreadBuffers.clear();
      _userLists.clear();
      _currentBuffer = 'Status';
      _encryptionReady = false;
      _isLoadingMOTD = true;
      _motdBuffer.clear();
      
      _buffers['Status'] = [ParsedMessage(
        sender: 'Status', 
        content: 'Establishing secure connection...',
      )];
      notifyListeners();
      
      // Set up WebSocket listeners
      bool registrationComplete = false;
      bool hasJoinedChannel = false;

      _channel!.stream.listen(
        (data) {
          debugPrint('IRC: Received WebSocket data: $data');
          try {
            final jsonData = json.decode(data);
            debugPrint('IRC: Parsed JSON type: ${jsonData['type']}');
            
            // Handle authentication errors
            if (jsonData['type'] == 'error') {
              debugPrint('IRC: Received error message from server');
              String errorMessage = jsonData['error'] ?? 'Authentication error';
              String action = jsonData['action'] ?? '';
              String code = jsonData['code'] ?? 'UNKNOWN_ERROR';
              
              // Format error message for display
              _addMessage(
                to: 'Status', 
                sender: 'Error', 
                content: '❌ $errorMessage'
              );
              
              if (action.isNotEmpty) {
                _addMessage(
                  to: 'Status', 
                  sender: 'Error', 
                  content: '💡 $action'
                );
              }
              
              // Handle specific error codes
              if (code == 'TOKEN_MISSING' || code == 'TOKEN_EXPIRED' || 
                  code == 'TOKEN_INVALID' || code == 'API_KEY_DISABLED') {
                _manualDisconnect = true; // Don't auto-reconnect for auth errors
              }
              
              return;
            }
            
            // Handle encryption initialization
            if (jsonData['type'] == 'encryption_init') {
              _sessionKey = base64.decode(jsonData['key']);
              _sessionIV = base64.decode(jsonData['iv']);
              _encryptionReady = true;
              _isConnected = true;  // NOW we're truly connected
              
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
              _addMessage(to: 'Status', sender: 'Status', content: 'Sending registration commands...');
              _sendEncryptedMessage('NICK $_nickname');
              _sendEncryptedMessage('USER $_nickname 0 * :I2P Bridge User');
              _addMessage(to: 'Status', sender: 'Status', content: 'Registration commands sent, waiting for server response...');
              
              // Start registration timeout
              _registrationTimer = Timer(const Duration(seconds: 30), () {
                _addMessage(to: 'Status', sender: 'Error', content: 'IRC server registration timeout - no response from server');
                disconnect();
              });
              
              return;
            }
            
            // Handle encrypted IRC messages
            if (jsonData['type'] == 'irc_message' && jsonData['encrypted'] == true) {
              final decrypted = _decryptMessage(jsonData['data']);
              final lines = decrypted.split('\r\n');
              
              // Debug: Log received messages during registration
              if (!registrationComplete) {
                _addMessage(to: 'Status', sender: 'Debug', content: 'Received IRC data: ${lines.where((l) => l.isNotEmpty).join(' | ')}');
              }
              
              for (final rawMessage in lines) {
                if (rawMessage.isEmpty) continue;
                
                if (!registrationComplete && (rawMessage.contains(' 001 ') || rawMessage.contains(' 376 ') || rawMessage.contains(' 422 '))) {
                  // 001 = Welcome, 376 = End of MOTD, 422 = No MOTD
                  registrationComplete = true;
                  _registrationTimer?.cancel();
                  _connectionTime = DateTime.now();
                  _addMessage(to: 'Status', sender: 'Status', content: 'Connected successfully!');
                  
                  // Handle NickServ authentication if configured
                  if (_nickServPassword.isNotEmpty) {
                    _sendEncryptedMessage('PRIVMSG NickServ :IDENTIFY $_nickServPassword');
                  }
                  
                  // Join the initial channel after required delay
                  if (!hasJoinedChannel && _lastChannel.isNotEmpty) {
                    hasJoinedChannel = true;
                    // IRC servers require at least 10 seconds before JOIN
                    _addMessage(to: 'Status', sender: 'Status', content: 'Waiting 11 seconds before joining $_lastChannel (IRC server requirement)...');
                    Future.delayed(const Duration(seconds: 11), () {
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
            DebugService.instance.logIrc('Message parsing error: $e');
          }
        },
        onDone: () {
          _isConnected = false;
          _encryptionReady = false;
          _registrationTimer?.cancel();
          _addMessage(to: 'Status', sender: 'Status', content: 'Disconnected.');
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
          notifyListeners();
        },
        onError: (error) {
          String errorMessage = 'Connection error';
          debugPrint('IRC: WebSocket error: $error');
          
          // Check for authentication errors (WebSocket close code 1008)
          if (error.toString().contains('1008') || error.toString().contains('Authentication')) {
            errorMessage = '❌ Authentication failed. Please check your API key in settings.';
            _manualDisconnect = true; // Don't auto-reconnect for auth errors
          } else if (error.toString().contains('503') || error.toString().contains('Service Unavailable')) {
            errorMessage = 'IRC service is temporarily disabled. Please try again later.';
            _manualDisconnect = true; // Don't auto-reconnect for service disabled
          } else if (error.toString().contains('WebSocketChannelException')) {
            // This might be an authentication failure
            errorMessage = '❌ Failed to connect. Please verify your API key is valid and try again.';
            _manualDisconnect = true; // Don't auto-reconnect
          } else {
            errorMessage = 'Error: $error';
          }
          
          _addMessage(to: 'Status', sender: 'Error', content: errorMessage);
          _isConnected = false;
          _encryptionReady = false;
          _registrationTimer?.cancel();
          
          if (!_manualDisconnect) {
            _scheduleReconnect();
          }
          notifyListeners();
        },
      );
    } catch (e) {
      debugPrint('IRC: Connection error: $e');
      _isConnected = false;
      
      String errorMessage;
      if (e.toString().contains('401') || e.toString().contains('403') || 
          e.toString().contains('Authentication') || e.toString().contains('Invalid token')) {
        errorMessage = '❌ Authentication failed. Please check your API key in settings.';
        _manualDisconnect = true; // Don't auto-reconnect for auth errors
      } else if (e.toString().contains('WebSocketChannelException')) {
        errorMessage = '❌ Failed to connect. This may be an authentication issue - please verify your API key.';
        _manualDisconnect = true;
      } else {
        errorMessage = 'Failed to connect: $e';
      }
      
      _addMessage(to: 'Status', sender: 'Error', content: errorMessage);
      notifyListeners();
      return;
    }
  }

  void _sendEncryptedMessage(String message) {
    if (!_encryptionReady) {
      DebugService.instance.logIrc('Encryption not ready, dropping message: $message');
      return;
    }
    
    DebugService.instance.logIrc('Sending: $message');
    
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
      connect(_lastChannel, server: _lastServer);
    });
  }

  void _handleMessage(String rawMessage) {
    // Handle JOIN error responses
    if (RegExp(r':\S+ 4\d{2} ').hasMatch(rawMessage)) {
      final match = RegExp(r':\S+ (\d{3}) \S+ (#?\S+)? :?(.*)').firstMatch(rawMessage);
      if (match != null) {
        final errorCode = match.group(1)!;
        final channel = match.group(2) ?? '';
        final content = match.group(3) ?? rawMessage;
        
        // Handle specific JOIN-related errors
        if (errorCode == '471' || errorCode == '473' || errorCode == '474' || errorCode == '475' || errorCode == '476') {
          _addMessage(to: 'Status', sender: 'Error', content: 'Failed to join $channel: $content');
        } else {
          _addMessage(to: 'Status', sender: 'Server', content: content.trim());
        }
      }
      return;
    }
    
    // Server numeric messages should go to Status
    if (RegExp(r':\S+ \d{3} ').hasMatch(rawMessage)) {
      final numericMatch = RegExp(r':\S+ (\d{3}) \S+ :?(.*)').firstMatch(rawMessage);
      if (numericMatch != null) {
        final code = numericMatch.group(1)!;
        final content = numericMatch.group(2) ?? '';
        
        // Handle MOTD messages specially
        if (_isLoadingMOTD) {
          if (code == '375') {
            // Start of MOTD
            _motdBuffer.clear();
            _addMessage(to: 'Status', sender: 'Status', content: '📋 Loading server information...');
            return;
          } else if (code == '372') {
            // MOTD line
            _motdBuffer.add(content.trim());
            return;
          } else if (code == '376' || code == '422') {
            // End of MOTD or No MOTD
            _isLoadingMOTD = false;
            if (_motdBuffer.isNotEmpty) {
              _addMessage(to: 'Status', sender: 'Server', content: '══════ Server Information ══════');
              for (final line in _motdBuffer) {
                if (line.trim().isNotEmpty) {
                  _addMessage(to: 'Status', sender: 'Server', content: line);
                }
              }
              _addMessage(to: 'Status', sender: 'Server', content: '═══════════════════════════════');
            }
            _motdBuffer.clear();
            notifyListeners();
            return;
          }
        }
        
        // Other numeric messages
        if (content.trim().isNotEmpty) {
          _addMessage(to: 'Status', sender: 'Server', content: content.trim());
        }
      }
      return;
    }

    // Handle user lists (NAMES response)
    if (rawMessage.contains(' 353 ')) {
      // Format: :server 353 nick = #channel :user1 user2 user3
      final match = RegExp(r':\S+ 353 \S+ [=*@] (#\S+) :(.+)').firstMatch(rawMessage);
      if (match != null) {
        final channel = match.group(1)!;
        final userListString = match.group(2)!;
        final users = userListString.split(' ');

        // If this channel is awaiting NAMES, clear the list first
        if (_channelsAwaitingNames.contains(channel)) {
          _userLists[channel] = [];
          _channelsAwaitingNames.remove(channel);
        }
        
        // Initialize list if needed
        if (!_userLists.containsKey(channel)) {
          _userLists[channel] = [];
        }
        
        // Add users to the list (multiple 353 responses may be sent for large channels)
        for (var user in users) {
          if (user.isNotEmpty && !_userLists[channel]!.contains(user)) {
            _userLists[channel]!.add(user);
          }
        }
      }
    }
    
    // Handle end of NAMES list
    if (rawMessage.contains(' 366 ')) {
      // Format: :server 366 nick #channel :End of /NAMES list
      final match = RegExp(r':\S+ 366 \S+ (#\S+) :').firstMatch(rawMessage);
      if (match != null) {
        final channel = match.group(1)!;
        // NAMES list is complete, sort the users
        if (_userLists.containsKey(channel)) {
          _userLists[channel]!.sort((a, b) {
            // Remove prefixes for sorting
            final cleanA = a.replaceAll(RegExp(r'^[@+~&%]'), '');
            final cleanB = b.replaceAll(RegExp(r'^[@+~&%]'), '');
            return cleanA.toLowerCase().compareTo(cleanB.toLowerCase());
          });
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
          
          // Add user if not already in list
          if (!_userLists[channel]!.contains(sender)) {
            _userLists[channel]!.add(sender);
          }
          
          if (sender == _nickname) {
            setCurrentBuffer(channel);
            // Clear user list and request fresh NAMES when we join a channel
            _userLists[channel] = [];
            _channelsAwaitingNames.add(channel);
            _sendEncryptedMessage('NAMES $channel');
          }
        }
      }
    }
    // Handle PART/QUIT/KICK
    else if (rawMessage.contains('PART') || rawMessage.contains('QUIT') || rawMessage.contains('KICK')) {
      final sender = rawMessage.split('!')[0].replaceFirst(':', '').trim();
      
      if (rawMessage.contains('PART')) {
        // PART only affects specific channel
        final channelMatch = RegExp(r'PART (#\S+)').firstMatch(rawMessage);
        if (channelMatch != null) {
          final channel = channelMatch.group(1)!;
          _userLists[channel]?.removeWhere((user) => user.replaceAll(RegExp(r'[@+~&%]'), '') == sender);
          if (!_hideJoinQuit) {
            _addMessage(to: channel, sender: 'Status', content: '$sender has left $channel.');
          }
        }
      } else if (rawMessage.contains('KICK')) {
        // KICK affects specific channel and user
        final kickMatch = RegExp(r'KICK (#\S+) (\S+)').firstMatch(rawMessage);
        if (kickMatch != null) {
          final channel = kickMatch.group(1)!;
          final kickedUser = kickMatch.group(2)!;
          _userLists[channel]?.removeWhere((user) => user.replaceAll(RegExp(r'[@+~&%]'), '') == kickedUser);
          if (!_hideJoinQuit) {
            _addMessage(to: channel, sender: 'Status', content: '$kickedUser was kicked from $channel by $sender.');
          }
        }
      } else {
        // QUIT affects all channels
        _userLists.forEach((channel, users) {
          users.removeWhere((user) => user.replaceAll(RegExp(r'[@+~&%]'), '') == sender);
        });
        if (!_hideJoinQuit) {
          // Add quit message to current buffer only
          _addMessage(to: _currentBuffer, sender: 'Status', content: '$sender has quit.');
        }
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
            
            // Check if enough time has passed since connection
            if (_connectionTime != null) {
              final secondsSinceConnection = DateTime.now().difference(_connectionTime!).inSeconds;
              if (secondsSinceConnection < 10) {
                final waitTime = 10 - secondsSinceConnection;
                _addMessage(to: 'Status', sender: 'Status', content: 'Must wait $waitTime more seconds before joining channels.');
                break;
              }
            }
            
            // Create buffer but don't switch to it until successful JOIN
            if (!_buffers.containsKey(channel)) {
              _buffers[channel] = [];
            }
            _addMessage(to: 'Status', sender: 'Status', content: 'Attempting to join $channel...');
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

  void clearBuffers() {
    _buffers.clear();
    _buffers['Status'] = [];
    notifyListeners();
  }
  
  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _registrationTimer?.cancel();
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