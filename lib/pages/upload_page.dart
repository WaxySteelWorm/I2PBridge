// lib/pages/upload_page.dart
// This version fixes the color of the Drop SVG logo.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../assets/drop_logo.dart';

class UploadPage extends StatefulWidget {
  const UploadPage({super.key});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  File? _pickedFile;
  String _uploadStatus = 'Select an image to upload to drop.i2p';
  String? _successfulUrl;
  bool _isLoading = false;

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _maxViewsController = TextEditingController();
  String? _selectedExpiry = '1h';
  final List<String> _expiryOptions = ['15m', '1h', '2h', '4h', '8h', '12h', '24h', '48h'];

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
        _uploadStatus = 'Selected: ${_pickedFile!.path.split('/').last}';
        _successfulUrl = null;
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_pickedFile == null) {
      setState(() => _uploadStatus = 'Please select an image first.');
      return;
    }
    setState(() { _isLoading = true; _successfulUrl = null; });

    const maxRetries = 3;
    for (int i = 0; i < maxRetries; i++) {
      try {
        setState(() {
          _uploadStatus = i == 0 ? 'Uploading...' : 'Upload failed. Retrying... (${i + 1}/$maxRetries)';
        });

        var request = http.MultipartRequest('POST', Uri.parse('http://bridge.stormycloud.org:3000/api/v1/upload'));
        request.files.add(await http.MultipartFile.fromPath('file', _pickedFile!.path, contentType: MediaType('image', 'jpeg')));

        if (_passwordController.text.isNotEmpty) request.fields['password'] = _passwordController.text;
        if (_maxViewsController.text.isNotEmpty) request.fields['max_views'] = _maxViewsController.text;
        if (_selectedExpiry != null) request.fields['expiry'] = _selectedExpiry!;

        var response = await request.send();
        final responseBody = await response.stream.bytesToString();
        final decodedBody = json.decode(responseBody);

        if (response.statusCode == 200) {
          final rawUrl = decodedBody['url'];
          final uri = Uri.tryParse(rawUrl);
          String finalUrl = (uri != null && uri.hasAbsolutePath) ? 'http://drop.i2p${uri.path}' : 'http://drop.i2p/uploads/$rawUrl';
          setState(() { _uploadStatus = 'Upload successful! Tap to copy URL.'; _successfulUrl = finalUrl; });
          setState(() => _isLoading = false);
          return;
        } else {
          if (i == maxRetries - 1) {
             setState(() => _uploadStatus = 'Upload failed: ${decodedBody['message']}');
          }
        }
      } catch (e) {
        if (i == maxRetries - 1) {
          setState(() => _uploadStatus = 'Error connecting to bridge: $e');
        }
      }
      if (i < maxRetries - 1) {
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    setState(() => _isLoading = false);
  }

  void _copyToClipboard() {
    if (_successfulUrl != null) {
      Clipboard.setData(ClipboardData(text: _successfulUrl!));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL Copied to Clipboard!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- FIX: Removed color filter to allow native SVG colors ---
          SizedBox(height: 120, child: SvgPicture.string(dropLogoSvg)),
          const SizedBox(height: 24),
          ElevatedButton.icon(icon: const Icon(Icons.image_outlined), label: const Text('Select Image'), onPressed: _pickFile),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            value: _selectedExpiry,
            hint: const Text('Set Expiration'),
            onChanged: (String? newValue) => setState(() => _selectedExpiry = newValue),
            items: _expiryOptions.map<DropdownMenuItem<String>>((String value) {
              return DropdownMenuItem<String>(value: value, child: Text(value));
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(controller: _passwordController, decoration: const InputDecoration(labelText: 'Password (optional)'), obscureText: true),
          const SizedBox(height: 16),
          TextField(controller: _maxViewsController, decoration: const InputDecoration(labelText: 'Max Views (optional)'), keyboardType: TextInputType.number),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _isLoading ? null : _uploadFile,
            child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Upload'),
          ),
          const SizedBox(height: 24),

          GestureDetector(
            onTap: _copyToClipboard,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    children: [
                      Text(_uploadStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, height: 1.5)),
                      if (_successfulUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(_successfulUrl!, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
