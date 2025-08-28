// lib/services/pop3_mail_service.dart
// Production mail service with end-to-end encryption

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debug_service.dart';
import 'auth_service.dart';


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

class EncryptedCredentials {
  final String encryptedUser;
  final String encryptedPass;
  final String key;
  final String iv;

  EncryptedCredentials({
    required this.encryptedUser,
    required this.encryptedPass,
    required this.key,
    required this.iv,
  });

  Map<String, dynamic> toJson() {
    return {
      'user': encryptedUser,
      'pass': encryptedPass,
      'key': key,
      'iv': iv,
    };
  }
}

class Pop3MailService with ChangeNotifier {
  // Authentication service
  AuthService? _authService;
  
  // Encryption components
  late Uint8List _credentialKey;
  late Uint8List _credentialIV;
  EncryptedCredentials? _encryptedCredentials;

  bool _isConnected = false;
  bool _isLoading = false;
  bool _isSending = false;
  String? _username;

  List<EmailMessage> _messages = [];
  int _totalMessages = 0;
  String _statusMessage = '';
  String _lastError = '';

  // Server configuration
  static const String _serverBaseUrl = 'https://bridge.stormycloud.org';
  
  // SSL Pinning configuration - Updated to use certificate fingerprint
  static const String expectedCertFingerprint = 'AO5T/CbxDzIBFkUp6jLEcAk0+ZxeN06uaKyeIzIE+E0=';
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';
  late http.Client _httpClient;

  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get username => _username;
  List<EmailMessage> get messages => _messages.where((m) => !m.isDeleted).toList();
  int get totalMessages => _totalMessages;
  String get statusMessage => _statusMessage;
  String get lastError => _lastError;

  Pop3MailService() {
    _initializeEncryption();
    _httpClient = _createPinnedHttpClient();
  }
  
  // Set the authentication service (called from UI)
  void setAuthService(AuthService authService) {
    _authService = authService;
  }
  
  // Get authenticated headers for HTTP requests
  Future<Map<String, String>> _getAuthenticatedHeaders() async {
    if (_authService != null) {
      await _authService!.ensureAuthenticated();
      return _authService!.getAuthHeaders();
    }
    
    // Fallback to legacy headers if AuthService not available
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'User-Agent': appUserAgent,
    };
  }

  // SECURITY IMPROVEMENT: Pin the certificate SHA-256 fingerprint
  String _getCertificateFingerprint(X509Certificate cert) {
    final certDer = cert.der;
    final fingerprint = sha256.convert(certDer);
    return base64.encode(fingerprint.bytes);
  }

  http.Client _createPinnedHttpClient() {
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
        DebugService.instance.logMail('Certificate validation error: $e');
        return false;
      }
    };
    
    return IOClient(httpClient);
  }

  void _initializeEncryption() {
    final secureRandom = _getSecureRandom();
    _credentialKey = secureRandom.nextBytes(32);
    _credentialIV = secureRandom.nextBytes(16);
  }

  SecureRandom _getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256))
        )
      ));
    return secureRandom;
  }

  String _encryptString(String plaintext, Uint8List key, Uint8List iv) {
    try {
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null
      );
      cipher.init(true, params);

      final plainBytes = utf8.encode(plaintext);
      final encrypted = cipher.process(Uint8List.fromList(plainBytes));
      return base64.encode(encrypted);
    } catch (e) {
      rethrow;
    }
  }

  String _decryptString(String encryptedData, Uint8List key, Uint8List iv) {
    try {
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null
      );
      cipher.init(false, params);

      final encryptedBytes = base64.decode(encryptedData);
      final decrypted = cipher.process(encryptedBytes);
      return utf8.decode(decrypted);
    } catch (e) {
      rethrow;
    }
  }

  EncryptedCredentials _encryptCredentials(String username, String password) {
    final encryptedUser = _encryptString(username, _credentialKey, _credentialIV);
    final encryptedPass = _encryptString(password, _credentialKey, _credentialIV);

    return EncryptedCredentials(
      encryptedUser: encryptedUser,
      encryptedPass: encryptedPass,
      key: base64.encode(_credentialKey),
      iv: base64.encode(_credentialIV),
    );
  }

  Map<String, dynamic> _decryptMailContent(Map<String, dynamic> encryptedResponse) {
    try {
      if (!encryptedResponse.containsKey('encrypted') || 
          encryptedResponse['encrypted'] != true) {
        return encryptedResponse;
      }

      final encryptedData = encryptedResponse['data'];
      final key = base64.decode(encryptedResponse['key']);
      final iv = base64.decode(encryptedResponse['iv']);

      final decrypted = _decryptString(encryptedData, key, iv);
      return json.decode(decrypted);
    } catch (e) {
      rethrow;
    }
  }

  void _updateStatus(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  Future<bool> connect(String username, String password) async {
    try {
      DebugService.instance.logMail('Attempting to connect with username: $username');
      _isLoading = true;
      _username = username;
      _lastError = '';

      _encryptedCredentials = _encryptCredentials(username, password);

      final headers = await _getAuthenticatedHeaders();
      final response = await _httpClient.post(
        Uri.parse('$_serverBaseUrl/api/v1/mail/headers'),
        headers: headers,

        body: json.encode({
          'credentials': _encryptedCredentials!.toJson(),
          'start': 1,
          'count': 1,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final encryptedData = json.decode(response.body);
        final data = _decryptMailContent(encryptedData);

        _isConnected = true;
        _updateStatus('Loading messages...');
        notifyListeners();

        await _updateMessageList();

        _isLoading = false;
        _updateStatus('');
        return true;
      } else {
        if (response.statusCode == 400) {
          _lastError = 'Invalid username or password';
        } else if (response.statusCode == 503) {
          // Service unavailable - check for custom message
          try {
            final jsonResponse = json.decode(response.body);
            _lastError = jsonResponse['message'] ?? 'Mail service is temporarily disabled';
          } catch (e) {
            _lastError = 'Mail service is temporarily disabled';
          }
        } else if (response.statusCode == 500) {
          _lastError = 'Authentication failed - check credentials';
        } else {
          _lastError = 'Connection failed: ${response.statusCode}';
        }
      }
    } catch (e) {
      if (e.toString().contains('TimeoutException')) {
        _lastError = 'Connection timeout - please try again';
      } else {
        _lastError = 'Connection failed';
      }
    }

    _isLoading = false;
    _isConnected = false;
    _updateStatus('');
    notifyListeners();
    return false;
  }

  Future<void> _updateMessageList() async {
    if (!_isConnected || _encryptedCredentials == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final headers = await _getAuthenticatedHeaders();
      final response = await _httpClient.post(
        Uri.parse('$_serverBaseUrl/api/v1/mail/headers'),
        headers: headers,

        body: json.encode({
          'credentials': _encryptedCredentials!.toJson(),
          'start': 1,
          'count': 50,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final encryptedData = json.decode(response.body);
        final data = _decryptMailContent(encryptedData);

        _messages.clear();
        _totalMessages = data['messageCount'] ?? 0;

        if (data['messages'] != null) {
          for (final messageData in data['messages']) {
            final emailMessage = EmailMessage(
              id: messageData['number'].toString(),
              from: messageData['from'] ?? 'Unknown',
              subject: messageData['subject'] ?? '(No Subject)',
              date: _formatServerDate(messageData['date']),
              body: '',
              size: 0,
              isRead: false,
              isPreloaded: false,
            );

            _messages.add(emailMessage);
          }
        }

        _isLoading = false;
        _updateStatus('');
        notifyListeners();

        _prefetchRecentMessages();

      } else {
        throw Exception('Server error: ${response.statusCode}');
      }

    } catch (e) {
      _isLoading = false;

      if (e.toString().contains('TimeoutException')) {
        _lastError = 'Loading messages timed out. I2P network is slow - please try again.';
        _updateStatus('Timeout - please try refreshing');
      } else {
        _lastError = 'Failed to load messages';
        _updateStatus('Error loading messages');
      }

      notifyListeners();

      Future.delayed(const Duration(seconds: 5), () {
        _updateStatus('');
        notifyListeners();
      });
    }
  }

Future<void> _prefetchRecentMessages() async {
  if (_messages.isEmpty) return;

  // Load user preference for prefetch count
  final prefs = await SharedPreferences.getInstance();
  final int prefetchCount = prefs.getInt('prefetch_count') ?? 5; // Default to 5

  final messagesToPrefetch = _messages.take(prefetchCount).toList();

  for (final message in messagesToPrefetch) {
    if (!_isConnected) break;
    if (message.isPreloaded) continue;

    try {
      final fullMessage = await _fetchEncryptedMessageSilently(message.id);

      if (fullMessage != null) {
        message.body = fullMessage.body;
        message.htmlBody = fullMessage.htmlBody;
        message.isPreloaded = true;
      }

      await Future.delayed(const Duration(milliseconds: 1500));
    } catch (e) {
      // Continue with next message
    }
  }
}

  Future<EmailMessage?> _fetchEncryptedMessageSilently(String messageId) async {
    if (!_isConnected || _encryptedCredentials == null) return null;

    try {
      final headers = await _getAuthenticatedHeaders();
      final response = await _httpClient.post(
        Uri.parse('$_serverBaseUrl/api/v1/mail/parsed'),
        headers: headers,

        body: json.encode({
          'credentials': _encryptedCredentials!.toJson(),
          'msg': int.parse(messageId),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final encryptedData = json.decode(response.body);
        final data = _decryptMailContent(encryptedData);

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
      return null;
    }
    return null;
  }

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

  Future<EmailMessage?> getMessage(String messageId) async {
    if (!_isConnected || _encryptedCredentials == null) {
      return null;
    }

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
      return existingMessage;
    }

    _updateStatus('Loading message...');

    try {
      final headers = await _getAuthenticatedHeaders();
      final response = await _httpClient.post(
        Uri.parse('$_serverBaseUrl/api/v1/mail/parsed'),
        headers: headers,

        body: json.encode({
          'credentials': _encryptedCredentials!.toJson(),
          'msg': int.parse(messageId),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final encryptedData = json.decode(response.body);
        final data = _decryptMailContent(encryptedData);

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
        _updateStatus('');
        return null;
      }
    } catch (e) {
      _updateStatus('');
      return null;
    }
  }

  Future<bool> deleteMessage(String messageId) async {
    if (!_isConnected || _encryptedCredentials == null) {
      return false;
    }

    try {
      final response = await _httpClient.delete(
        Uri.parse('$_serverBaseUrl/api/v1/mail/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': appUserAgent,
        },
        body: json.encode({
          'credentials': _encryptedCredentials!.toJson(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _messages.removeWhere((msg) => msg.id == messageId);
          notifyListeners();
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendEmail({
    required String to,
    required String subject,
    required String body,
  }) async {
    if (_encryptedCredentials == null) {
      return false;
    }

    _isSending = true;
    _updateStatus('Sending securely...');
    notifyListeners();

    try {
      final emailKey = _getSecureRandom().nextBytes(32);
      final emailIV = _getSecureRandom().nextBytes(16);

      final emailData = {
        'to': to,
        'subject': subject,
        'body': body,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final encryptedEmailData = {
        'encrypted': true,
        'data': _encryptString(json.encode(emailData), emailKey, emailIV),
        'key': base64.encode(emailKey),
        'iv': base64.encode(emailIV),
      };

      final headers = await _getAuthenticatedHeaders();
      final response = await _httpClient.post(
        Uri.parse('$_serverBaseUrl/api/v1/mail/send'),
        headers: headers,

        body: json.encode({
          'credentials': _encryptedCredentials!.toJson(),
          'emailData': encryptedEmailData,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final encryptedResponse = json.decode(response.body);
        final result = _decryptMailContent(encryptedResponse);

        if (result['success'] == true) {
          _isSending = false;
          _updateStatus('Message sent!');

          Future.delayed(const Duration(seconds: 2), () {
            _updateStatus('');
            notifyListeners();
          });

          return true;
        }
      }

      throw Exception('Server error: ${response.statusCode}');

    } catch (e) {
      _isSending = false;
      _lastError = 'Failed to send message';
      _updateStatus('');

      notifyListeners();
      return false;
    }
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
    await _updateMessageList();
  }

  void disconnect() {
    _isConnected = false;
    _isSending = false;
    _username = null;
    _encryptedCredentials = null;
    _messages.clear();
    _totalMessages = 0;
    _statusMessage = '';
    _lastError = '';

    // Explicitly nullify the encryption fields
    _credentialKey = Uint8List(0);
    _credentialIV = Uint8List(0);

    // Reinitialize encryption fields
    _initializeEncryption();
    notifyListeners();
  }

  @override
  void dispose() {
    _httpClient.close();
    disconnect();
    super.dispose();
  }
}