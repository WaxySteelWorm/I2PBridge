import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService extends ChangeNotifier {
  static const String _baseUrl = 'https://bridge.stormycloud.org';
  static const String _tokenKey = 'jwt_token';
  static const String _expiryKey = 'token_expiry';
  
  // Secure storage for sensitive data
  static const _secureStorage = FlutterSecureStorage();
  
  String? _jwtToken;
  DateTime? _tokenExpiry;
  bool _isAuthenticated = false;
  
  // API key loaded from environment or secure storage
  String? _apiKey;
  
  bool get isAuthenticated => _isAuthenticated;
  String? get token => _jwtToken;
  
  AuthService() {
    _loadApiKey();
    _initializeAuth();
  }
  
  /// Initialize authentication on startup
  Future<void> _initializeAuth() async {
    // Check if API key has changed
    final prefs = await SharedPreferences.getInstance();
    final storedApiKeyHash = prefs.getString('api_key_hash');
    final currentApiKeyHash = _apiKey != null ? _apiKey.hashCode.toString() : null;
    
    if (storedApiKeyHash != null && currentApiKeyHash != null && storedApiKeyHash != currentApiKeyHash) {
      debugPrint('⚠️ AUTH: API key has changed - clearing old token');
      await _clearStoredToken();
    }
    
    // Store current API key hash
    if (currentApiKeyHash != null) {
      await prefs.setString('api_key_hash', currentApiKeyHash);
    }
    
    await _loadStoredToken();
    
    // Small delay to ensure API key is loaded properly
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Try to authenticate immediately if we don't have a valid token
    if (!_isTokenValid() && _apiKey != null && _apiKey!.isNotEmpty) {
      try {
        debugPrint('🔄 AUTH: Starting initial authentication...');
        await authenticate();
      } catch (e) {
        debugPrint('🔄 AUTH: Initial authentication failed, will retry on first request: $e');
      }
    } else if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('⚠️ AUTH: No API key available for initial authentication');
    }
  }
  
  /// Load API key from environment variables (compile-time)
  void _loadApiKey() {
    try {
      // API key should be provided at build time via --dart-define
      _apiKey = const String.fromEnvironment('I2P_BRIDGE_API_KEY');
      
      if (_apiKey == null || _apiKey!.isEmpty) {
        debugPrint('⚠️ AUTH: API key not found in environment variables');
        debugPrint('   Build with: flutter run --dart-define=I2P_BRIDGE_API_KEY=your-key');
      } else {
        debugPrint('✅ AUTH: API key loaded successfully');
      }
    } catch (e) {
      debugPrint('❌ AUTH: Error loading API key: $e');
    }
  }
  
  /// Load stored JWT token from secure storage
  Future<void> _loadStoredToken() async {
    try {
      // Use secure storage for JWT token
      _jwtToken = await _secureStorage.read(key: _tokenKey);
      
      // Use SharedPreferences only for non-sensitive expiry time
      final prefs = await SharedPreferences.getInstance();
      final expiryMs = prefs.getInt(_expiryKey);
      
      if (expiryMs != null) {
        _tokenExpiry = DateTime.fromMillisecondsSinceEpoch(expiryMs);
      }
      
      if (_jwtToken != null && _isTokenValid()) {
        _isAuthenticated = true;
        debugPrint('✅ AUTH: Valid token loaded from storage');
      } else {
        await _clearStoredToken();
        debugPrint('🔄 AUTH: Stored token expired or invalid');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ AUTH: Error loading stored token: $e');
      await _clearStoredToken();
    }
  }
  
  /// Store JWT token securely
  Future<void> _storeToken(String token, DateTime expiry) async {
    try {
      // Store token in secure storage
      await _secureStorage.write(key: _tokenKey, value: token);
      
      // Store only expiry in SharedPreferences (non-sensitive)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_expiryKey, expiry.millisecondsSinceEpoch);
      
      _jwtToken = token;
      _tokenExpiry = expiry;
      _isAuthenticated = true;
      
      debugPrint('✅ AUTH: Token stored securely');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ AUTH: Error storing token: $e');
      throw Exception('Failed to store authentication token');
    }
  }
  
  /// Clear stored authentication data
  Future<void> _clearStoredToken() async {
    try {
      // Clear token from secure storage
      await _secureStorage.delete(key: _tokenKey);
      
      // Clear expiry from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_expiryKey);
      
      _jwtToken = null;
      _tokenExpiry = null;
      _isAuthenticated = false;
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ AUTH: Error clearing stored token: $e');
    }
  }
  
  /// Check if current token is valid (not expired)
  bool _isTokenValid() {
    return _jwtToken != null && 
           _tokenExpiry != null && 
           DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5))); // 5min buffer
  }
  
  /// Authenticate with the server and get JWT token
  Future<bool> authenticate() async {
    debugPrint('🔄 AUTH: Starting authentication...');
    debugPrint('🔄 AUTH: API key available: ${_apiKey != null}');
    
    if (_apiKey == null || _apiKey!.isEmpty) {
      debugPrint('❌ AUTH: Cannot authenticate - API key not available');
      throw Exception('API key not configured. Please rebuild app with API key.');
    }
    
    // If we have a valid token, no need to re-authenticate
    if (_isTokenValid()) {
      debugPrint('✅ AUTH: Using existing valid token');
      return true;
    }
    
    try {
      debugPrint('🔄 AUTH: Requesting new JWT token from server...');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/token'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': _getUserAgent(),
        },
        body: json.encode({
          'apiKey': _apiKey,
        }),
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('🔄 AUTH: Server responded with status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final token = data['token'] as String;
        final expiresIn = data['expiresIn'] as String; // e.g., "24h"
        
        // Parse expiry time (assuming format like "24h")
        final hours = int.parse(expiresIn.replaceAll('h', ''));
        final expiry = DateTime.now().add(Duration(hours: hours));
        
        await _storeToken(token, expiry);
        
        debugPrint('✅ AUTH: Authentication successful, token expires in $expiresIn');
        return true;
      } else {
        debugPrint('❌ AUTH: Authentication failed with status ${response.statusCode}');
        debugPrint('❌ AUTH: Response body: ${response.body}');
        
        // Clear any existing invalid token
        await _clearStoredToken();
        
        if (response.statusCode == 401) {
          // Try to parse the server's error message
          try {
            final responseBody = json.decode(response.body);
            final error = responseBody['error'] ?? 'Invalid API key';
            final action = responseBody['action'] ?? 'Please check your API key in settings';
            throw Exception('$error. $action');
          } catch (e) {
            throw Exception('Invalid API key. Please check your API key in settings and try again.');
          }
        } else if (response.statusCode == 403) {
          // Try to parse the server's error message
          try {
            final responseBody = json.decode(response.body);
            final error = responseBody['error'] ?? 'Authentication failed';
            final action = responseBody['action'] ?? 'Please update your app or check your API key';
            throw Exception('$error. $action');
          } catch (e) {
            throw Exception('Authentication failed. Your session may have expired or your API key may be disabled.');
          }
        } else if (response.statusCode == 429) {
          throw Exception('Rate limit exceeded. Please try again later.');
        } else {
          throw Exception('Authentication failed (${response.statusCode}). Please check your API key or try again later.');
        }
      }
    } on SocketException catch (e) {
      debugPrint('❌ AUTH: Network error during authentication: $e');
      throw Exception('Network error. Please check your connection.');
    } on TimeoutException catch (e) {
      debugPrint('❌ AUTH: Request timeout during authentication: $e');
      throw Exception('Request timeout. Please try again.');
    } catch (e) {
      debugPrint('❌ AUTH: Unexpected error during authentication: $e');
      rethrow;
    }
  }
  
  /// Ensure user is authenticated (for backward compatibility)
  Future<void> ensureAuthenticated() async {
    if (!_isTokenValid()) {
      debugPrint('🔄 AUTH: Token invalid or expired, re-authenticating...');
      await authenticate();
    }
    
    if (_jwtToken == null) {
      throw Exception('Authentication required');
    }
  }
  
  /// Get authentication headers for API requests  
  Map<String, String> getAuthHeaders() {
    if (_jwtToken == null) {
      throw Exception('Authentication required - call ensureAuthenticated() first');
    }
    
    return {
      'Authorization': 'Bearer $_jwtToken',
      'User-Agent': _getUserAgent(),
    };
  }
  
  /// Get authentication headers for API requests (async version)
  Future<Map<String, String>> getAuthHeadersAsync() async {
    // Ensure we have a valid token
    await ensureAuthenticated();
    return getAuthHeaders();
  }
  
  /// Get current authentication status
  Future<bool> checkAuthStatus() async {
    if (_isTokenValid()) {
      return true;
    }
    
    try {
      return await authenticate();
    } catch (e) {
      debugPrint('❌ AUTH: Failed to authenticate: $e');
      return false;
    }
  }
  
  /// Logout and clear authentication data
  Future<void> logout() async {
    debugPrint('🔄 AUTH: Logging out...');
    await _clearStoredToken();
    debugPrint('✅ AUTH: Logged out successfully');
  }
  
  /// Get user agent string for API requests
  String _getUserAgent() {
    String platform = 'Unknown';
    if (Platform.isIOS) {
      platform = 'iOS';
    } else if (Platform.isAndroid) {
      platform = 'Android';
    } else if (Platform.isMacOS) {
      platform = 'macOS';
    } else if (Platform.isWindows) {
      platform = 'Windows';
    } else if (Platform.isLinux) {
      platform = 'Linux';
    }
    
    return 'I2PBridge/1.0.0 ($platform; Flutter)';
  }
  
  /// Handle authentication errors (e.g., 401 responses)
  Future<void> handleAuthError({Map<String, dynamic>? errorResponse}) async {
    debugPrint('🔄 AUTH: Handling authentication error...');
    
    // Check if this is a TOKEN_OUTDATED error
    if (errorResponse != null && errorResponse['code'] == 'TOKEN_OUTDATED') {
      debugPrint('⚠️ AUTH: Token outdated - clearing old token and re-authenticating');
    }
    
    await _clearStoredToken();
    
    // Try to re-authenticate automatically
    try {
      await authenticate();
    } catch (e) {
      debugPrint('❌ AUTH: Re-authentication failed: $e');
      rethrow;
    }
  }
  
  /// Force clear cached token and re-authenticate
  Future<void> forceReauthenticate() async {
    debugPrint('🔄 AUTH: Force re-authentication requested');
    await _clearStoredToken();
    await authenticate();
  }
}

