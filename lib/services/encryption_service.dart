// lib/services/encryption_service.dart
// Enhanced encryption service with mail support

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';
import 'debug_service.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Generate a random key for each session
  late final Uint8List _sessionKey;
  late final Uint8List _sessionIV;
  bool _initialized = false;
  
  // Mail-specific encryption keys (derived from session key)
  late final Uint8List _mailKey;
  late final Uint8List _mailIV;
  
  // Initialize encryption parameters
  void initialize() {
    if (_initialized) return; // Prevent re-initialization
    
    final secureRandom = _getSecureRandom();
    _sessionKey = secureRandom.nextBytes(32); // 256-bit key for AES
    _sessionIV = secureRandom.nextBytes(16);  // 128-bit IV for AES
    
    // Derive mail-specific keys from session key
    _mailKey = _deriveKey(_sessionKey, 'mail_key');
    _mailIV = _deriveKey(_sessionKey, 'mail_iv').sublist(0, 16);
    
    _initialized = true;
  }

  // Derive a key from the master session key using a context string
  Uint8List _deriveKey(Uint8List masterKey, String context) {
    final contextBytes = utf8.encode(context);
    final combined = Uint8List.fromList([...masterKey, ...contextBytes]);
    
    final digest = SHA256Digest();
    return digest.process(combined);
  }

  // Get a cryptographically secure random number generator
  SecureRandom _getSecureRandom() {
    final secureRandom = SecureRandom('Fortuna')
      ..seed(KeyParameter(
        Uint8List.fromList(
          List.generate(32, (_) => Random.secure().nextInt(256))
        )
      ));
    return secureRandom;
  }

  // Encrypt data before sending to bridge
  Map<String, dynamic> encryptRequest(Map<String, dynamic> request) {
    try {
      // Convert request to JSON string
      final jsonString = json.encode(request);
      final plaintext = utf8.encode(jsonString);
      
      // Setup AES cipher
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(_sessionKey), _sessionIV),
        null
      );
      cipher.init(true, params); // true for encryption
      
      // Encrypt the data
      final encrypted = cipher.process(Uint8List.fromList(plaintext));
      
      // Create encrypted payload
      return {
        'encrypted': true,
        'data': base64.encode(encrypted),
        'iv': base64.encode(_sessionIV),
        'key': base64.encode(_sessionKey),
      };
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'Encryption error: $e');
      rethrow;
    }
  }

  // Decrypt response from bridge
  String decryptResponse(Map<String, dynamic> response) {
    try {
      if (!response.containsKey('encrypted') || !response['encrypted']) {
        // Response is not encrypted, return as-is
        return json.encode(response);
      }
      
      final encryptedData = base64.decode(response['data']);
      final iv = base64.decode(response['iv']);
      final key = base64.decode(response['key']);
      
      // Setup AES cipher for decryption
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null
      );
      cipher.init(false, params); // false for decryption
      
      // Decrypt the data
      final decrypted = cipher.process(encryptedData);
      
      // Convert back to string
      return utf8.decode(decrypted);
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'Decryption error: $e');
      rethrow;
    }
  }

  // =================================================================
  // MAIL-SPECIFIC ENCRYPTION FUNCTIONS
  // =================================================================

  // Encrypt mail credentials
  Map<String, String> encryptMailCredentials(String username, String password) {
    try {
      if (!_initialized) initialize();
      
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(_mailKey), _mailIV),
        null
      );
      cipher.init(true, params);
      
      // Encrypt username
      final usernameBytes = utf8.encode(username);
      final encryptedUsername = cipher.process(Uint8List.fromList(usernameBytes));
      
      // Reset cipher for password
      cipher.reset();
      cipher.init(true, params);
      final passwordBytes = utf8.encode(password);
      final encryptedPassword = cipher.process(Uint8List.fromList(passwordBytes));
      
      return {
        'user': base64.encode(encryptedUsername),
        'pass': base64.encode(encryptedPassword),
        'key': base64.encode(_mailKey),
        'iv': base64.encode(_mailIV),
      };
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'Mail credential encryption error: $e');
      rethrow;
    }
  }

  // Encrypt mail content (body, subject)
  Map<String, dynamic> encryptMailContent({
    required String body,
    String? htmlBody,
    String? subject,
  }) {
    try {
      if (!_initialized) initialize();
      
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(_mailKey), _mailIV),
        null
      );
      
      // Encrypt body
      cipher.init(true, params);
      final bodyBytes = utf8.encode(body);
      final encryptedBody = cipher.process(Uint8List.fromList(bodyBytes));
      
      Map<String, dynamic> encrypted = {
        'body': base64.encode(encryptedBody),
        'encrypted': true,
        'key': base64.encode(_mailKey),
        'iv': base64.encode(_mailIV),
      };
      
      // Encrypt HTML body if present
      if (htmlBody != null && htmlBody.isNotEmpty) {
        cipher.reset();
        cipher.init(true, params);
        final htmlBytes = utf8.encode(htmlBody);
        final encryptedHtml = cipher.process(Uint8List.fromList(htmlBytes));
        encrypted['htmlBody'] = base64.encode(encryptedHtml);
      }
      
      // Encrypt subject if present (optional based on I2P compatibility)
      if (subject != null && subject.isNotEmpty) {
        cipher.reset();
        cipher.init(true, params);
        final subjectBytes = utf8.encode(subject);
        final encryptedSubject = cipher.process(Uint8List.fromList(subjectBytes));
        encrypted['subject'] = base64.encode(encryptedSubject);
      }
      
      return encrypted;
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'Mail content encryption error: $e');
      rethrow;
    }
  }

  // Decrypt mail content
  Map<String, String?> decryptMailContent(Map<String, dynamic> encryptedData) {
    try {
      if (!encryptedData.containsKey('encrypted') || !encryptedData['encrypted']) {
        // Not encrypted, return as-is
        return {
          'body': encryptedData['text']?.toString(),
          'htmlBody': encryptedData['html']?.toString(),
          'subject': encryptedData['subject']?.toString(),
        };
      }
      
      final key = base64.decode(encryptedData['key']);
      final iv = base64.decode(encryptedData['iv']);
      
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), iv),
        null
      );
      
      Map<String, String?> decrypted = {};
      
      // Decrypt body
      if (encryptedData.containsKey('body')) {
        cipher.init(false, params);
        final encryptedBody = base64.decode(encryptedData['body']);
        final decryptedBody = cipher.process(encryptedBody);
        decrypted['body'] = utf8.decode(decryptedBody);
      }
      
      // Decrypt HTML body
      if (encryptedData.containsKey('htmlBody')) {
        cipher.reset();
        cipher.init(false, params);
        final encryptedHtml = base64.decode(encryptedData['htmlBody']);
        final decryptedHtml = cipher.process(encryptedHtml);
        decrypted['htmlBody'] = utf8.decode(decryptedHtml);
      }
      
      // Decrypt subject
      if (encryptedData.containsKey('subject')) {
        cipher.reset();
        cipher.init(false, params);
        final encryptedSubject = base64.decode(encryptedData['subject']);
        final decryptedSubject = cipher.process(encryptedSubject);
        decrypted['subject'] = utf8.decode(decryptedSubject);
      }
      
      return decrypted;
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'Mail content decryption error: $e');
      rethrow;
    }
  }

  // Encrypt email for sending
  Map<String, dynamic> encryptOutgoingEmail({
    required String to,
    required String subject,
    required String body,
  }) {
    try {
      if (!_initialized) initialize();
      
      final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
      final params = PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(_mailKey), _mailIV),
        null
      );
      
      // Create email data structure
      final emailData = {
        'to': to,
        'subject': subject,
        'body': body,
        'timestamp': DateTime.now().toIso8601String(),
      };
      
      // Encrypt the entire email data
      cipher.init(true, params);
      final emailBytes = utf8.encode(json.encode(emailData));
      final encryptedEmail = cipher.process(Uint8List.fromList(emailBytes));
      
      return {
        'encrypted': true,
        'data': base64.encode(encryptedEmail),
        'key': base64.encode(_mailKey),
        'iv': base64.encode(_mailIV),
        'to': to, // Keep recipient in plaintext for server routing
      };
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'Outgoing email encryption error: $e');
      rethrow;
    }
  }

  // Generate session ID for mail operations
  String generateMailSessionId() {
    if (!_initialized) initialize();
    return base64.encode(_getSecureRandom().nextBytes(16));
  }

  // =================================================================
  // EXISTING FUNCTIONS (unchanged)
  // =================================================================

  // Encrypt URL for browse requests (simplified for server compatibility)
  String encryptUrl(String url) {
    // For now, use simple base64 encoding of JSON
    // In production, implement proper AES encryption here
    final data = {'url': url, 'timestamp': DateTime.now().millisecondsSinceEpoch};
    return base64.encode(utf8.encode(json.encode(data)));
  }

  // Decrypt URL from encrypted request
  String decryptUrl(String encryptedUrl) {
    try {
      final decoded = json.decode(utf8.decode(base64.decode(encryptedUrl)));
      final decrypted = decryptResponse(decoded);
      final data = json.decode(decrypted);
      return data['url'];
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'URL decryption error: $e');
      return '';
    }
  }

  // Generate a secure channel ID for WebSocket connections
  String generateChannelId() {
    final random = _getSecureRandom();
    final bytes = random.nextBytes(16);
    return base64.encode(bytes);
  }

  // Encrypt IRC message
  String encryptIrcMessage(String message) {
    final encrypted = encryptRequest({'message': message});
    return json.encode(encrypted);
  }

  // Decrypt IRC message
  String decryptIrcMessage(String encryptedMessage) {
    try {
      final decoded = json.decode(encryptedMessage);
      final decrypted = decryptResponse(decoded);
      final data = json.decode(decrypted);
      return data['message'];
    } catch (e) {
      DebugService.instance.log('ENCRYPTION', 'IRC decryption error: $e');
      return '';
    }
  }

  // Create encrypted upload request
  Map<String, dynamic> createEncryptedUpload({
    required String fileName,
    required Uint8List fileData,
    String? password,
    String? expiry,
    String? maxViews,
  }) {
    // First encrypt the file data
    final cipher = PaddedBlockCipher('AES/CBC/PKCS7');
    final params = PaddedBlockCipherParameters(
      ParametersWithIV(KeyParameter(_sessionKey), _sessionIV),
      null
    );
    cipher.init(true, params);
    
    final encryptedFile = cipher.process(fileData);
    
    // Create metadata
    final metadata = {
      'fileName': fileName,
      'password': password,
      'expiry': expiry,
      'maxViews': maxViews,
    };
    
    // Encrypt metadata separately
    final encryptedMetadata = encryptRequest(metadata);
    
    return {
      'encrypted': true,
      'file': base64.encode(encryptedFile),
      'metadata': encryptedMetadata,
    };
  }
}

// Extension to make encryption easier to use throughout the app
extension EncryptionHelpers on EncryptionService {
  // Helper to create secure HTTP headers
  Map<String, String> getSecureHeaders() {
    return {
      'X-Encryption': 'AES-256-CBC',
      'X-Channel-Id': generateChannelId(),
      'Content-Type': 'application/json',
    };
  }
  
  // Helper to create secure mail headers
  Map<String, String> getSecureMailHeaders() {
    return {
      'X-Encryption': 'AES-256-CBC',
      'X-Mail-Session': generateMailSessionId(),
      'Content-Type': 'application/json',
    };
  }
  
  // Verify response integrity (basic implementation)
  bool verifyResponse(Map<String, dynamic> response) {
    // In production, implement HMAC or similar
    return response.containsKey('encrypted') && 
           response.containsKey('data') && 
           response.containsKey('iv');
  }
}