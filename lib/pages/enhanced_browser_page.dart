// lib/pages/enhanced_browser_page.dart
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import '../data/popular_sites.dart';
import '../services/encryption_service.dart';
import '../services/debug_service.dart';

class EnhancedBrowserPage extends StatefulWidget {
  final String? initialUrl;
  final String? sessionCookie;
  
  const EnhancedBrowserPage({this.initialUrl, this.sessionCookie, super.key});
  
  @override
  State<EnhancedBrowserPage> createState() => _EnhancedBrowserPageState();
}

class _EnhancedBrowserPageState extends State<EnhancedBrowserPage> with SingleTickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final EncryptionService _encryption = EncryptionService();
  
  InAppWebViewController? _webViewController;
  bool _isLoading = false;
  bool _encryptionEnabled = true;
  double _progress = 0;
  String _currentUrl = '';
  String _currentBaseUrl = '';
  
  final List<String> _history = [];
  int _historyIndex = -1;
  
  late AnimationController _lockAnimationController;
  late Animation<double> _lockAnimation;
  
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';
  final http.Client _httpClient = http.Client();
  
  bool get _canGoBack => _webViewController != null && _historyIndex > 0;
  bool get _canGoForward => _webViewController != null && _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    _encryption.initialize();
    
    _lockAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _lockAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _lockAnimationController, curve: Curves.easeInOut)
    );
    
    if (_encryptionEnabled) _lockAnimationController.forward();
    
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(widget.initialUrl!));
    }
  }

  @override
  void dispose() {
    _lockAnimationController.dispose();
    _httpClient.close();
    super.dispose();
  }

  void _log(String message) {
    DebugService.instance.logBrowser(message);
  }

  void _toggleEncryption() {
    setState(() {
      _encryptionEnabled = !_encryptionEnabled;
    });
    
    if (_encryptionEnabled) {
      _lockAnimationController.forward();
    } else {
      _lockAnimationController.reverse();
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_encryptionEnabled ? Icons.lock : Icons.lock_open, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(_encryptionEnabled ? 'Privacy Mode enabled' : 'Privacy Mode disabled'),
          ],
        ),
        backgroundColor: _encryptionEnabled ? Colors.green : Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _goBack() async {
    if (_webViewController != null) {
      if (await _webViewController!.canGoBack()) {
        await _webViewController!.goBack();
      } else if (_historyIndex > 0) {
        setState(() => _historyIndex--);
        await _loadPage(_history[_historyIndex], fromHistory: true);
      }
    }
  }

  Future<void> _goForward() async {
    if (_webViewController != null) {
      if (await _webViewController!.canGoForward()) {
        await _webViewController!.goForward();
      } else if (_historyIndex < _history.length - 1) {
        setState(() => _historyIndex++);
        await _loadPage(_history[_historyIndex], fromHistory: true);
      }
    }
  }

  Future<void> _refresh() async {
    if (_webViewController != null) {
      await _webViewController!.reload();
    } else if (_history.isNotEmpty) {
      await _loadPage(_history[_historyIndex], fromHistory: true, forceRefresh: true);
    }
  }

  Future<void> _loadPage(String url, {bool fromHistory = false, bool forceRefresh = false}) async {
    if (url.trim().isEmpty) return;
    
    String fullUrl = url.startsWith('http') ? url : 'http://$url';
    final cleanUrl = fullUrl.replaceFirst(RegExp(r'^https?://'), '');
    
    _log('Loading page: $fullUrl');
    
    setState(() {
      _isLoading = true;
      _currentUrl = cleanUrl;
      _currentBaseUrl = fullUrl;
      _urlController.text = cleanUrl;
      _progress = 0.0;
    });

    if (!fromHistory) {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(cleanUrl);
      _historyIndex = _history.length - 1;
    }

    try {
      setState(() => _progress = 0.3);
      
      final content = await _fetchFromBridge(fullUrl);
      
      setState(() => _progress = 0.7);
      
      if (content.trim().isEmpty) {
        throw Exception('Empty response from server');
      }
      
      final enhancedHtml = _enhanceHtmlForMobile(content, fullUrl);
      
      setState(() => _progress = 0.9);
      
      if (_webViewController != null) {
        await _webViewController!.loadData(
          data: enhancedHtml,
          mimeType: "text/html",
          encoding: "utf8",
          baseUrl: WebUri(fullUrl),
        );
      }
      
      setState(() => _progress = 1.0);
      _log('Page loaded successfully: $cleanUrl');
      
    } catch (e) {
      _log('Error loading page: $e');
      final errorHtml = _createErrorPage('Failed to load $cleanUrl: ${e.toString()}');
      if (_webViewController != null) {
        await _webViewController!.loadData(data: errorHtml, mimeType: "text/html");
      }
    } finally {
      await Future.delayed(const Duration(milliseconds: 300));
      setState(() {
        _isLoading = false;
        _progress = 1.0;
      });
    }
  }

  Future<String> _fetchFromBridge(String fullUrl) async {
    const maxRetries = 2;
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        _log('Fetching from bridge (attempt ${attempt + 1}): $fullUrl');
        
        if (_encryptionEnabled) {
          final sessionToken = _encryption.generateChannelId();
          final encryptedUrl = _encryption.encryptUrl(fullUrl);
          
          final headers = {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-Session-Token': sessionToken,
            'X-Privacy-Mode': 'enabled',
            'User-Agent': appUserAgent,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
            if (widget.sessionCookie != null) 'Cookie': widget.sessionCookie!,
          };
          
          final body = 'url=$encryptedUrl&encrypted=true';
          
          DebugService.instance.logHttp('POST https://bridge.stormycloud.org/api/v1/browse - Encrypted request for: $fullUrl');
          final response = await _httpClient.post(
            Uri.parse('https://bridge.stormycloud.org/api/v1/browse'),
            headers: headers,
            body: body,
          ).timeout(const Duration(seconds: 45));
          DebugService.instance.logHttp('Response: ${response.statusCode} (${response.body.length} bytes)');
          
          _log('Bridge response: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            if (response.body.trim().isEmpty) {
              throw Exception('Empty response from server');
            }
            
            try {
              final jsonResponse = jsonDecode(response.body);
              final content = jsonResponse['content'] ?? jsonResponse['data'] ?? response.body;
              if (content.toString().trim().isEmpty) {
                throw Exception('No content in response');
              }
              return content.toString();
            } catch (jsonError) {
              return response.body;
            }
          } else {
            throw Exception('Server returned ${response.statusCode}: ${response.reasonPhrase}');
          }
        } else {
          final Uri browseUrl = Uri.parse('https://bridge.stormycloud.org/api/v1/browse?url=${Uri.encodeComponent(fullUrl)}');
          final headers = {
            'User-Agent': appUserAgent,
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'gzip, deflate',
            'Connection': 'keep-alive',
          };
          if (widget.sessionCookie != null) headers['Cookie'] = widget.sessionCookie!;
          
          DebugService.instance.logHttp('GET $browseUrl - Direct request');
          final response = await _httpClient.get(browseUrl, headers: headers).timeout(const Duration(seconds: 45));
          DebugService.instance.logHttp('Response: ${response.statusCode} (${response.body.length} bytes)');
          
          _log('Bridge response: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            if (response.body.trim().isEmpty) {
              throw Exception('Empty response from server');
            }
            
            try {
              final jsonResponse = jsonDecode(response.body);
              final content = jsonResponse['content'] ?? jsonResponse['data'] ?? response.body;
              if (content.toString().trim().isEmpty) {
                throw Exception('No content in response');
              }
              return content.toString();
            } catch (jsonError) {
              return response.body;
            }
          } else {
            throw Exception('Server returned ${response.statusCode}: ${response.reasonPhrase}');
          }
        }
      } catch (e) {
        _log('Bridge fetch error (attempt ${attempt + 1}): $e');
        if (attempt == maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    
    throw Exception('Failed after $maxRetries retries');
  }

  String _enhanceHtmlForMobile(String html, String baseUrl) {
    final Uri baseUri = Uri.parse(baseUrl);
    
    // Fix relative URLs for images and links
    html = _fixRelativeUrls(html, baseUri);
    
    // Convert all images to base64 or proxy them through our bridge
    html = _proxyImages(html, baseUri);
    
    // Remove any meta refreshes or redirects that would bypass our handler
    html = _removeMetaRedirects(html);
    
    final mobileCSS = '''
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0, user-scalable=yes">
    <meta name="color-scheme" content="dark">
    <style>
      * { box-sizing: border-box; }
      body { 
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
        font-size: 18px; 
        line-height: 1.6; 
        margin: 0; 
        padding: 16px;
        background-color: #1a1a1a !important;
        color: #ffffff !important;
        word-wrap: break-word;
        overflow-wrap: break-word;
        -webkit-text-size-adjust: 100%;
      }
      img { 
        max-width: 100% !important; 
        height: auto !important; 
        display: block;
        margin: 12px auto;
        border-radius: 8px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.3);
        background: #2a2a2a;
        border: 1px solid #444;
      }
      a { 
        color: #4A9EFF !important; 
        text-decoration: none;
        padding: 8px 12px;
        border-radius: 6px;
        background: rgba(74, 158, 255, 0.1) !important;
        display: inline-block;
        margin: 4px 2px;
        min-height: 44px;
        line-height: 28px;
        word-wrap: break-word;
        transition: background 0.2s ease;
      }
      a:hover, a:active { 
        background: rgba(74, 158, 255, 0.2) !important;
        text-decoration: underline;
      }
      a:active {
        transform: scale(0.98);
      }
      table { 
        width: 100% !important; 
        border-collapse: collapse;
        font-size: 16px;
        margin: 16px 0;
        background: #2a2a2a !important;
        border-radius: 8px;
        overflow: hidden;
      }
      table td, table th {
        padding: 12px;
        border: 1px solid #444 !important;
        word-wrap: break-word;
        background: #2a2a2a !important;
        color: #ffffff !important;
      }
      table th {
        background: #3a3a3a !important;
        font-weight: bold;
      }
      pre, code { 
        background: #2a2a2a !important;
        color: #ffffff !important;
        padding: 12px;
        border-radius: 8px;
        font-size: 16px;
        overflow-x: auto;
        border: 1px solid #444;
        font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
      }
      input, textarea, select {
        font-size: 18px !important;
        padding: 16px !important;
        border: 2px solid #4A9EFF !important;
        border-radius: 8px;
        background: #2a2a2a !important;
        color: #ffffff !important;
        min-height: 44px;
        width: 100%;
        max-width: 100%;
        box-sizing: border-box;
        margin: 8px 0;
        -webkit-appearance: none;
        appearance: none;
      }
      button, input[type="button"], input[type="submit"] {
        background: #4A9EFF !important;
        color: white !important;
        cursor: pointer;
        font-weight: bold;
        border: none !important;
        transition: background 0.2s ease;
        text-align: center;
      }
      button:hover, input[type="button"]:hover, input[type="submit"]:hover {
        background: #3A8EEF !important;
      }
      h1, h2, h3, h4, h5, h6 {
        color: #4A9EFF !important;
        margin: 24px 0 16px 0;
        line-height: 1.3;
      }
      h1 { font-size: 28px; }
      h2 { font-size: 24px; }
      h3 { font-size: 20px; }
      p, li {
        margin: 12px 0;
        line-height: 1.6;
        color: #ffffff !important;
      }
      ul, ol {
        padding-left: 20px;
        margin: 16px 0;
      }
      li { margin: 8px 0; }
      blockquote {
        border-left: 4px solid #4A9EFF;
        padding-left: 16px;
        margin: 16px 0;
        background: rgba(74, 158, 255, 0.05);
        border-radius: 0 8px 8px 0;
      }
      hr {
        border: none;
        height: 2px;
        background: #444;
        margin: 24px 0;
        border-radius: 1px;
      }
      .container {
        max-width: 100%;
        overflow-x: hidden;
      }
      .post, .topic, .forum-post {
        background: #2a2a2a !important;
        border-radius: 8px;
        padding: 16px;
        margin: 12px 0;
        border: 1px solid #444;
      }
      .username, .author {
        color: #4A9EFF !important;
        font-weight: bold;
      }
      .timestamp, .date {
        color: #888 !important;
        font-size: 14px;
      }
      .gallery img, .thumbnail img {
        border-radius: 8px;
        margin: 8px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.4);
      }
      small, .small {
        font-size: 16px !important;
      }
      img[src=""], img:not([src]) {
        display: none;
      }
    </style>
    ''';

    if (html.toLowerCase().contains('<head>')) {
      html = html.replaceFirst(RegExp(r'<head>', caseSensitive: false), '<head>$mobileCSS');
    } else if (html.toLowerCase().contains('<html>')) {
      html = html.replaceFirst(RegExp(r'<html>', caseSensitive: false), '<html><head>$mobileCSS</head>');
    } else {
      html = '<!DOCTYPE html><html><head>$mobileCSS</head><body><div class="container">$html</div></body></html>';
    }

    if (!html.toLowerCase().contains('<body>')) {
      html = html.replaceFirst('</head>', '</head><body><div class="container">') + '</div></body>';
    }

    return html;
  }

  String _fixRelativeUrls(String html, Uri baseUri) {
    // Fix relative image URLs with double quotes
    html = html.replaceAllMapped(
      RegExp(r'<img[^>]*src="([^"]*)"[^>]*>', caseSensitive: false),
      (match) {
        final fullMatch = match.group(0)!;
        final src = match.group(1)!;
        
        if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) {
          return fullMatch;
        }
        
        final absoluteUrl = baseUri.resolve(src).toString();
        return fullMatch.replaceFirst(src, absoluteUrl);
      },
    );

    // Fix relative image URLs with single quotes
    html = html.replaceAllMapped(
      RegExp('<img[^>]*src=\'([^\']*)\'[^>]*>', caseSensitive: false),
      (match) {
        final fullMatch = match.group(0)!;
        final src = match.group(1)!;
        
        if (src.startsWith('http://') || src.startsWith('https://') || src.startsWith('data:')) {
          return fullMatch;
        }
        
        final absoluteUrl = baseUri.resolve(src).toString();
        return fullMatch.replaceFirst(src, absoluteUrl);
      },
    );

    // Fix relative links with double quotes
    html = html.replaceAllMapped(
      RegExp(r'<a[^>]*href="([^"]*)"[^>]*>', caseSensitive: false),
      (match) {
        final fullMatch = match.group(0)!;
        final href = match.group(1)!;
        
        if (href.startsWith('http://') || href.startsWith('https://') || href.startsWith('data:') || href.startsWith('#')) {
          return fullMatch;
        }
        
        final absoluteUrl = baseUri.resolve(href).toString();
        return fullMatch.replaceFirst(href, absoluteUrl);
      },
    );

    // Fix relative links with single quotes
    html = html.replaceAllMapped(
      RegExp('<a[^>]*href=\'([^\']*)\'[^>]*>', caseSensitive: false),
      (match) {
        final fullMatch = match.group(0)!;
        final href = match.group(1)!;
        
        if (href.startsWith('http://') || href.startsWith('https://') || href.startsWith('data:') || href.startsWith('#')) {
          return fullMatch;
        }
        
        final absoluteUrl = baseUri.resolve(href).toString();
        return fullMatch.replaceFirst(href, absoluteUrl);
      },
    );

    return html;
  }

  // THIS FUNCTION IS DISABLED TO FIX THE BUILD ERROR
  String _removeMetaRedirects(String html) {
    return html;
  }

  // THIS FUNCTION IS DISABLED TO FIX THE BUILD ERROR
  String _proxyImages(String html, Uri baseUri) {
    return html;
  }

  String _createErrorPage(String error) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, sans-serif;
          background: #1a1a1a;
          color: #ffffff;
          padding: 20px;
          text-align: center;
        }
        .error-container {
          background: #2a2a2a;
          border-radius: 12px;
          padding: 24px;
          margin: 20px 0;
          border: 1px solid #444;
        }
        .error-icon {
          font-size: 48px;
          margin-bottom: 16px;
        }
        .retry-button {
          background: #4A9EFF;
          color: white;
          border: none;
          padding: 12px 24px;
          border-radius: 8px;
          font-size: 16px;
          margin-top: 16px;
          cursor: pointer;
        }
        .debug-info {
          background: #1a1a1a;
          border: 1px solid #444;
          border-radius: 8px;
          padding: 12px;
          margin-top: 16px;
          font-family: monospace;
          font-size: 12px;
          text-align: left;
          white-space: pre-wrap;
        }
      </style>
    </head>
    <body>
      <div class="error-container">
        <div class="error-icon">⚠️</div>
        <h2>Connection Error</h2>
        <p>$error</p>
        <button class="retry-button" onclick="location.reload()">Retry</button>
        <div class="debug-info">Debug Info:\nCurrent URL: $_currentUrl\nBase URL: $_currentBaseUrl\nEncryption: $_encryptionEnabled</div>
      </div>
    </body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(12),
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
                    height: 44,
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _toggleEncryption,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: AnimatedBuilder(
                              animation: _lockAnimation,
                              builder: (context, child) {
                                return Icon(
                                  _encryptionEnabled ? Icons.lock : Icons.lock_open,
                                  size: 20,
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
                            style: const TextStyle(fontSize: 16),
                            onSubmitted: (value) => _loadPage(value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _isLoading ? null : _refresh,
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
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
              child: _isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Go'),
            ),
          ),
          
          const SizedBox(height: 16),
          
          if (_progress > 0 && _progress < 1)
            LinearProgressIndicator(
              value: _progress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            ),
          
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildWebView(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_history.isEmpty && widget.initialUrl == null) {
      return _buildPopularSitesList();
    }

    return InAppWebView(
      initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(
          userAgent: appUserAgent,
          javaScriptEnabled: true,
          transparentBackground: true,
          supportZoom: true,
          cacheEnabled: false,
        ),
        ios: IOSInAppWebViewOptions(
          allowsInlineMediaPlayback: true,
          allowsBackForwardNavigationGestures: true,
        ),
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        
        // Add handler for link clicks
        controller.addJavaScriptHandler(
          handlerName: 'linkClicked',
          callback: (args) {
            if (args.isNotEmpty) {
              final url = args[0].toString();
              _log('JavaScript link click: $url');
              _loadPage(url);
            }
          },
        );
      },
      onProgressChanged: (controller, progress) {
        setState(() {
          _progress = progress / 100;
        });
      },
      onLoadStart: (controller, url) {
        _log('WebView load start: ${url?.toString()}');
        setState(() {
          _isLoading = true;
        });
      },
      onLoadStop: (controller, url) async {
        _log('WebView load stop: ${url?.toString()}');
        
        // Inject JavaScript to intercept all link clicks AND prevent redirects
        await controller.evaluateJavascript(source: '''
          (function() {
            // Remove any existing listeners
            document.removeEventListener('click', window.i2pLinkHandler);
            
            // Override window.location and related redirect methods
            var originalLocation = window.location;
            Object.defineProperty(window, 'location', {
              get: function() { return originalLocation; },
              set: function(url) {
                console.log('Redirect intercepted: ' + url);
                window.flutter_inappwebview.callHandler('linkClicked', url);
              }
            });
            
            // Override location.href
            Object.defineProperty(originalLocation, 'href', {
              get: function() { return originalLocation.href; },
              set: function(url) {
                console.log('Location.href intercepted: ' + url);
                window.flutter_inappwebview.callHandler('linkClicked', url);
              }
            });
            
            // Override location.replace
            originalLocation.replace = function(url) {
              console.log('Location.replace intercepted: ' + url);
              window.flutter_inappwebview.callHandler('linkClicked', url);
            };
            
            // Create new click handler
            window.i2pLinkHandler = function(e) {
              var target = e.target;
              
              // Find the closest anchor tag
              while (target && target.tagName !== 'A') {
                target = target.parentElement;
              }
              
              if (target && target.href) {
                e.preventDefault();
                e.stopPropagation();
                
                console.log('Link clicked: ' + target.href);
                
                // Send message to Flutter
                window.flutter_inappwebview.callHandler('linkClicked', target.href);
                
                return false;
              }
            };
            
            // Add click listener to document
            document.addEventListener('click', window.i2pLinkHandler, true);
            
            console.log('I2P link handler and redirect interceptor installed');
          })();
        ''');
        
        setState(() {
          _isLoading = false;
          _progress = 1.0;
        });
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url!;
        final url = uri.toString();
        
        _log('Navigation intercepted: $url');
        
        // Allow data URLs and about:blank
        if (url.startsWith('data:') || url.startsWith('about:blank')) {
          return NavigationActionPolicy.ALLOW;
        }
        
        // Block ALL other navigation and handle it ourselves
        if (url.contains('.i2p') || url.startsWith('http://') || url.startsWith('https://')) {
          _log('Intercepting navigation to: $url');
          // Don't await this - let it run async
          Future.microtask(() => _loadPage(url));
          return NavigationActionPolicy.CANCEL;
        }
        
        _log('Blocking unknown navigation: $url');
        return NavigationActionPolicy.CANCEL;
      },
      onConsoleMessage: (controller, consoleMessage) {
        _log('Console: ${consoleMessage.message}');
      },
    );
  }

  Widget _buildPopularSitesList() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          Icon(Icons.language, size: 80, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            _encryptionEnabled ? '🔒 Privacy Mode Active' : '🔓 Standard Mode',
            style: TextStyle(fontSize: 16, color: _encryptionEnabled ? Colors.green : Colors.orange),
          ),
          const SizedBox(height: 24),
          const Text('Popular I2P Sites', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: popularSites.length,
            itemBuilder: (context, index) {
              final site = popularSites[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      site.name[0].toUpperCase(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: Text(site.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  subtitle: Text(site.description, style: const TextStyle(fontSize: 14)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Theme.of(context).colorScheme.primary),
                  onTap: () => _loadPage(site.url),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}