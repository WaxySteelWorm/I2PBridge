import 'dart:convert';
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


