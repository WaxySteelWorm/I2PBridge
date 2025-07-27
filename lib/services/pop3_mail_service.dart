// lib/services/pop3_mail_service.dart
// Updated POP3/SMTP client using server-side mail parsing

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class EmailMessage {
  final String id;
  final String from;
  final String subject;
  final String date;
  String body;
  String? htmlBody;
  final int size;
  bool isRead;
  bool isPreloaded;
  bool isDeleted;
  final List<EmailAttachment> attachments;

  EmailMessage({
    required this.id,
    required this.from,
    required this.subject,
    required this.date,
    required this.body,
    this.htmlBody,
    required this.size,
    this.isRead = false,
    this.isPreloaded = false,
    this.isDeleted = false,
    this.attachments = const [],
  });
}

class EmailAttachment {
  final String? filename;
  final String contentType;
  final int size;
  final String? cid;

  EmailAttachment({
    this.filename,
    required this.contentType,
    required this.size,
    this.cid,
  });

  factory EmailAttachment.fromJson(Map<String, dynamic> json) {
    return EmailAttachment(
      filename: json['filename'],
      contentType: json['contentType'] ?? 'application/octet-stream',
      size: json['size'] ?? 0,
      cid: json['cid'],
    );
  }
}

class Pop3MailService with ChangeNotifier {
  Socket? _pop3Socket;
  Socket? _smtpSocket;
  
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isSending = false;
  String? _username;
  String? _password;
  
  List<EmailMessage> _messages = [];
  int _totalMessages = 0;
  String _statusMessage = '';
  String _lastError = '';
  
  // Server-side parsing configuration
  static const String _serverBaseUrl = 'http://bridge.stormycloud.org:3000';
  static const String _serverHost = 'bridge.stormycloud.org';
  static const int _pop3Port = 8110;
  static const int _smtpPort = 8025;
  
  // Debug mode
  bool debugMode = true;
  List<String> debugLog = [];
  
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get username => _username;
  List<EmailMessage> get messages => _messages.where((m) => !m.isDeleted).toList();
  int get totalMessages => _totalMessages;
  String get statusMessage => _statusMessage;
  String get lastError => _lastError;

  // Response handling for POP3 commands
  final StreamController<String> _responseController = StreamController<String>.broadcast();
  String _commandBuffer = '';

  Pop3MailService();

  void _debug(String message) {
    if (debugMode) {
      final timestamp = DateTime.now().toString().substring(11, 19);
      final logMessage = '[$timestamp] $message';
      print('[MAIL] $logMessage');
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

  // Test server connection and authentication
  Future<bool> connect(String username, String password) async {
    try {
      _debug('=== Testing Server-Side Mail Parsing ===');
      _debug('Username: $username');
      
      _isLoading = true;
      _username = username;
      _password = password;
      _lastError = '';
      debugLog.clear();
      _updateStatus('Testing connection...');

      // Test connection by fetching message count via POP3
      _debug('Connecting to POP3 server for authentication test...');
      _pop3Socket = await Socket.connect(
        _serverHost, 
        _pop3Port,
        timeout: const Duration(seconds: 90),
      );
      _debug('Socket connected successfully');
      
      _pop3Socket!.setOption(SocketOption.tcpNoDelay, true);
      
      _pop3Socket!.listen(
        (data) {
          final response = utf8.decode(data);
          _debug('RAW RECEIVE: ${response.replaceAll('\r\n', '\\r\\n')}');
          
          _commandBuffer += response;
          final lines = _commandBuffer.split('\r\n');
          _commandBuffer = lines.last;
          
          for (int i = 0; i < lines.length - 1; i++) {
            if (lines[i].isNotEmpty) {
              _debug('RESPONSE: ${lines[i]}');
              _responseController.add(lines[i]);
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
        },
      );

      // Authenticate via POP3
      _updateStatus('Authenticating...');
      final greeting = await _waitForResponse(
        timeout: const Duration(seconds: 90),
        context: 'greeting',
      );
      
      if (!greeting.startsWith('+OK')) {
        throw Exception('Invalid server greeting');
      }

      await _sendCommand('USER $username');
      final userResponse = await _waitForResponse(
        timeout: const Duration(seconds: 60),
        context: 'USER response',
      );
      
      if (!userResponse.startsWith('+OK')) {
        throw Exception('Invalid username');
      }

      await _sendCommand('PASS $password');
      final passResponse = await _waitForResponse(
        timeout: const Duration(seconds: 60),
        context: 'PASS response',
      );
      
      if (!passResponse.startsWith('+OK')) {
        throw Exception('Invalid password');
      }

      _debug('Authentication successful!');
      _isConnected = true;
      _updateStatus('Connected successfully');
      notifyListeners();

      // Get message count and headers
      await _updateMessageList();
      
      _isLoading = false;
      _updateStatus('');
      return true;
    } catch (e) {
      _debug('CONNECTION ERROR: $e');
      
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

  Future<void> _sendCommand(String command) async {
    if (_pop3Socket == null) return;
    
    String debugCommand = command;
    if (command.startsWith('PASS ')) {
      debugCommand = 'PASS ****';
    }
    
    _debug('SEND: $debugCommand');
    _pop3Socket!.write('$command\r\n');
  }

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

  // Get message list using traditional POP3 for headers, then server parsing for bodies
  Future<void> _updateMessageList() async {
    if (!_isConnected) return;
    
    _isLoading = true;
    _updateStatus('Checking for messages...');
    notifyListeners();

    try {
      // Get message count with STAT
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
        _totalMessages = 0;
      }

      if (_totalMessages == 0) {
        _messages = [];
        _isLoading = false;
        _updateStatus('');
        notifyListeners();
        return;
      }

      // Get message headers using POP3 TOP command
      _messages.clear();
      final startIndex = _totalMessages > 50 ? _totalMessages - 49 : 1;
      
      for (int i = _totalMessages; i >= startIndex; i--) {
        _statusMessage = 'Loading message ${_totalMessages - i + 1} of ${_totalMessages - startIndex + 1}...';
        notifyListeners();
        
        try {
          await _sendCommand('TOP $i 0');
          final headerLines = await _collectHeaderResponse();
          
          if (headerLines.isNotEmpty) {
            final headers = headerLines.join('\n');
            final from = _extractHeader(headers, 'From:');
            final subject = _extractHeader(headers, 'Subject:');
            final date = _extractHeader(headers, 'Date:');
            
            _messages.add(EmailMessage(
              id: i.toString(),
              from: from.isNotEmpty ? from : 'Unknown',
              subject: subject.isNotEmpty ? subject : '(No Subject)',
              date: date.isNotEmpty ? _formatDate(date) : 'Unknown date',
              body: '', // Will be loaded using server-side parsing
              size: 0,
              isRead: false,
              isPreloaded: false,
            ));
            
            notifyListeners();
          }
        } catch (e) {
          _debug('ERROR fetching message $i: $e');
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
      }

      _debug('Fetched ${_messages.length} message headers successfully');
      _statusMessage = 'Loaded ${_messages.length} messages successfully!';
      _isLoading = false;
      notifyListeners();
      
      Future.delayed(const Duration(seconds: 2), () {
        _statusMessage = '';
        notifyListeners();
      });
      
    } catch (e) {
      _debug('ERROR updating message list: $e');
      _isLoading = false;
      _updateStatus('');
      notifyListeners();
    }
  }

  Future<List<String>> _collectHeaderResponse() async {
    final List<String> responseBuffer = [];
    
    while (true) {
      try {
        final line = await _responseController.stream.first.timeout(
          const Duration(seconds: 5),
        );
        
        if (line == '.') {
          break;
        }
        
        responseBuffer.add(line);
      } catch (e) {
        break;
      }
    }
    
    // Remove the +OK line if present
    if (responseBuffer.isNotEmpty && responseBuffer[0].startsWith('+OK')) {
      responseBuffer.removeAt(0);
    }
    
    return responseBuffer;
  }

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
        if (line.startsWith(' ') || line.startsWith('\t')) {
          headerValue += ' ' + line.trim();
        } else {
          break;
        }
      }
    }
    
    // Handle encrypted subjects
    if (headerName.toLowerCase() == 'subject:' && headerValue == '...') {
      return '(Encrypted)';
    }
    
    // Clean up from addresses
    if (headerName.toLowerCase() == 'from:') {
      final match = RegExp(r'<([^>]+)>').firstMatch(headerValue);
      if (match != null) {
        final email = match.group(1);
        final name = headerValue.substring(0, match.start).trim();
        return name.isNotEmpty ? name : email ?? headerValue;
      }
      headerValue = headerValue.replaceAll('"', '');
    }
    
    return headerValue;
  }

  String _formatDate(String dateStr) {
    try {
      final cleanDate = dateStr.replaceAll(RegExp(r'\s*\(.*\)'), '').trim();
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

  // Get full message using server-side parsing
  Future<EmailMessage?> getMessage(String messageId) async {
    if (!_isConnected || _username == null || _password == null) {
      _debug('ERROR: Not connected or missing credentials');
      return null;
    }
    
    _updateStatus('Loading message...');
    
    try {
      _debug('Fetching parsed message $messageId from server...');
      
      final response = await http.get(
        Uri.parse('$_serverBaseUrl/api/v1/mail/parsed')
            .replace(queryParameters: {
          'user': _username!,
          'pass': _password!,
          'msg': messageId,
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _debug('Received parsed message data from server');
        
        // Extract attachments
        final List<EmailAttachment> attachments = [];
        if (data['attachments'] != null) {
          for (final attachmentData in data['attachments']) {
            attachments.add(EmailAttachment.fromJson(attachmentData));
          }
        }
        
        final emailMessage = EmailMessage(
          id: messageId,
          from: data['from']?.toString() ?? 'Unknown',
          subject: data['subject']?.toString() ?? '(No Subject)',
          date: _formatServerDate(data['date']),
          body: data['text']?.toString() ?? '(No content)',
          htmlBody: _safeGetString(data['html']),
          size: (data['text']?.toString().length ?? 0) + (_safeGetString(data['html'])?.length ?? 0),
          isRead: true,
          isPreloaded: true,
          attachments: attachments,
        );
        
        // Update the existing message in the list
        final existingIndex = _messages.indexWhere((msg) => msg.id == messageId);
        if (existingIndex != -1) {
          _messages[existingIndex].body = emailMessage.body;
          _messages[existingIndex].htmlBody = emailMessage.htmlBody;
          _messages[existingIndex].isPreloaded = true;
          _messages[existingIndex].isRead = true;
        }
        
        _updateStatus('');
        return emailMessage;
      } else {
        _debug('ERROR: Server returned ${response.statusCode}');
        _updateStatus('');
        return null;
      }
    } catch (e) {
      _debug('ERROR fetching parsed message: $e');
      _updateStatus('');
      return null;
    }
  }

  // Safely get string value from dynamic data
  String? _safeGetString(dynamic value) {
    if (value == null || value == false) return null;
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  String _formatServerDate(dynamic dateData) {
    if (dateData == null) return 'Unknown date';
    
    try {
      final DateTime date = DateTime.parse(dateData.toString());
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateData.toString();
    }
  }

  // Delete message
  Future<bool> deleteMessage(String messageId) async {
    if (!_isConnected) return false;
    
    try {
      _debug('Deleting message $messageId...');
      _updateStatus('Deleting message...');
      
      await _sendCommand('DELE $messageId');
      final response = await _waitForResponse(
        timeout: const Duration(seconds: 30),
        context: 'DELE response',
      );
      
      if (response.startsWith('+OK')) {
        final message = _messages.firstWhere(
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
        
        if (message.id.isNotEmpty) {
          message.isDeleted = true;
          notifyListeners();
        }
        
        _updateStatus('');
        return true;
      } else {
        _updateStatus('');
        return false;
      }
    } catch (e) {
      _debug('ERROR deleting message: $e');
      _updateStatus('');
      return false;
    }
  }

  // Send email via SMTP (unchanged)
  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    if (_username == null || _password == null) {
      _debug('ERROR: No credentials for sending email');
      return false;
    }
    
    _isSending = true;
    _updateStatus('Sending email...');
    notifyListeners();
    
    try {
      _debug('=== Starting SMTP Connection ===');
      _smtpSocket = await Socket.connect(
        _serverHost, 
        _smtpPort,
        timeout: const Duration(seconds: 60),
      );
      
      final smtpResponse = StreamController<String>.broadcast();
      String smtpBuffer = '';
      
      _smtpSocket!.listen((data) {
        final response = utf8.decode(data);
        smtpBuffer += response;
        
        final lines = smtpBuffer.split('\r\n');
        smtpBuffer = lines.last;
        
        for (int i = 0; i < lines.length - 1; i++) {
          if (lines[i].isNotEmpty) {
            smtpResponse.add(lines[i]);
          }
        }
      });

      // SMTP protocol implementation (same as before)
      final greeting = await smtpResponse.stream.first.timeout(const Duration(seconds: 60));
      if (!greeting.startsWith('220')) throw Exception('Invalid SMTP greeting');

      _smtpSocket!.write('HELO localhost\r\n');
      final heloResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!heloResponse.startsWith('250')) throw Exception('HELO failed');

      _smtpSocket!.write('AUTH LOGIN\r\n');
      final authResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!authResponse.startsWith('334')) throw Exception('AUTH LOGIN failed');

      _smtpSocket!.write('${base64.encode(utf8.encode(_username!))}\r\n');
      final userResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!userResponse.startsWith('334')) throw Exception('Username authentication failed');

      _smtpSocket!.write('${base64.encode(utf8.encode(_password!))}\r\n');
      final passResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!passResponse.startsWith('235')) throw Exception('Password authentication failed');

      final fromAddress = _username!.contains('@') ? _username! : '$_username@mail.i2p';
      _smtpSocket!.write('MAIL FROM:<$fromAddress>\r\n');
      final fromResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!fromResponse.startsWith('250')) throw Exception('MAIL FROM failed');

      final toAddress = to.contains('@') ? to : '$to@mail.i2p';
      _smtpSocket!.write('RCPT TO:<$toAddress>\r\n');
      final toResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!toResponse.startsWith('250')) throw Exception('RCPT TO failed');

      _smtpSocket!.write('DATA\r\n');
      final dataResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!dataResponse.startsWith('354')) throw Exception('DATA command failed');

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
      _smtpSocket!.write(emailContent);
      
      final sentResponse = await smtpResponse.stream.first.timeout(const Duration(seconds: 30));
      if (!sentResponse.startsWith('250')) throw Exception('Failed to send email');

      _smtpSocket!.write('QUIT\r\n');
      await _smtpSocket!.close();
      _smtpSocket = null;
      
      _isSending = false;
      _updateStatus('Email sent successfully!');
      
      Future.delayed(const Duration(seconds: 2), () {
        _updateStatus('');
        notifyListeners();
      });
      
      return true;
    } catch (e) {
      _debug('SMTP ERROR: $e');
      _isSending = false;
      _lastError = 'Failed to send email: ${e.toString()}';
      _updateStatus('');
      
      try {
        await _smtpSocket?.close();
      } catch (_) {}
      _smtpSocket = null;
      
      notifyListeners();
      return false;
    }
  }

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
  
  String formatReplyBody(EmailMessage originalMessage) {
    final date = originalMessage.date;
    final from = originalMessage.from;
    final body = originalMessage.body;
    
    final quotedBody = body.split('\n').map((line) => '> $line').join('\n');
    return '\n\nOn $date, $from wrote:\n$quotedBody';
  }
  
  String getReplySubject(String originalSubject) {
    if (originalSubject.startsWith('Re:')) {
      return originalSubject;
    }
    return 'Re: $originalSubject';
  }

  Future<void> refresh() async {
    _debug('Refreshing inbox...');
    await _updateMessageList();
  }

  void disconnect() {
    _debug('Disconnecting...');
    
    if (_pop3Socket != null) {
      try {
        _pop3Socket!.write('QUIT\r\n');
      } catch (e) {
        _debug('Error sending QUIT: $e');
      }
    }
    
    _pop3Socket?.close();
    _smtpSocket?.close();
    
    _isConnected = false;
    _isSending = false;
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