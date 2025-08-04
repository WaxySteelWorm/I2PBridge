// Debug service for managing application debug mode and logging
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class DebugService {
  static DebugService? _instance;
  static DebugService get instance => _instance ??= DebugService._();
  
  DebugService._();
  
  bool _isDebugMode = false;
  bool _serverDebugMode = false;
  
  bool get isDebugMode => _isDebugMode || _serverDebugMode;
  bool get localDebugMode => _isDebugMode;
  bool get serverDebugMode => _serverDebugMode;
  
  /// Initialize debug service with command line arguments
  void initialize(List<String> args) {
    // Check for --debug flag
    _isDebugMode = args.contains('--debug') || args.contains('-d');
    
    if (_isDebugMode) {
      print('🐛 Debug mode enabled');
      print('   - HTTP requests/responses will be logged');
      print('   - Browser navigation will be logged');
      print('   - Mail operations will be logged');
      print('   - Upload operations will be logged');
      print('   - Debug banner will be displayed in UI');
      print('');
    }
  }
  
  /// Log HTTP-related debug information
  void logHttp(String message) {
    if (_isDebugMode) {
      print('[HTTP] ${DateTime.now().toIso8601String()}: $message');
    }
  }
  
  /// Log browser-related debug information
  void logBrowser(String message) {
    if (_isDebugMode) {
      print('[BROWSER] ${DateTime.now().toIso8601String()}: $message');
    }
  }
  
  /// Log mail-related debug information
  void logMail(String message) {
    if (_isDebugMode) {
      print('[MAIL] ${DateTime.now().toIso8601String()}: $message');
    }
  }
  
  /// Log upload-related debug information
  void logUpload(String message) {
    if (_isDebugMode) {
      print('[UPLOAD] ${DateTime.now().toIso8601String()}: $message');
    }
  }
  
  /// Log IRC-related debug information
  void logIrc(String message) {
    if (_isDebugMode) {
      print('[IRC] ${DateTime.now().toIso8601String()}: $message');
    }
  }
  
  /// Log general debug information
  void log(String category, String message) {
    if (_isDebugMode) {
      print('[$category] ${DateTime.now().toIso8601String()}: $message');
    }
  }
  
  /// Force print a message (used for app startup)
  void forceLog(String message) {
    print(message);
  }
  
  /// Check server debug status
  Future<void> checkServerDebugStatus() async {
    try {
      final response = await http.get(
        Uri.parse('https://bridge.stormycloud.org/api/v1/debug'),
        headers: {
          'User-Agent': 'I2PBridge/1.0.0',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _serverDebugMode = data['debug'] == true;
        
        if (_serverDebugMode) {
          forceLog('🐛 Server debug mode detected - detailed server logging is active');
        }
      }
    } catch (e) {
      // Silently fail - server might not be available
      _serverDebugMode = false;
    }
  }
}