// lib/services/pop3_mail_service.dart
// POP3/SMTP client for I2P mail with debugging

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';

class EmailMessage {
  final String id;
  final String from;
  final String subject;
  final String date;
  String body; // Made mutable for preloading
  final int size;
  bool isRead;
  bool isPreloaded;

  EmailMessage({
    required this.id,
    required this.from,
    required this.subject,
    required this.date,
    required this.body,
    required this.size,
    this.isRead = false,
    this.isPreloaded = false,
  });
}

class Pop3MailService with ChangeNotifier {
  Socket? _pop3Socket;
  Socket? _smtpSocket;
  
  // Encryption components (similar to IRC)
  Uint8List? _sessionKey;
  Uint8List? _sessionIV;
  bool _encryptionReady = false;
  
  bool _isConnected = false;
  bool _isLoading = false;
  String? _username;
  String? _password;
  
  List<EmailMessage> _messages = [];
  int _totalMessages = 0;
  String _statusMessage = '';
  String _lastError = '';
  
  // Debug mode
  bool debugMode = true;
  List<String> debugLog = [];
  
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get username => _username;
  List<EmailMessage> get messages => _messages;
  int get totalMessages => _totalMessages;
  String get statusMessage => _statusMessage;
  String get lastError => _lastError;

  // POP3 commands state
  final StreamController<String> _responseController = StreamController<String>.broadcast();
  String _commandBuffer = '';
  
  // Buffer for collecting responses
  List<String> _responseBuffer = [];
  bool _isCollectingResponse = false;

  Pop3MailService() {
    _initializeEncryption();
  }

  void _initializeEncryption() {
    // Generate session keys
    final secureRandom = _getSecureRandom();
    _sessionKey = secureRandom.nextBytes(32);
    _sessionIV = secureRandom.nextBytes(16);
    _encryptionReady = true;
  }

  SecureRandom _getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => DateTime.now().millisecondsSinceEpoch % 256)
        )
      ));
    return secureRandom;
  }

  void _debug(String message) {
    if (debugMode) {
      final timestamp = DateTime.now().toString().substring(11, 19);
      final logMessage = '[$timestamp] $message';
      print('[POP3] $logMessage');
      debugLog.add(logMessage);
      if (debugLog.length > 200) {
        debugLog.removeAt(0);
      }
      notifyListeners();
    }
  }

  void _updateStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  // Connect to POP3 server
  Future<bool> connect(String username, String password) async {
    try {
      _debug('=== Starting POP3 Connection ===');
      _debug('Username: $username');
      _debug('Password: ${password.replaceAll(RegExp(r'.'), '*')}');
      
      _isLoading = true;
      _username = username;
      _password = password;
      _lastError = '';
      debugLog.clear();
      _updateStatus('Connecting to mail server...');

      // Connect to POP3 through bridge proxy port
      _debug('Connecting to bridge.stormycloud.org:8110...');
      _pop3Socket = await Socket.connect(
        'bridge.stormycloud.org', 
        8110,
        timeout: const Duration(seconds: 90), // Increased timeout
      );
      _debug('Socket connected successfully');
      
      // Enable keep-alive to prevent connection drops
      _pop3Socket!.setOption(SocketOption.tcpNoDelay, true);
      
      // Clear any existing response buffer
      _responseBuffer.clear();
      
      _pop3Socket!.listen(
        (data) {
          final response = utf8.decode(data);
          _debug('RAW RECEIVE: ${response.replaceAll('\r\n', '\\r\\n')}');
          
          _commandBuffer += response;
          
          // Process complete lines
          final lines = _commandBuffer.split('\r\n');
          _commandBuffer = lines.last; // Keep incomplete line
          
          for (int i = 0; i < lines.length - 1; i++) {
            if (lines[i].isNotEmpty) {
              _debug('RESPONSE: ${lines[i]}');
              
              // Always add to response buffer if we're in a command
              if (_isCollectingResponse) {
                _responseBuffer.add(lines[i]);
              } else {
                _responseController.add(lines[i]);
              }
            }
          }
        },
        onError: (error) {
          _debug('SOCKET ERROR: $error');
          _isConnected = false;
          _lastError = 'Connection error: $error';
          notifyListeners();
        },
        onDone: () {
          _debug('Socket closed by server');
          _isConnected = false;
          if (_isLoading) {
            _lastError = 'Connection closed unexpectedly';
          }
          notifyListeners();
        },
      );

      // Wait for server greeting
      _updateStatus('Waiting for server response...');
      _debug('Waiting for server greeting...');
      final greeting = await _waitForResponse(
        timeout: const Duration(seconds: 90),
        context: 'greeting',
      );
      
      if (!greeting.startsWith('+OK')) {
        _debug('ERROR: Invalid greeting: $greeting');
        throw Exception('Invalid server greeting');
      }
      _debug('Server greeting received');

      // Send USER command
      _updateStatus('Authenticating...');
      _debug('Sending USER command...');
      await _sendCommand('USER $username');
      final userResponse = await _waitForResponse(
        timeout: const Duration(seconds: 60),
        context: 'USER response',
      );
      
      if (!userResponse.startsWith('+OK')) {
        _debug('ERROR: USER failed: $userResponse');
        throw Exception('Invalid username');
      }
      _debug('USER accepted');

      // Send PASS command
      _debug('Sending PASS command...');
      await _sendCommand('PASS $password');
      final passResponse = await _waitForResponse(
        timeout: const Duration(seconds: 60),
        context: 'PASS response',
      );
      
      if (!passResponse.startsWith('+OK')) {
        _debug('ERROR: PASS failed: $passResponse');
        throw Exception('Invalid password');
      }
      _debug('Authentication successful!');

      _isConnected = true;
      _updateStatus('Connected successfully');
      notifyListeners();

      // Get message count
      _debug('Fetching message list...');
      await _updateMessageList();
      
      _isLoading = false;
      _updateStatus('');
      return true;
    } catch (e, stack) {
      _debug('CONNECTION ERROR: $e');
      _debug('Stack trace: $stack');
      
      // Determine error type
      if (e.toString().contains('TimeoutException')) {
        _lastError = 'Connection timeout - I2P mail servers are slow, please try again';
      } else if (e.toString().contains('Invalid password')) {
        _lastError = 'Invalid username or password';
      } else if (e.toString().contains('Invalid username')) {
        _lastError = 'Invalid username';
      } else {
        _lastError = 'Connection failed: ${e.toString()}';
      }
      
      _isLoading = false;
      _isConnected = false;
      _updateStatus('');
      notifyListeners();
      return false;
    }
  }

  // Send POP3 command
  Future<void> _sendCommand(String command) async {
    if (_pop3Socket == null) {
      _debug('ERROR: Socket is null, cannot send command');
      return;
    }
    
    // Mask password in debug output
    String debugCommand = command;
    if (command.startsWith('PASS ')) {
      debugCommand = 'PASS ****';
    }
    
    _debug('SEND: $debugCommand');
    _pop3Socket!.write('$command\r\n');
  }

  // Wait for response with timeout and context
  Future<String> _waitForResponse({
    Duration timeout = const Duration(seconds: 30),
    String context = '',
  }) async {
    try {
      _debug('Waiting for response ($context)...');
      final response = await _responseController.stream.first.timeout(
        timeout,
        onTimeout: () {
          _debug('TIMEOUT waiting for $context');
          throw TimeoutException('POP3 response timeout for $context');
        },
      );
      return response;
    } catch (e) {
      _debug('ERROR in _waitForResponse: $e');
      rethrow;
    }
  }

  // Collect all responses until end marker
  Future<List<String>> _collectUntilEnd({bool forMessageBody = false}) async {
    _responseBuffer.clear();
    _isCollectingResponse = true;
    
    try {
      // For message bodies, we need to handle larger data
      if (forMessageBody) {
        await Future.delayed(const Duration(milliseconds: 1000));
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }
      
      // Check if we already have the end marker
      final hasEnd = _responseBuffer.any((line) => line == '.');
      
      if (!hasEnd) {
        // Wait for more data with timeout
        final completer = Completer<void>();
        Timer? timer;
        
        StreamSubscription? subscription;
        subscription = _responseController.stream.listen((line) {
          _responseBuffer.add(line);
          if (line == '.') {
            timer?.cancel();
            subscription?.cancel();
            completer.complete();
          }
        });
        
        timer = Timer(Duration(seconds: forMessageBody ? 15 : 5), () {
          subscription?.cancel();
          completer.complete();
        });
        
        await completer.future;
      }
      
      // Clean up duplicate responses for RETR commands
      if (forMessageBody && _responseBuffer.isNotEmpty) {
        // Find the first +OK response and remove any duplicates
        final firstOkIndex = _responseBuffer.indexWhere((line) => line.startsWith('+OK'));
        if (firstOkIndex > 0) {
          // Remove lines before the first +OK
          _responseBuffer.removeRange(0, firstOkIndex);
        }
        
        // Find and remove any duplicate +OK responses
        bool foundFirstOk = false;
        _responseBuffer = _responseBuffer.where((line) {
          if (line.startsWith('+OK')) {
            if (!foundFirstOk) {
              foundFirstOk = true;
              return true;
            }
            return false;
          }
          return true;
        }).toList();
      }
      
      // Remove the end marker if present
      if (_responseBuffer.isNotEmpty && _responseBuffer.last == '.') {
        _responseBuffer.removeLast();
      }
      
      return List.from(_responseBuffer);
    } finally {
      _isCollectingResponse = false;
      _responseBuffer.clear();
    }
  }

  // Get list of messages
  Future<void> _updateMessageList() async {
    if (!_isConnected) {
      _debug('ERROR: Not connected, cannot update message list');
      return;
    }
    
    _isLoading = true;
    _updateStatus('Checking for messages...');
    notifyListeners();

    try {
      // Get message count with STAT
      _debug('Sending STAT command...');
      await _sendCommand('STAT');
      final statResponse = await _waitForResponse(
        timeout: const Duration(seconds: 60),
        context: 'STAT response',
      );
      
      if (statResponse.startsWith('+OK')) {
        final parts = statResponse.split(' ');
        _totalMessages = int.tryParse(parts[1]) ?? 0;
        _debug('STAT response: $_totalMessages messages');
      } else {
        _debug('ERROR: STAT failed: $statResponse');
        _totalMessages = 0;
      }

      if (_totalMessages == 0) {
        _debug('No messages in mailbox');
        _messages = [];
        _isLoading = false;
        _updateStatus('');
        notifyListeners();
        return;
      }

      // Get message list
      _messages.clear();
      
      // Fetch last 50 messages (or all if less)
      final startIndex = _totalMessages > 50 ? _totalMessages - 49 : 1;
      _debug('Fetching messages $startIndex to $_totalMessages...');
      
      int successCount = 0;
      for (int i = _totalMessages; i >= startIndex; i--) {
        // Update status and notify UI immediately for each message
        _statusMessage = 'Loading message ${_totalMessages - i + 1} of ${_totalMessages - startIndex + 1}...';
        notifyListeners();
        
        try {
          // Get message headers with TOP
          _debug('Fetching headers for message $i...');
          await _sendCommand('TOP $i 0');
          
          // Collect all lines until we get "."
          final headerLines = await _collectUntilEnd();
          
          if (headerLines.isNotEmpty && headerLines[0].startsWith('+OK')) {
            // Remove the +OK line
            headerLines.removeAt(0);
            
            final headers = headerLines.join('\n');
            _debug('Received ${headerLines.length} header lines');
            
            // Parse headers
            final from = _extractHeader(headers, 'From:');
            final subject = _extractHeader(headers, 'Subject:');
            final date = _extractHeader(headers, 'Date:');
            
            _debug('Message $i - From: $from, Subject: $subject, Date: $date');
            
            _messages.add(EmailMessage(
              id: i.toString(),
              from: from.isNotEmpty ? from : 'Unknown',
              subject: subject.isNotEmpty ? subject : '(No Subject)',
              date: date.isNotEmpty ? _formatDate(date) : 'Unknown date',
              body: '', // Will be preloaded after headers are fetched
              size: 0,
              isRead: false,
              isPreloaded: false,
            ));
            successCount++;
            
            // Update UI to show the new message
            notifyListeners();
          } else {
            _debug('ERROR: Invalid TOP response for message $i');
          }
        } catch (e) {
          _debug('ERROR fetching message $i: $e');
          // Continue with next message
        }
        
        // Small delay to prevent overwhelming the server
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _debug('Fetched $successCount messages successfully');
      _statusMessage = 'Loaded $successCount messages successfully!';
      _isLoading = false;
      notifyListeners();
      
      // Keep status visible for longer before clearing
      Future.delayed(const Duration(seconds: 3), () {
        _statusMessage = '';
        notifyListeners();
      });
      
      // Start preloading message bodies in the background
      _preloadMessageBodies();
    } catch (e) {
      _debug('ERROR updating message list: $e');
      _isLoading = false;
      _updateStatus('');
      notifyListeners();
    }
  }

  // Format date for display
  String _formatDate(String dateStr) {
    try {
      // Try to parse the date - I2P mail uses various formats
      // Example: "Thu, 24 Jul 2025 02:32:52 +0000 (UTC)"
      final cleanDate = dateStr.replaceAll(RegExp(r'\s*\(.*\)'), '').trim();
      
      // Simple formatting - in production use proper date parsing
      if (cleanDate.contains(',')) {
        final parts = cleanDate.split(',');
        if (parts.length > 1) {
          return parts[1].trim().split(' ').take(3).join(' ');
        }
      }
      return cleanDate;
    } catch (e) {
      return dateStr;
    }
  }

  // Extract header value - handle multiline headers and encodings
  String _extractHeader(String headers, String headerName) {
    final lines = headers.split('\n');
    String headerValue = '';
    bool inHeader = false;
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      
      if (line.toLowerCase().startsWith(headerName.toLowerCase())) {
        headerValue = line.substring(headerName.length).trim();
        inHeader = true;
        continue;
      }
      
      if (inHeader) {
        // Check if this is a continuation line (starts with space or tab)
        if (line.startsWith(' ') || line.startsWith('\t')) {
          headerValue += ' ' + line.trim();
        } else {
          // New header started, we're done
          break;
        }
      }
    }
    
    // Special handling for encrypted subjects showing as "..."
    if (headerName.toLowerCase() == 'subject:') {
      if (headerValue == '...') {
        return '(Encrypted)';
      }
      // Handle partial subjects that got cut off
      if (headerValue.endsWith('<…') || headerValue.endsWith('...')) {
        // Try to extract what we have
        if (headerValue.contains(':')) {
          final parts = headerValue.split(':');
          if (parts.length > 1) {
            return parts[1].trim().replaceAll('<…', '').replaceAll('...', '');
          }
        }
        return headerValue.replaceAll('<…', '').replaceAll('...', '');
      }
    }
    
    // Handle encoded headers (e.g., =?UTF-8?Q?...?=)
    if (headerValue.contains('=?')) {
      // Simple decode - in production use proper MIME decoding
      headerValue = headerValue
        .replaceAll('=?UTF-8?Q?', '')
        .replaceAll('=?UTF-8?B?', '') 
        .replaceAll('?=', '')
        .replaceAll('_', ' ');
    }
    
    // Clean up email addresses
    if (headerName.toLowerCase() == 'from:') {
      // Extract email from "Name <email>" format
      final match = RegExp(r'<([^>]+)>').firstMatch(headerValue);
      if (match != null) {
        final email = match.group(1);
        final name = headerValue.substring(0, match.start).trim();
        return name.isNotEmpty ? name : email ?? headerValue;
      }
      
      // Remove quotes if present
      headerValue = headerValue.replaceAll('"', '');
    }
    
    return headerValue;
  }

  // Preload message bodies in the background
  Future<void> _preloadMessageBodies() async {
    if (!_isConnected || _messages.isEmpty) return;
    
    _debug('Starting background preload of message bodies...');
    
    for (final message in _messages) {
      if (!_isConnected) break; // Stop if disconnected
      if (message.isPreloaded) continue; // Skip already loaded
      
      try {
        _debug('Preloading body for message ${message.id}...');
        final fullMessage = await _getMessageBody(message.id);
        
        if (fullMessage != null) {
          message.body = fullMessage.body;
          message.isPreloaded = true;
          _debug('Preloaded message ${message.id} successfully');
        }
        
        // Delay between fetches to be nice to the server
        await Future.delayed(const Duration(milliseconds: 500));
      } catch (e) {
        _debug('Error preloading message ${message.id}: $e');
      }
    }
    
    _debug('Finished preloading message bodies');
  }
  
  // Get message body without updating UI
  Future<EmailMessage?> _getMessageBody(String messageId) async {
    if (!_isConnected) return null;
    
    try {
      await _sendCommand('RETR $messageId');
      
      // Collect all lines until end marker
      final messageLines = await _collectUntilEnd(forMessageBody: true);
      
      if (messageLines.isNotEmpty && messageLines[0].startsWith('+OK')) {
        // Remove the +OK line
        messageLines.removeAt(0);
        
        // Find the empty line that separates headers from body
        int headerEndIndex = -1;
        for (int i = 0; i < messageLines.length; i++) {
          if (messageLines[i].trim().isEmpty) {
            headerEndIndex = i;
            break;
          }
        }
        
        String headers = '';
        String body = '';
        
        if (headerEndIndex > 0) {
          headers = messageLines.sublist(0, headerEndIndex).join('\n');
          if (headerEndIndex + 1 < messageLines.length) {
            body = messageLines.sublist(headerEndIndex + 1).join('\n').trim();
            
            // Check if this is a multipart message - either by content type or by boundary markers
            final contentType = _extractHeader(headers, 'Content-Type:');
            if (contentType.contains('multipart/') || body.contains('------WEI3KH1ZHXE3MB23OXFMHFSXNKO9XW')) {
              body = _parseMultipartMessage(body, contentType);
            }
          }
        } else {
          headers = messageLines.join('\n');
          final dateIndex = headers.lastIndexOf('Date:');
          if (dateIndex >= 0) {
            final afterDate = headers.substring(dateIndex);
            final lines = afterDate.split('\n');
            if (lines.length > 1) {
              body = lines.sublist(1).join('\n').trim();
              headers = headers.substring(0, dateIndex + lines[0].length);
              
              // Check if body looks like multipart
              if (body.contains('------WEI3KH1ZHXE3MB23OXFMHFSXNKO9XW')) {
                body = _parseMultipartMessage(body, '');
              }
            }
          }
        }
        
        final from = _extractHeader(headers, 'From:');
        final subject = _extractHeader(headers, 'Subject:');
        final date = _extractHeader(headers, 'Date:');
        
        return EmailMessage(
          id: messageId,
          from: from,
          subject: subject.isEmpty ? '(No Subject)' : subject,
          date: _formatDate(date),
          body: body.isEmpty ? '(No content)' : body,
          size: messageLines.join('\n').length,
          isRead: true,
          isPreloaded: true,
        );
      }
    } catch (e) {
      _debug('Error getting message body: $e');
    }
    
    return null;
  }

  // Get full message
  Future<EmailMessage?> getMessage(String messageId) async {
    if (!_isConnected) {
      _debug('ERROR: Not connected, cannot get message');
      return null;
    }
    
    // Check if message is already preloaded
    final existingMessage = _messages.firstWhere(
      (msg) => msg.id == messageId,
      orElse: () => EmailMessage(
        id: '', 
        from: '', 
        subject: '', 
        date: '', 
        body: '', 
        size: 0,
      ),
    );
    
    if (existingMessage.id.isNotEmpty && existingMessage.isPreloaded && existingMessage.body.isNotEmpty) {
      _debug('Using preloaded message body for message $messageId');
      return existingMessage;
    }
    
    // If not preloaded, fetch it now
    _updateStatus('Loading message...');
    
    try {
      final fullMessage = await _getMessageBody(messageId);
      
      if (fullMessage != null) {
        // Update the existing message with the body
        if (existingMessage.id.isNotEmpty) {
          existingMessage.body = fullMessage.body;
          existingMessage.isPreloaded = true;
        }
        
        _updateStatus('');
        return fullMessage;
      } else {
        _debug('ERROR: Failed to retrieve message');
        _updateStatus('');
        return null;
      }
    } catch (e) {
      _debug('ERROR getting message: $e');
      _updateStatus('');
      return null;
    }
  }

  // Send email via SMTP
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    if (_username == null || _password == null) {
      _debug('ERROR: No credentials for sending email');
      return false;
    }
    
    _updateStatus('Sending email...');
    
    try {
      _debug('=== Starting SMTP Connection ===');
      _debug('Connecting to bridge.stormycloud.org:8025...');
      
      // Connect to SMTP through bridge proxy port
      _smtpSocket = await Socket.connect(
        'bridge.stormycloud.org', 
        8025,
        timeout: const Duration(seconds: 60),
      );
      _debug('SMTP socket connected');
      
      final smtpResponse = StreamController<String>.broadcast();
      String smtpBuffer = '';
      
      _smtpSocket!.listen(
        (data) {
          final response = utf8.decode(data);
          _debug('SMTP RAW: ${response.replaceAll('\r\n', '\\r\\n')}');
          smtpBuffer += response;
          
          final lines = smtpBuffer.split('\r\n');
          smtpBuffer = lines.last;
          
          for (int i = 0; i < lines.length - 1; i++) {
            if (lines[i].isNotEmpty) {
              _debug('SMTP RESPONSE: ${lines[i]}');
              smtpResponse.add(lines[i]);
            }
          }
        },
      );

      // Wait for greeting
      _debug('Waiting for SMTP greeting...');
      final greeting = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 60),
      );
      if (!greeting.startsWith('220')) {
        _debug('ERROR: Invalid SMTP greeting: $greeting');
        return false;
      }

      // HELO
      _debug('Sending HELO...');
      _smtpSocket!.write('HELO localhost\r\n');
      final heloResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!heloResponse.startsWith('250')) {
        _debug('ERROR: HELO failed: $heloResponse');
        return false;
      }

      // AUTH LOGIN
      _debug('Sending AUTH LOGIN...');
      _smtpSocket!.write('AUTH LOGIN\r\n');
      final authResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!authResponse.startsWith('334')) {
        _debug('ERROR: AUTH LOGIN failed: $authResponse');
        return false;
      }

      // Username (base64)
      _debug('Sending username...');
      _smtpSocket!.write('${base64.encode(utf8.encode(_username!))}\r\n');
      final userResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!userResponse.startsWith('334')) {
        _debug('ERROR: Username failed: $userResponse');
        return false;
      }

      // Password (base64)
      _debug('Sending password...');
      _smtpSocket!.write('${base64.encode(utf8.encode(_password!))}\r\n');
      final passResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!passResponse.startsWith('235')) {
        _debug('ERROR: Password failed: $passResponse');
        return false;
      }

      // MAIL FROM
      _debug('Sending MAIL FROM...');
      final fromAddress = _username!.contains('@') ? _username! : '$_username@mail.i2p';
      _smtpSocket!.write('MAIL FROM:<$fromAddress>\r\n');
      final fromResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!fromResponse.startsWith('250')) {
        _debug('ERROR: MAIL FROM failed: $fromResponse');
        return false;
      }

      // RCPT TO
      _debug('Sending RCPT TO: $to...');
      final toAddress = to.contains('@') ? to : '$to@mail.i2p';
      _smtpSocket!.write('RCPT TO:<$toAddress>\r\n');
      final toResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!toResponse.startsWith('250')) {
        _debug('ERROR: RCPT TO failed: $toResponse');
        return false;
      }

      // DATA
      _debug('Sending DATA...');
      _smtpSocket!.write('DATA\r\n');
      final dataResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!dataResponse.startsWith('354')) {
        _debug('ERROR: DATA failed: $dataResponse');
        return false;
      }

      // Email content
      final now = DateTime.now().toUtc();
      final emailContent = '''From: $fromAddress\r
To: $toAddress\r
Subject: $subject\r
Date: ${_formatSmtpDate(now)}\r
MIME-Version: 1.0\r
Content-Type: text/plain; charset=UTF-8\r
\r
$body\r
.\r
''';
      _debug('Sending email content...');
      _smtpSocket!.write(emailContent);
      
      final sentResponse = await smtpResponse.stream.first.timeout(
        const Duration(seconds: 30),
      );
      if (!sentResponse.startsWith('250')) {
        _debug('ERROR: Send failed: $sentResponse');
        return false;
      }

      // QUIT
      _debug('Sending QUIT...');
      _smtpSocket!.write('QUIT\r\n');
      await _smtpSocket!.close();
      
      _debug('Email sent successfully!');
      _updateStatus('');
      return true;
    } catch (e) {
      _debug('SMTP ERROR: $e');
      _updateStatus('');
      return false;
    }
  }

  // Format date for SMTP
  String _formatSmtpDate(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final weekday = weekdays[date.weekday - 1];
    final month = months[date.month - 1];
    
    return '$weekday, ${date.day} $month ${date.year} '
           '${date.hour.toString().padLeft(2, '0')}:'
           '${date.minute.toString().padLeft(2, '0')}:'
           '${date.second.toString().padLeft(2, '0')} +0000';
  }

  // Parse multipart messages
  String _parseMultipartMessage(String body, String contentType) {
    // Extract boundary from content type
    final boundaryMatch = RegExp(r'boundary="?([^";\s]+)"?').firstMatch(contentType);
    if (boundaryMatch == null) {
      // If no boundary found, check if body looks like multipart anyway
      if (body.contains('------WEI3KH1ZHXE3MB23OXFMHFSXNKO9XW')) {
        return _parseMultipartWithKnownBoundary(body, '------WEI3KH1ZHXE3MB23OXFMHFSXNKO9XW');
      }
      return body;
    }
    
    final boundary = boundaryMatch.group(1)!;
    return _parseMultipartWithKnownBoundary(body, boundary);
  }
  
  String _parseMultipartWithKnownBoundary(String body, String boundary) {
    final parts = body.split(boundary);
    
    // Look for text/plain part first, then text/html
    String textContent = '';
    String htmlContent = '';
    
    for (final part in parts) {
      if (part.trim().isEmpty || part.contains('--')) continue;
      
      final partLines = part.split('\n');
      int partHeaderEnd = -1;
      
      // Find where part headers end
      for (int i = 0; i < partLines.length; i++) {
        if (partLines[i].trim().isEmpty) {
          partHeaderEnd = i;
          break;
        }
      }
      
      if (partHeaderEnd > 0) {
        final partHeaders = partLines.sublist(0, partHeaderEnd).join('\n');
        final partBody = partLines.sublist(partHeaderEnd + 1).join('\n').trim();
        
        if (partHeaders.toLowerCase().contains('content-type: text/plain')) {
          // Decode quoted-printable if needed
          if (partHeaders.toLowerCase().contains('quoted-printable')) {
            textContent = _decodeQuotedPrintable(partBody);
          } else {
            textContent = partBody;
          }
        } else if (partHeaders.toLowerCase().contains('content-type: text/html')) {
          if (partHeaders.toLowerCase().contains('quoted-printable')) {
            htmlContent = _decodeQuotedPrintable(partBody);
          } else {
            htmlContent = partBody;
          }
        }
      }
    }
    
    // Prefer plain text, fall back to HTML stripped of tags
    if (textContent.isNotEmpty) {
      return textContent;
    } else if (htmlContent.isNotEmpty) {
      // Basic HTML stripping
      return htmlContent
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
    }
    
    return body;
  }
  
  // Decode quoted-printable encoding
  String _decodeQuotedPrintable(String input) {
    return input.replaceAllMapped(
      RegExp(r'=([0-9A-F]{2})'),
      (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
    ).replaceAll('=\n', '');
  }
  
  // Format reply email
  String formatReplyBody(EmailMessage originalMessage) {
    final date = originalMessage.date;
    final from = originalMessage.from;
    final body = originalMessage.body;
    
    // Create quoted reply format
    final quotedBody = body.split('\n').map((line) => '> $line').join('\n');
    
    return '\n\nOn $date, $from wrote:\n$quotedBody';
  }
  
  // Get reply subject
  String getReplySubject(String originalSubject) {
    if (originalSubject.startsWith('Re:')) {
      return originalSubject;
    }
    return 'Re: $originalSubject';
  }

  // Refresh inbox
  Future<void> refresh() async {
    _debug('Refreshing inbox...');
    await _updateMessageList();
  }

  // Disconnect
  void disconnect() {
    _debug('Disconnecting...');
    _pop3Socket?.write('QUIT\r\n');
    _pop3Socket?.close();
    _smtpSocket?.close();
    
    _isConnected = false;
    _username = null;
    _password = null;
    _messages.clear();
    _totalMessages = 0;
    _statusMessage = '';
    _lastError = '';
    _debug('Disconnected');
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _responseController.close();
    super.dispose();
  }
}