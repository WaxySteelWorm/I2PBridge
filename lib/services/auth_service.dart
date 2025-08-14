import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService extends ChangeNotifier {
  static const String _baseUrl = 'https://bridge.stormycloud.org';
  static const String _tokenKey = 'jwt_token';
  static const String _expiryKey = 'token_expiry';
  
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
        debugPrint('✅ AUTH: API key loaded successfully (${_apiKey!.length} chars)');
      }
    } catch (e) {
      debugPrint('❌ AUTH: Error loading API key: $e');
    }
  }
  
  /// Load stored JWT token from secure storage
  Future<void> _loadStoredToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _jwtToken = prefs.getString(_tokenKey);
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
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
    debugPrint('🔄 AUTH: === Authentication Debug ===');
    debugPrint('🔄 AUTH: API key available: ${_apiKey != null}');
    debugPrint('🔄 AUTH: API key length: ${_apiKey?.length ?? 0}');
    debugPrint('🔄 AUTH: API key starts with: ${_apiKey?.substring(0, 8) ?? 'null'}...');
    
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
      debugPrint('🔄 AUTH: Requesting new token from server...');
      debugPrint('🔄 AUTH: Sending request to: $_baseUrl/auth/token');
      
      final requestBody = {'apiKey': _apiKey};
      debugPrint('🔄 AUTH: Request body API key length: ${_apiKey!.length}');
      
      final response = await http.post(
        Uri.parse('$_baseUrl/auth/token'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'I2PBridge/1.0.0 (Flutter)',
        },
        body: jsonEncode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      debugPrint('🔄 AUTH: Response status: ${response.statusCode}');
      debugPrint('🔄 AUTH: Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String;
        final expiresIn = data['expiresIn'] as String;
        
        // Parse expiry (assumes format like "24h")
        final expiryDuration = _parseExpiryDuration(expiresIn);
        final expiry = DateTime.now().add(expiryDuration);
        
        await _storeToken(token, expiry);
        
        debugPrint('✅ AUTH: Authentication successful');
        return true;
      } else {
        try {
          final errorData = jsonDecode(response.body);
          debugPrint('❌ AUTH: Authentication failed: ${errorData['error']}');
          debugPrint('❌ AUTH: Error code: ${errorData['code']}');
          throw Exception('Authentication failed: ${errorData['error']}');
        } catch (e) {
          debugPrint('❌ AUTH: Authentication failed with status ${response.statusCode}');
          debugPrint('❌ AUTH: Raw response: ${response.body}');
          throw Exception('Authentication failed with status ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('❌ AUTH: Authentication error: $e');
      await _clearStoredToken();
      rethrow;
    }
  }
  
  /// Parse expiry duration string (e.g., "24h" -> Duration(hours: 24))
  Duration _parseExpiryDuration(String expiresIn) {
    final regex = RegExp(r'(\d+)([hm])');
    final match = regex.firstMatch(expiresIn);
    
    if (match != null) {
      final value = int.parse(match.group(1)!);
      final unit = match.group(2)!;
      
      switch (unit) {
        case 'h':
          return Duration(hours: value);
        case 'm':
          return Duration(minutes: value);
      }
    }
    
    // Default to 23 hours if parsing fails
    return const Duration(hours: 23);
  }
  
  /// Get HTTP headers with authentication
  Map<String, String> getAuthHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'I2PBridge/1.0.0 (Flutter)',
    };
    
    if (_jwtToken != null) {
      headers['Authorization'] = 'Bearer $_jwtToken';
    }
    
    return headers;
  }
  
  /// Ensure authentication before making API calls
  Future<void> ensureAuthenticated() async {
    // Wait a bit for initialization if still in progress
    int retries = 0;
    while (_apiKey == null && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }
    
    if (!_isTokenValid()) {
      debugPrint('🔄 AUTH: Token invalid, re-authenticating...');
      await authenticate();
    }
  }
  
  /// Logout and clear stored tokens
  Future<void> logout() async {
    debugPrint('🔄 AUTH: Logging out...');
    await _clearStoredToken();
    debugPrint('✅ AUTH: Logout complete');
  }
  
  /// Handle authentication errors (token expired, etc.)
  Future<void> handleAuthError() async {
    debugPrint('🔄 AUTH: Handling authentication error...');
    await _clearStoredToken();
    
    // Try to re-authenticate automatically
    try {
      await authenticate();
    } catch (e) {
      debugPrint('❌ AUTH: Re-authentication failed: $e');
      rethrow;
    }
  }
}
=======
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// AuthService: obtains and caches JWT tokens for bridge API
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const String _bridgeBase = 'https://bridge.stormycloud.org';
  // Provide API key at build time: --dart-define=I2P_BRIDGE_API_KEY=... (min 32 chars)
  static const String _apiKey = String.fromEnvironment('I2P_BRIDGE_API_KEY');

  String? _token;
  DateTime? _expiry;
  bool _initializing = false;

  Future<void> initialize() async {
    if (_token != null && _expiry != null && DateTime.now().isBefore(_expiry!)) return;
    await ensureToken();
  }

  Future<void> ensureToken() async {
    if (_initializing) return;
    if (_token != null && _expiry != null && DateTime.now().isBefore(_expiry!)) return;

    _initializing = true;
    try {
      if (_apiKey.isEmpty) {
        debugPrint('❌ AUTH: Missing I2P_BRIDGE_API_KEY. Pass with --dart-define.');
        return;
      }
      final resp = await http.post(
        Uri.parse('$_bridgeBase/auth/token'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'I2PBridge/1.0.0 (Mobile; Flutter)'
        },
        body: json.encode({'apiKey': _apiKey}),
      ).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        _token = data['token']?.toString();
        // expiresIn is '24h' — set expiry 23h to be safe
        _expiry = DateTime.now().add(const Duration(hours: 23));
        debugPrint('✅ AUTH: Token acquired');
      } else {
        debugPrint('❌ AUTH: Failed to get token: ${resp.statusCode} ${resp.body}');
      }
    } catch (e) {
      debugPrint('❌ AUTH: Token request error: $e');
    } finally {
      _initializing = false;
    }
  }

  Future<Map<String, String>> authHeader() async {
    await ensureToken();
    if (_token == null) return {};
    return {'Authorization': 'Bearer $_token'};
  }

  String? get token => _token;
}
