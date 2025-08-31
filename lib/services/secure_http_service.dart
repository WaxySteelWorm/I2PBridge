import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:crypto/crypto.dart';

/// Secure HTTP client service with enhanced security validation
class SecureHttpService {
  static SecureHttpService? _instance;
  late http.Client _client;
  
  static const String _bridgeHost = 'bridge.stormycloud.org';
  static const int _bridgePort = 443;
  
  // Security configuration - uses standard SSL/TLS + enhanced validation
  static const bool _enableEnhancedSecurity = bool.fromEnvironment(
    'ENABLE_ENHANCED_SECURITY', 
    defaultValue: true  // Enhanced security enabled by default
  );
  
  SecureHttpService._internal();
  
  static SecureHttpService get instance {
    _instance ??= SecureHttpService._internal();
    return _instance!;
  }
  
  /// Initialize the secure HTTP client with enhanced security
  Future<void> initialize() async {
    try {
      if (_enableEnhancedSecurity) {
        // Create HTTP client with enhanced security validation
        _client = await _createSecureClient();
        debugPrint('✅ SECURITY: Secure HTTP client initialized with ENHANCED SECURITY');
        debugPrint('   - Standard SSL/TLS validation + enhanced checks');
        debugPrint('   - Domain validation, timeout controls, secure headers');
      } else {
        // Use standard HTTP client
        _client = http.Client();
        debugPrint('✅ SECURITY: Using standard HTTP client (enhanced security DISABLED)');
        debugPrint('   - Standard SSL/TLS validation only');
      }
    } catch (e) {
      debugPrint('❌ SECURITY: Failed to initialize secure HTTP client: $e');
      // Fallback to default client
      _client = http.Client();
    }
  }
  
  /// Create HTTP client with enhanced security validation
  Future<http.Client> _createSecureClient() async {
    // Use the default system SecurityContext which includes trusted CA certificates
    final httpClient = HttpClient();
    
    // Enhanced security settings
    httpClient.connectionTimeout = const Duration(seconds: 30);
    httpClient.idleTimeout = const Duration(seconds: 60);
    
    // Use standard certificate validation with system certificate store
    // This automatically handles certificate rotation and uses trusted CAs
    
    return IOClient(httpClient);
  }
  
  /// Validate request security before sending
  bool _validateRequest(Uri uri, Map<String, String>? headers) {
    try {
      // Validate target host
      if (uri.host != _bridgeHost) {
        debugPrint('❌ SECURITY: Request to unauthorized host: ${uri.host}');
        return false;
      }
      
      // Validate port
      if (uri.port != _bridgePort && uri.port != 443) {
        debugPrint('❌ SECURITY: Request to unauthorized port: ${uri.port}');
        return false;
      }
      
      // Validate protocol
      if (uri.scheme != 'https') {
        debugPrint('❌ SECURITY: Non-HTTPS request blocked: ${uri.scheme}');
        return false;
      }
      
      // Validate headers contain our user agent
      if (headers != null && !headers.containsKey('User-Agent')) {
        debugPrint('⚠️ SECURITY: Request without User-Agent header');
      }
      
      return true;
    } catch (e) {
      debugPrint('❌ SECURITY: Request validation error: $e');
      return false;
    }
  }
  
  /// Perform GET request with enhanced security validation
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    // Validate request security
    if (_enableEnhancedSecurity && !_validateRequest(url, headers)) {
      throw Exception('Security validation failed for GET request');
    }
    
    try {
      // Add security headers
      final secureHeaders = _addSecurityHeaders(headers);
      
      return await _client.get(
        url,
        headers: secureHeaders,
      ).timeout(timeout ?? const Duration(seconds: 30));
    } catch (e) {
      debugPrint('❌ SECURITY: Secure GET request failed: $e');
      rethrow;
    }
  }
  
  /// Perform POST request with enhanced security validation
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    // Validate request security
    if (_enableEnhancedSecurity && !_validateRequest(url, headers)) {
      throw Exception('Security validation failed for POST request');
    }
    
    try {
      // Add security headers
      final secureHeaders = _addSecurityHeaders(headers);
      
      return await _client.post(
        url,
        headers: secureHeaders,
        body: body,
      ).timeout(timeout ?? const Duration(seconds: 30));
    } catch (e) {
      debugPrint('❌ SECURITY: Secure POST request failed: $e');
      rethrow;
    }
  }
  
  /// Add security headers to requests
  Map<String, String> _addSecurityHeaders(Map<String, String>? originalHeaders) {
    final headers = Map<String, String>.from(originalHeaders ?? {});
    
    // Ensure User-Agent is present
    if (!headers.containsKey('User-Agent')) {
      headers['User-Agent'] = 'I2PBridge/1.0.0 (Flutter)';
    }
    
    // Add security-focused headers
    headers['X-Requested-With'] = 'I2PBridge';
    headers['DNT'] = '1'; // Do Not Track
    
    return headers;
  }
  
  /// Test secure connection to bridge server
  Future<bool> testConnection() async {
    try {
      // Perform a test request to verify secure connection is working
      final testUri = Uri.parse('https://$_bridgeHost/api/v1/debug');
      final response = await get(
        testUri,
        headers: {'User-Agent': 'I2PBridge/1.0.0 (Security-Test)'},
        timeout: const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200 || response.statusCode == 401) {
        // 200 or 401 means we connected successfully (401 is expected without auth)
        debugPrint('✅ SECURITY: Bridge server connection successful');
        return true;
      } else {
        debugPrint('❌ SECURITY: Bridge server connection failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ SECURITY: Bridge server connection error: $e');
      return false;
    }
  }
  
  /// Dispose of the HTTP client
  void dispose() {
    _client.close();
  }
  
  /// Get the underlying HTTP client (for advanced use cases)
  http.Client get client => _client;
}

/// Extension for security configuration and monitoring
extension SecureHttpServiceConfig on SecureHttpService {
  /// Check if enhanced security is enabled
  static bool get isEnhancedSecurityEnabled => SecureHttpService._enableEnhancedSecurity;
  
  /// Get configured bridge host
  static String get bridgeHost => SecureHttpService._bridgeHost;
  
  /// Get security configuration summary
  static Map<String, dynamic> getSecurityStatus() {
    return {
      'enhanced_security': SecureHttpService._enableEnhancedSecurity,
      'bridge_host': SecureHttpService._bridgeHost,
      'bridge_port': SecureHttpService._bridgePort,
      'security_approach': 'Standard SSL/TLS + Enhanced Validation',
      'maintenance_required': false, // No certificate updates needed!
      'certificate_rotation_support': true,
    };
  }
}