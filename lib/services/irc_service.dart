// lib/services/irc_service.dart
// This version fixes the bug where the initial channel buffer was not
// being correctly selected after connecting.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParsedMessage {
  final String sender;
  final String content;
  final bool isNotice;
  final DateTime timestamp;

  ParsedMessage({required this.sender, required this.content, this.isNotice = false})
      : timestamp = DateTime.now();
}

class IrcService with ChangeNotifier {
  WebSocketChannel? _channel;
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

  void connect(String initialChannel) {
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _lastChannel = initialChannel;
    _loadSettings().then((_) {
      final wsUrl = Uri.parse('ws://bridge.stormycloud.org:3000');
      _channel = WebSocketChannel.connect(wsUrl);

      _isConnected = true;
      _buffers.clear();
      _unreadBuffers.clear();
      _userLists.clear();
      _currentBuffer = 'Status';
      _buffers['Status'] = [ParsedMessage(sender: 'Status', content: 'Connecting...')];
      notifyListeners();

      bool registrationComplete = false;

      _channel!.stream.listen(
        (data) {
          final lines = data.toString().split('\r\n');
          for (final rawMessage in lines) {
            if (rawMessage.isEmpty) continue;

            if (!registrationComplete && rawMessage.contains(' 001 ')) {
              registrationComplete = true;
              _addMessage(to: 'Status', sender: 'Status', content: 'Connected! Authenticating...');
              if (_nickServPassword.isNotEmpty) {
                _sendMessageToSocket('PRIVMSG NickServ :IDENTIFY $_nickServPassword');
              }
              Future.delayed(const Duration(seconds: 2), () {
                _sendMessageToSocket('JOIN $initialChannel');
              });
            }
            
            _handleMessage(rawMessage);

            if (rawMessage.startsWith('PING')) {
              _sendMessageToSocket('PONG ${rawMessage.split(" ")[1]}');
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

      _sendMessageToSocket('NICK $_nickname');
      _sendMessageToSocket('USER $_nickname 0 * :I2P Bridge User');
    });
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _addMessage(to: 'Status', sender: 'Status', content: 'Attempting to reconnect in 5 seconds...');
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      connect(_lastChannel);
    });
  }

  void _handleMessage(String rawMessage) {
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

    if (rawMessage.contains('PRIVMSG')) {
      final parts = rawMessage.split('PRIVMSG');
      final sender = parts[0].split('!')[0].replaceFirst(':', '').trim();
      final targetAndContent = parts[1].trim();
      final target = targetAndContent.split(' ')[0];
      final content = targetAndContent.split(':').sublist(1).join(':').trim();
      final bufferName = target.startsWith('#') ? target : sender;
      _addMessage(to: bufferName, sender: sender, content: content);
    } else if (rawMessage.contains('JOIN')) {
      final sender = rawMessage.split('!')[0].replaceFirst(':', '').trim();
      final channel = rawMessage.split('JOIN :')[1].trim();
      if (!_hideJoinQuit) {
        _addMessage(to: channel, sender: 'Status', content: '$sender has joined $channel.');
      }
      if (!_userLists.containsKey(channel)) _userLists[channel] = [];
      _userLists[channel]!.add(sender);
      // --- FIX: Immediately switch to the new channel buffer ---
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
  
  void _addMessage({required String to, required String sender, required String content, bool isNotice = false}) {
    if (!_buffers.containsKey(to)) _buffers[to] = [];
    _buffers[to]!.add(ParsedMessage(sender: sender, content: content, isNotice: isNotice));
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
            _sendMessageToSocket('JOIN $channel');
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
            _sendMessageToSocket('PRIVMSG $target :$message');
            _addMessage(to: target, sender: _nickname, content: message);
          }
          break;
        default:
          _sendMessageToSocket(text.substring(1));
      }
    } else {
      _sendMessageToSocket('PRIVMSG $_currentBuffer :$text');
      _addMessage(to: _currentBuffer, sender: _nickname, content: text);
    }
    notifyListeners();
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
      _sendMessageToSocket('QUIT :Leaving');
      _channel?.sink.close();
    }
    _isConnected = false;
    notifyListeners();
  }

  void _sendMessageToSocket(String message) {
    _channel?.sink.add(message);
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
