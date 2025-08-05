// lib/pages/create_account_page.dart
// A native UI for the Susimail account creation form.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nickController = TextEditingController();
  
  bool _isPublic = false;
  bool _isLoading = false;
  String _statusMessage = '';
  
  // SSL Pinning configuration - Updated to use certificate fingerprint
  static const String expectedCertFingerprint = 'AO5T/CbxDzIBFkUp6jLEcAk0+ZxeN06uaKyeIzIE+E0=';
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';
  static const String _serverBaseUrl = 'https://bridge.stormycloud.org';
  
  late http.Client _httpClient;

  @override
  void initState() {
    super.initState();
    _httpClient = _createPinnedHttpClient();
  }

  @override
  void dispose() {
    _httpClient.close();
    _accountController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nickController.dispose();
    super.dispose();
  }
  
  /// Get authenticated headers for HTTP requests
  Future<Map<String, String>> _getAuthenticatedHeaders() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.ensureAuthenticated();
      return authService.getAuthHeaders();
    } catch (e) {
      // Fallback to basic headers if authentication fails
      return {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': appUserAgent,
      };
    }
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
        return false;
      }
    };
    
    return IOClient(httpClient);
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating your I2P account...';
    });

    const int maxRetries = 3;
    
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (attempt > 1) {
          setState(() {
            _statusMessage = 'Attempt $attempt of $maxRetries - I2P network can be slow...';
          });
          
          // Show retry snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Attempt ${attempt-1} failed. Retrying... ($attempt/$maxRetries)'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          
          // Wait 3 seconds before retry
          await Future.delayed(const Duration(seconds: 3));
        }

        final headers = await _getAuthenticatedHeaders();
        final response = await _httpClient.post(
          Uri.parse('$_serverBaseUrl/api/v1/account/create'),
          headers: headers,
          body: json.encode({
            'mail': _accountController.text.trim(),
            'pw1': _passwordController.text,
            'pw2': _confirmPasswordController.text,
            'nick': _nickController.text.trim(),
            'isPublic': _isPublic,
          }),
        ).timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (mounted) {
            setState(() {
              _isLoading = false;
              _statusMessage = '';
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message'] ?? 'Account created successfully!'),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 5),
              ),
            );
            
            // Show success dialog with account details
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Account Created!'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Your I2P mail account has been created successfully.'),
                    const SizedBox(height: 16),
                    Text('Username: ${data['username']}', 
                         style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    const Text('New I2P Mail accounts may take up to 30 minutes to activate.'),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close dialog
                      Navigator.of(context).pop(); // Go back to previous page
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      minimumSize: const Size(140, 44),
                    ),
                    child: const Text('Continue to Login'),
                  ),
                ],
              ),
            );
          }
          return; // Success - exit retry loop
        } else {
          final errorData = json.decode(response.body);
          throw Exception(errorData['error'] ?? 'Account creation failed');
        }
      } catch (e) {
        // Handle non-retriable errors immediately
        if (e.toString().contains('Account name already exists')) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _statusMessage = '';
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account name already exists - please choose a different name'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
          return; // Don't retry for duplicate accounts
        }
        
        // If this is the last attempt, show final error
        if (attempt == maxRetries) {
          if (mounted) {
            String errorMessage = 'Account creation failed';
            
            if (e.toString().contains('TimeoutException')) {
              errorMessage = 'Request timed out - I2P network is slow, please try again';
            } else if (e.toString().contains('Cannot reach I2P network')) {
              errorMessage = 'Cannot reach I2P network - please try again later';
            } else {
              errorMessage = e.toString().replaceAll('Exception: ', '');
            }
            
            setState(() {
              _isLoading = false;
              _statusMessage = '';
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('$errorMessage after $maxRetries attempts'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
        }
        // Continue retry loop for other errors
      }
    }
    
    // If we get here, all retries failed
    if (mounted) {
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create I2PMail Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _accountController,
                decoration: const InputDecoration(
                  labelText: 'Desired Account Name',
                  border: OutlineInputBorder(),
                  suffixText: '@mail.i2p',
                  helperText: 'Maximum 16 characters',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                maxLength: 16,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a username';
                  }
                  if (value.length > 16) {
                    return 'Username must be 16 characters or less';
                  }
                  if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(value)) {
                    return 'Username can only contain letters, numbers, dots, underscores, and hyphens';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Desired Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a password';
                  }
                  if (value.length < 6) {
                    return 'Password must be at least 6 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                decoration: const InputDecoration(
                  labelText: 'Repeat Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please repeat the password';
                  }
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nickController,
                decoration: const InputDecoration(
                  labelText: 'Your Nick/Handle (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                  helperText: 'Display name for your account',
                ),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: const Text('Appear in public address book?'),
                value: _isPublic,
                onChanged: (newValue) {
                  setState(() {
                    _isPublic = newValue!;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.green,
                ),
                child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Create Account'),
              ),
              if (_isLoading) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage.isEmpty 
                    ? 'Creating your I2P account...\nThis may take up to 60 seconds due to the I2P network.'
                    : _statusMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.orange,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
