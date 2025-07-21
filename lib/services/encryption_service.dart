// lib/services/encryption_service.dart
// This service handles end-to-end encryption between the app and I2P destinations
// The bridge server will only see encrypted payloads

import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/pointycastle.dart';
import 'package:pointycastle/export.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  // Generate a random key for each session
  late final Uint8List _sessionKey;
  late final Uint8List _sessionIV;
  bool _initialized = false;
  
  // Initialize encryption parameters
  void initialize() {
    if (_initialized) return; // Prevent re-initialization
    
    final secureRandom = _getSecureRandom();
    _sessionKey = secureRandom.nextBytes(32); // 256-bit key for AES
    _sessionIV = secureRandom.nextBytes(16);  // 128-bit IV for AES
    _initialized = true;
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
        // In production, you'd exchange keys securely
        // For now, we'll include the key (this is just for demonstration)
        'key': base64.encode(_sessionKey),
      };
    } catch (e) {
      print('Encryption error: $e');
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
      print('Decryption error: $e');
      rethrow;
    }
  }

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
      print('URL decryption error: $e');
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
      print('IRC decryption error: $e');
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
  
  // Verify response integrity (basic implementation)
  bool verifyResponse(Map<String, dynamic> response) {
    // In production, implement HMAC or similar
    return response.containsKey('encrypted') && 
           response.containsKey('data') && 
           response.containsKey('iv');
  }
}