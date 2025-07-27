// lib/services/pop3_mail_service.dart
// Mail service using server-side parsing and HTTP API

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  Socket? _smtpSocket; // Keep SMTP for sending emails
  
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isSending = false;
  String? _username;
  String? _password;
  
  List<EmailMessage> _messages = [];
  int _totalMessages = 0;
  String _statusMessage = '';
  String _lastError = '';
  
  // Server configuration
  static const String _serverBaseUrl = 'http://bridge.stormycloud.org:3000';
  static const String _serverHost = 'bridge.stormycloud.org';
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

  // Connect using server-side API
  Future<bool> connect(String username, String password) async {
    try {
      _debug('=== Connecting via Server API ===');
      _debug('Username: $username');
      
      _isLoading = true;
      _username = username;
      _password = password;
      _lastError = '';
      debugLog.clear();
      _updateStatus('Testing connection...');

      _debug('Testing connection via server API...');
      _updateStatus('Authenticating...');
      
      final response = await http.get(
        Uri.parse('$_serverBaseUrl/api/v1/mail/headers')
            .replace(queryParameters: {
          'user': username,
          'pass': password,
          'start': '1',
          'count': '1',
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _debug('Authentication successful! Found ${data['messageCount'] ?? 0} messages');
        
        _isConnected = true;
        _updateStatus('Connected successfully');
        notifyListeners();

        // Get the full message list
        await _updateMessageList();
        
        _isLoading = false;
        _updateStatus('');
        return true;
      } else {
        _debug('ERROR: Server returned ${response.statusCode}');
        if (response.statusCode == 500) {
          _lastError = 'Invalid username or password';
        } else {
          _lastError = 'Connection failed: ${response.statusCode}';
        }
      }
    } catch (e) {
      _debug('CONNECTION ERROR: $e');
      
      if (e.toString().contains('TimeoutException')) {
        _lastError = 'Connection timeout - please try again';
      } else if (e.toString().contains('Authentication failed')) {
        _lastError = 'Invalid username or password';
      } else {
        _lastError = 'Connection failed: ${e.toString()}';
      }
    }
    
    _isLoading = false;
    _isConnected = false;
    _updateStatus('');
    notifyListeners();
    return false;
  }

  // Get message list using server-side header fetching with prefetching
  Future<void> _updateMessageList() async {
    if (!_isConnected || _username == null || _password == null) return;
    
    _isLoading = true;
    _updateStatus('Loading messages...');
    notifyListeners();

    try {
      _debug('Fetching message headers from server API...');
      
      final response = await http.get(
        Uri.parse('$_serverBaseUrl/api/v1/mail/headers')
            .replace(queryParameters: {
          'user': _username!,
          'pass': _password!,
          'start': '1',
          'count': '50',
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 45));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _debug('Received headers for ${data['messages']?.length ?? 0} messages');
        
        _messages.clear();
        _totalMessages = data['messageCount'] ?? 0;
        
        if (data['messages'] != null) {
          for (final messageData in data['messages']) {
            final emailMessage = EmailMessage(
              id: messageData['number'].toString(),
              from: messageData['from'] ?? 'Unknown',
              subject: messageData['subject'] ?? '(No Subject)',
              date: _formatServerDate(messageData['date']),
              body: '', // Will be loaded on demand
              size: 0,
              isRead: false,
              isPreloaded: false,
            );
            
            _messages.add(emailMessage);
          }
        }
        
        _debug('Loaded ${_messages.length} message headers successfully');
        _isLoading = false;
        _updateStatus('');
        notifyListeners();
        
        // Start prefetching top 10 messages in background
        _prefetchRecentMessages();
        
      } else {
        _debug('ERROR: Server returned ${response.statusCode}: ${response.body}');
        throw Exception('Server error: ${response.statusCode}');
      }
      
    } catch (e) {
      _debug('ERROR fetching headers from server: $e');
      _isLoading = false;
      
      // Set user-friendly error message
      if (e.toString().contains('TimeoutException')) {
        _lastError = 'Loading messages timed out. I2P network is slow - please try again.';
        _updateStatus('Timeout - please try refreshing');
      } else {
        _lastError = 'Failed to load messages: ${e.toString()}';
        _updateStatus('Error loading messages');
      }
      
      notifyListeners();
      
      // Clear error status after a delay
      Future.delayed(const Duration(seconds: 5), () {
        _updateStatus('');
        notifyListeners();
      });
    }
  }

  // Prefetch the most recent messages in background
  Future<void> _prefetchRecentMessages() async {
    if (_messages.isEmpty) return;
    
    _debug('Starting background prefetch of recent messages...');
    
    // Get the top 5 most recent messages (reduced from 10 to avoid overwhelming I2P)
    final messagesToPrefetch = _messages.take(5).toList();
    
    int successCount = 0;
    int maxAttempts = 3; // Limit attempts to avoid endless retries
    
    for (final message in messagesToPrefetch) {
      if (!_isConnected) break; // Stop if disconnected
      if (message.isPreloaded) continue; // Skip already loaded
      if (successCount >= maxAttempts) break; // Don't overload the server
      
      try {
        _debug('Prefetching message ${message.id}...');
        final fullMessage = await _fetchMessageSilently(message.id);
        
        if (fullMessage != null) {
          message.body = fullMessage.body;
          message.htmlBody = fullMessage.htmlBody;
          message.isPreloaded = true;
          successCount++;
          _debug('Prefetched message ${message.id} successfully');
        }
        
        // Longer delay to be nice to I2P network
        await Future.delayed(const Duration(milliseconds: 1000));
      } catch (e) {
        _debug('Error prefetching message ${message.id}: $e');
        // Continue with next message instead of stopping
      }
    }
    
    _debug('Finished prefetching recent messages (${successCount} successful)');
  }

  // Fetch message without updating UI status - more resilient version
  Future<EmailMessage?> _fetchMessageSilently(String messageId) async {
    if (!_isConnected || _username == null || _password == null) return null;
    
    try {
      final response = await http.get(
        Uri.parse('$_serverBaseUrl/api/v1/mail/parsed')
            .replace(queryParameters: {
          'user': _username!,
          'pass': _password!,
          'msg': messageId,
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15)); // Shorter timeout for prefetching
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        final List<EmailAttachment> attachments = [];
        if (data['attachments'] != null) {
          for (final attachmentData in data['attachments']) {
            attachments.add(EmailAttachment.fromJson(attachmentData));
          }
        }
        
        return EmailMessage(
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
      }
    } catch (e) {
      // Silent failure for prefetching - don't spam logs
      return null;
    }
    return null;
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

  // Get full message using server-side parsing
  Future<EmailMessage?> getMessage(String messageId) async {
    if (!_isConnected || _username == null || _password == null) {
      _debug('ERROR: Not connected or missing credentials');
      return null;
    }
    
    // Check if message is already prefetched
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
      _debug('Using prefetched message body for message $messageId');
      return existingMessage;
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

  // Delete message using server API with proper POP3 deletion
  Future<bool> deleteMessage(String messageId) async {
    if (!_isConnected || _username == null || _password == null) {
      _debug('ERROR: Not connected, cannot delete message');
      return false;
    }
    
    try {
      _debug('Deleting message $messageId via server...');
      
      final response = await http.delete(
        Uri.parse('$_serverBaseUrl/api/v1/mail/$messageId')
            .replace(queryParameters: {
          'user': _username!,
          'pass': _password!,
        }),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _debug('Message $messageId deleted successfully on server');
          
          // Remove from local list
          _messages.removeWhere((msg) => msg.id == messageId);
          notifyListeners();
          
          return true;
        }
      }
      
      _debug('ERROR: Delete failed with status ${response.statusCode}');
      _debug('Response body: ${response.body}');
      return false;
    } catch (e) {
      _debug('ERROR deleting message: $e');
      return false;
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

      // SMTP protocol implementation
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
    super.dispose();
  }
}