// lib/pages/upload_page.dart (Reverted)
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';

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

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
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

    setState(() {
      _isLoading = true;
      _uploadStatus = 'Uploading...';
      _successfulUrl = null;
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://bridge.stormycloud.org:3000/api/v1/upload'),
      );

      request.files.add(await http.MultipartFile.fromPath(
        'file',
        _pickedFile!.path,
        contentType: MediaType('image', 'jpeg'),
      ));

      var response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final decodedBody = json.decode(responseBody);

      if (response.statusCode == 200) {
        final rawUrl = decodedBody['url'];
        final uri = Uri.tryParse(rawUrl);
        String finalUrl;
        if (uri != null && uri.hasAbsolutePath) {
            finalUrl = 'http://drop.i2p${uri.path}';
        } else {
            finalUrl = 'http://drop.i2p/uploads/$rawUrl';
        }
        
        setState(() {
          _uploadStatus = 'Upload successful! Tap to copy URL.';
          _successfulUrl = finalUrl;
        });
      } else {
        setState(() => _uploadStatus = 'Upload failed: ${decodedBody['message']}');
      }
    } catch (e) {
      setState(() => _uploadStatus = 'Error connecting to bridge: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _copyToClipboard() {
    if (_successfulUrl != null) {
      Clipboard.setData(ClipboardData(text: _successfulUrl!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL Copied to Clipboard!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.cloud_upload_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: const Text('Select Image'),
            onPressed: _pickFile,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _isLoading ? null : _uploadFile,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.blueAccent,
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Upload', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 24),

          GestureDetector(
            onTap: _copyToClipboard,
            child: Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  children: [
                    Text(
                      _uploadStatus,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, height: 1.5),
                    ),
                    if (_successfulUrl != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          _successfulUrl!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: Colors.blue, decoration: TextDecoration.underline),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
