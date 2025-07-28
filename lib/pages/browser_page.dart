// lib/pages/browser_page.dart
// Redesigned browser with cleaner privacy UI

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/popular_sites.dart';
import '../services/encryption_service.dart';

class BrowserPage extends StatefulWidget {
  final String? initialUrl;
  final String? sessionCookie;
  const BrowserPage({this.initialUrl, this.sessionCookie, super.key});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with SingleTickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final EncryptionService _encryption = EncryptionService(); // Singleton instance
  
  String? _pageContent;
  String _contentType = 'text/html';
  bool _isLoading = false;
  bool _encryptionEnabled = true;
  
  final List<String> _history = [];
  int _historyIndex = -1;
  final Map<String, String> _cache = {};
  
  // Animation controller for the lock icon
  late AnimationController _lockAnimationController;
  late Animation<double> _lockAnimation;
  
  bool get _canGoBack {
    return _historyIndex > 0 || (_historyIndex == 0 && _pageContent != null);
  }
  bool get _canGoForward => _historyIndex < _history.length - 1;
  bool get _canRefresh => _history.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _encryption.initialize(); // Safe to call multiple times
    
    // Initialize animation
    _lockAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _lockAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _lockAnimationController,
      curve: Curves.easeInOut,
    ));
    
    if (_encryptionEnabled) {
      _lockAnimationController.forward();
    }
    
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(widget.initialUrl!));
    }
  }

  @override
  void dispose() {
    _lockAnimationController.dispose();
    super.dispose();
  }

  void _toggleEncryption() {
    setState(() {
      _encryptionEnabled = !_encryptionEnabled;
      _cache.clear();
    });
    
    if (_encryptionEnabled) {
      _lockAnimationController.forward();
    } else {
      _lockAnimationController.reverse();
    }
    
    // Show snackbar with animation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _encryptionEnabled ? Icons.lock : Icons.lock_open,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(_encryptionEnabled 
              ? 'Privacy Mode enabled' 
              : 'Privacy Mode disabled'),
          ],
        ),
        backgroundColor: _encryptionEnabled ? Colors.green : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _goBack() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
        _loadPage(_history[_historyIndex], fromHistory: true);
      });
    } else if (_historyIndex == 0) {
      setState(() {
        _historyIndex = -1;
        _history.clear();
        _pageContent = null;
        _urlController.clear();
      });
    }
  }

  void _goForward() { 
    if (_canGoForward) setState(() { 
      _historyIndex++; 
      _loadPage(_history[_historyIndex], fromHistory: true); 
    }); 
  }
  
  void _refresh() { 
    if (_canRefresh) _loadPage(_history[_historyIndex], fromHistory: true, forceRefresh: true); 
  }
  
  Future<void> _loadPage(String url, {bool fromHistory = false, bool forceRefresh = false}) async {
    String fullUrl;
    if (url.contains('.')) {
      fullUrl = url.startsWith('http') ? url : 'http://$url';
    } else {
      if (_history.isEmpty) {
        fullUrl = 'http://$url';
      } else {
        final currentUri = Uri.parse('http://${_history[_historyIndex]}');
        fullUrl = currentUri.resolve(url).toString();
      }
    }
    final cleanUrl = fullUrl.replaceFirst(RegExp(r'^https?://'), '');
    
    setState(() { 
      _isLoading = true; 
      _pageContent = 'Loading $cleanUrl...'; 
      _contentType = 'text/html'; 
      _urlController.text = cleanUrl; 
    });

    if (!forceRefresh && _cache.containsKey(cleanUrl)) {
      setState(() { _pageContent = _cache[cleanUrl]!; _isLoading = false; });
      if (!fromHistory) {
        if (_history.isEmpty) _historyIndex = -1;
        if (_historyIndex < _history.length - 1) _history.removeRange(_historyIndex + 1, _history.length);
        _history.add(cleanUrl);
        _historyIndex++;
      }
      return;
    }

    if (!fromHistory) {
      if (_history.isEmpty) _historyIndex = -1;
      if (_historyIndex < _history.length - 1) _history.removeRange(_historyIndex + 1, _history.length);
      _history.add(cleanUrl);
      _historyIndex++;
    }

    try {
      if (_encryptionEnabled) {
        // Use privacy-preserving approach
        await Future.delayed(Duration(milliseconds: DateTime.now().millisecond % 500));
        
        final sessionToken = _encryption.generateChannelId();
        final encryptedUrl = _encryption.encryptUrl(cleanUrl);
        
        final response = await http.post(
          Uri.parse('http://bridge.stormycloud.org:3000/api/v1/browse'),
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Session-Token': sessionToken,
            'X-Privacy-Mode': 'enabled',
            if (widget.sessionCookie != null) 'Cookie': widget.sessionCookie!,
          },
          body: 'url=$encryptedUrl&encrypted=true',
        ).timeout(const Duration(seconds: 30));
        
        if (response.statusCode == 200) {
          final newContent = response.body;
          final newContentType = response.headers['content-type'] ?? 'text/html';
          setState(() { 
            _pageContent = newContent; 
            _contentType = newContentType; 
          });
          if (newContentType.startsWith('text/html')) {
            _cache[cleanUrl] = newContent;
          }
        } else {
          setState(() => _pageContent = 'Error: ${response.statusCode}\n\n${response.body}');
        }
      } else {
        // Standard unencrypted mode
        final Uri browseUrl = Uri.parse('http://bridge.stormycloud.org:3000/api/v1/browse?url=$cleanUrl');
        final headers = <String, String>{};
        if (widget.sessionCookie != null) headers['Cookie'] = widget.sessionCookie!;
        
        final response = await http.get(browseUrl, headers: headers).timeout(const Duration(seconds: 30));
        
        if (response.statusCode == 200) {
          final newContent = response.body;
          final newContentType = response.headers['content-type'] ?? 'text/html';
          setState(() { _pageContent = newContent; _contentType = newContentType; });
          if (newContentType.startsWith('text/html')) _cache[cleanUrl] = newContent;
        } else {
          setState(() => _pageContent = 'Error: ${response.statusCode}\n\n${response.body}');
        }
      }
    } catch (e) {
      setState(() => _pageContent = 'Failed to connect to the bridge server.\nError: $e');
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final Color svgColor = Theme.of(context).textTheme.bodyLarge?.color ?? Colors.white;
    final currentUrl = _history.isNotEmpty ? _history[_historyIndex] : '';

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: <Widget>[
          // Redesigned navigation bar with integrated lock
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton( 
                  icon: const Icon(Icons.arrow_back), 
                  onPressed: _canGoBack ? _goBack : null, 
                ),
                IconButton( 
                  icon: const Icon(Icons.arrow_forward), 
                  onPressed: _canGoForward ? _goForward : null, 
                ),
                Expanded(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        // Animated lock icon in address bar
                        GestureDetector(
                          onTap: _toggleEncryption,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: AnimatedBuilder(
                              animation: _lockAnimation,
                              builder: (context, child) {
                                return Icon(
                                  _encryptionEnabled ? Icons.lock : Icons.lock_open,
                                  size: 18,
                                  color: ColorTween(
                                    begin: Colors.grey,
                                    end: Colors.green,
                                  ).evaluate(_lockAnimation),
                                );
                              },
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _urlController,
                            decoration: const InputDecoration(
                              hintText: 'Enter I2P address',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8),
                            ),
                            style: const TextStyle(fontSize: 14),
                            onSubmitted: (value) => _loadPage(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton( 
                  icon: const Icon(Icons.refresh), 
                  onPressed: _isLoading || !_canRefresh ? null : _refresh, 
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox( 
            width: double.infinity, 
            child: ElevatedButton( 
              onPressed: _isLoading ? null : () => _loadPage(_urlController.text), 
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
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
                : const Text('Go'), 
            ), 
          ),
          const SizedBox(height: 16),
          Expanded( 
            child: Card(
              margin: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _pageContent == null
                  ? _buildPopularSitesList()
                  : _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              _pageContent!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : _contentType.startsWith('image/')
                        ? Center(
                            child: CachedNetworkImage(
                              imageUrl: _encryptionEnabled 
                                ? 'http://bridge.stormycloud.org:3000/api/v1/browse'
                                : 'http://bridge.stormycloud.org:3000/api/v1/browse?url=$currentUrl',
                              httpHeaders: _encryptionEnabled 
                                ? {
                                    'Content-Type': 'application/x-www-form-urlencoded',
                                    'X-Session-Token': _encryption.generateChannelId(),
                                    'X-Privacy-Mode': 'enabled',
                                  }
                                : null,
                              placeholder: (context, url) => const CircularProgressIndicator(), 
                              errorWidget: (context, url, error) => const Text('[Image failed to load]'),
                            )
                          )
                        : HtmlWidget( 
                            _pageContent!, 
                            renderMode: RenderMode.listView, 
                            customWidgetBuilder: (element) { 
                              if (element.localName == 'img') { 
                                final src = element.attributes['src']; 
                                if (src != null) { 
                                  if (src.startsWith('data:image')) { 
                                    try { 
                                      final parts = src.split(','); 
                                      final imageBytes = base64Decode(parts[1]); 
                                      return Image.memory(imageBytes); 
                                    } catch (e) { 
                                      return const Text('[Invalid Image Data]'); 
                                    } 
                                  } 
                                  final currentUri = Uri.parse('http://$currentUrl'); 
                                  final imageUrl = currentUri.resolve(src).toString(); 
                                  final proxiedUrl = 'http://bridge.stormycloud.org:3000/api/v1/browse?url=${imageUrl.replaceFirst(RegExp(r'^https?://'), '')}'; 
                                  if (proxiedUrl.endsWith('.svg')) { 
                                    return SvgPicture.network( 
                                      proxiedUrl, 
                                      colorFilter: ColorFilter.mode(svgColor, BlendMode.srcIn), 
                                      placeholderBuilder: (context) => const CircularProgressIndicator(), 
                                    ); 
                                  } else { 
                                    return CachedNetworkImage( 
                                      imageUrl: proxiedUrl, 
                                      placeholder: (context, url) => const CircularProgressIndicator(), 
                                      errorWidget: (context, url, error) => const Text('[Image failed to load]'), 
                                    ); 
                                  } 
                                } 
                              } 
                              return null; 
                            }, 
                            onTapUrl: (url) { 
                              _loadPage(url); 
                              return true; 
                            }, 
                            textStyle: const TextStyle(color: Colors.white), 
                          ),
              ),
            ), 
          ),
        ],
      ),
    );
  }

  Widget _buildPopularSitesList() {
    return Column(
      children: [
        const SizedBox(height: 10),
        Icon(
          Icons.language,
          size: 64,
          color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
        ),
        const SizedBox(height: 16),
        Text(
          _encryptionEnabled 
            ? '🔒 Privacy Mode Active'
            : '🔓 Standard Mode',
          style: TextStyle(
            fontSize: 14,
            color: _encryptionEnabled ? Colors.green : Colors.orange,
          ),
        ),
        const SizedBox(height: 32),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Popular I2P Sites',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: popularSites.length,
            itemBuilder: (context, index) {
              final site = popularSites[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      site.name[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(site.name),
                  subtitle: Text(
                    site.description,
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  onTap: () => _loadPage(site.url),
                ),
              );
            },
          ),
        ),
        // Privacy tip at bottom
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Tap the lock icon in the address bar to toggle privacy mode',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}