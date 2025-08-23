// lib/pages/upload_page.dart
// Redesigned upload page with modern, clean UI

import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:crypto/crypto.dart';
import 'package:provider/provider.dart';
import '../assets/drop_logo.dart';
import '../services/auth_service.dart';
import '../services/debug_service.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> with SingleTickerProviderStateMixin {
  File? _pickedFile;
  String? _successfulUrl;
  bool _isLoading = false;
  bool _showAdvancedOptions = false;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _maxViewsController = TextEditingController();
  String _selectedExpiry = '24h';
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late http.Client _httpClient;

  // SSL Pinning configuration - Updated to use certificate fingerprint
  static const String expectedCertFingerprint = 'AO5T/CbxDzIBFkUp6jLEcAk0+ZxeN06uaKyeIzIE+E0=';
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';

  @override
  void initState() {
    super.initState();
    _httpClient = _createPinnedHttpClient();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
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
        DebugService.instance.logUpload('Certificate validation error: $e');
        return false;
      }
    };
    
    return IOClient(httpClient);
  }

  @override
  void dispose() {
    _httpClient.close();
    _animationController.dispose();
    _passwordController.dispose();
    _maxViewsController.dispose();
    super.dispose();
  }
  
  /// Get authenticated headers for HTTP requests
  Future<Map<String, String>> _getAuthenticatedHeaders() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.ensureAuthenticated();
      return authService.getAuthHeaders();
    } catch (e) {
      DebugService.instance.logUpload('Upload authentication failed: $e');
      // Return empty headers - the upload will likely fail but won't crash
      return <String, String>{};
    }
  }

  Future<void> _pickFile() async {
    try {
      setState(() {
        _isLoading = true; // Show loading state during file selection
      });
      
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.single.path != null) {
        setState(() {
          _pickedFile = File(result.files.single.path!);
          _successfulUrl = null;
          _isLoading = false;
        });
        
        DebugService.instance.logUpload('File selected: ${result.files.single.name} (${result.files.single.size} bytes)');
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      DebugService.instance.logUpload('File selection error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('File selection failed: ${e.toString()}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _uploadFile() async {
    if (_pickedFile == null) {
      DebugService.instance.logUpload('Upload attempted but no file selected');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an image first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() { 
      _isLoading = true; 
      _successfulUrl = null; 
    });

    const maxRetries = 3;
    for (int i = 0; i < maxRetries; i++) {
      try {
        // Show retry message if not first attempt
        if (i > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed. Retrying... (${i + 1}/$maxRetries)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
          await Future.delayed(const Duration(seconds: 2));
        }
        
        DebugService.instance.logUpload('Uploading file: ${_pickedFile!.path} (attempt ${i + 1}/$maxRetries)');
        
        var request = http.MultipartRequest(
          'POST', 
          Uri.parse('https://bridge.stormycloud.org/api/v1/upload')
        );
        
        // Add authenticated headers
        final headers = await _getAuthenticatedHeaders();
        request.headers.addAll(headers);
        
        request.files.add(
          await http.MultipartFile.fromPath(
            'file', 
            _pickedFile!.path, 
            contentType: MediaType('image', 'jpeg')
          )
        );

        if (_passwordController.text.isNotEmpty) {
          request.fields['password'] = _passwordController.text;
        }
        if (_maxViewsController.text.isNotEmpty) {
          request.fields['max_views'] = _maxViewsController.text;
        }
        request.fields['expiry'] = _selectedExpiry;

        // Add auth header
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.ensureAuthenticated();
        final authHeaders = authService.getAuthHeaders();
        request.headers.addAll(authHeaders);

        // Set timeout and send with pinned client
        var streamedResponse = await _httpClient.send(request).timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            throw Exception('Upload timed out');
          },
        );
        
        final responseBody = await streamedResponse.stream.bytesToString();
        final decodedBody = json.decode(responseBody);
        
        DebugService.instance.logUpload('Upload response: ${streamedResponse.statusCode} - ${responseBody.length} bytes');

        if (streamedResponse.statusCode == 200) {
          final rawUrl = decodedBody['url'];
          final uri = Uri.tryParse(rawUrl);
          String finalUrl = (uri != null && uri.hasAbsolutePath) 
            ? 'http://drop.i2p${uri.path}' 
            : 'http://drop.i2p/uploads/$rawUrl';
          
          setState(() { 
            _successfulUrl = finalUrl; 
          });
          
          // Success animation
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Upload successful!'),
              backgroundColor: Colors.green,
            ),
          );
          
          break; // Success - exit retry loop
        } else {
          throw Exception(decodedBody['message'] ?? 'Upload failed');
        }
      } on SocketException {
        if (i == maxRetries - 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload failed: Connection timed out'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        if (i == maxRetries - 1) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Upload failed after $maxRetries attempts: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
    
    setState(() => _isLoading = false);
  }

  void _copyToClipboard() {
    if (_successfulUrl != null) {
      Clipboard.setData(ClipboardData(text: _successfulUrl!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ URL copied to clipboard!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetUpload() {
    setState(() {
      _pickedFile = null;
      _successfulUrl = null;
      _passwordController.clear();
      _maxViewsController.clear();
      _selectedExpiry = '24h';
      _showAdvancedOptions = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16), 
              SizedBox(
                height: 100,
                child: SvgPicture.string(dropLogoSvg),
              ),
              const SizedBox(height: 32),
              
              // Main upload area
              if (_successfulUrl == null) ...[
                _buildUploadCard(),
                const SizedBox(height: 20),
                _buildAdvancedOptions(),
                const SizedBox(height: 24),
                _buildUploadButton(),
              ] else
                _buildSuccessCard(),
              
              const SizedBox(height: 20),
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return GestureDetector(
      onTap: _pickFile,
      child: Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _pickedFile != null 
              ? Colors.green.withOpacity(0.5)
              : Colors.grey.withOpacity(0.3),
            width: 2,
            style: BorderStyle.solid,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _pickedFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
                size: 64,
                color: _pickedFile != null ? Colors.green : Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                _pickedFile != null 
                  ? _pickedFile!.path.split('/').last
                  : 'Tap to select image',
                style: TextStyle(
                  fontSize: 16,
                  color: _pickedFile != null ? Colors.white : Colors.grey,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_pickedFile != null) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _pickFile,
                  child: const Text('Change Image'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAdvancedOptions() {
    return Column(
      children: [
        TextButton.icon(
          onPressed: () {
            setState(() {
              _showAdvancedOptions = !_showAdvancedOptions;
            });
          },
          icon: Icon(
            _showAdvancedOptions ? Icons.expand_less : Icons.expand_more,
          ),
          label: Text(_showAdvancedOptions ? 'Hide Options' : 'Show Options'),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: _showAdvancedOptions ? null : 0,
          child: _showAdvancedOptions
            ? Column(
                children: [
                  const SizedBox(height: 16),
                  // Expiry dropdown
                  DropdownButtonFormField<String>(
                    value: _selectedExpiry,
                    decoration: const InputDecoration(
                      labelText: 'Expiration',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(value: '15m', child: Text('15 minutes')),
                      DropdownMenuItem(value: '1h', child: Text('1 hour')),
                      DropdownMenuItem(value: '6h', child: Text('6 hours')),
                      DropdownMenuItem(value: '24h', child: Text('24 hours')),
                      DropdownMenuItem(value: '48h', child: Text('48 hours')),
                    ],
                    onChanged: (value) => setState(() => _selectedExpiry = value!),
                  ),
                  const SizedBox(height: 16),
                  // Password field
                  TextField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_outline),
                      helperText: 'Viewers will need this password',
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  // Max views field
                  TextField(
                    controller: _maxViewsController,
                    decoration: const InputDecoration(
                      labelText: 'Max views (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.visibility_outlined),
                      helperText: 'Delete after this many views',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ],
              )
            : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildUploadButton() {
    return ElevatedButton(
      onPressed: _isLoading ? null : _uploadFile,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
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
        : const Text(
            'Upload to drop.i2p',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
    );
  }

  Widget _buildSuccessCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Upload Successful!',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              _successfulUrl!,
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _copyToClipboard,
                icon: const Icon(Icons.copy, size: 20),
                label: const Text('Copy URL'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _resetUpload,
                icon: const Icon(Icons.refresh),
                label: const Text('New Upload'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Colors.blue,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'About drop.i2p',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Your images are encrypted and stored anonymously on the I2P network.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}