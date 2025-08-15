// lib/pages/enhanced_browser_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../data/popular_sites.dart';
import '../services/encryption_service.dart';
import '../services/debug_service.dart';
import '../services/auth_service.dart';

class EnhancedBrowserPage extends StatefulWidget {
  final String? initialUrl;
  final String? sessionCookie;
  
  const EnhancedBrowserPage({this.initialUrl, this.sessionCookie, super.key});
  
  @override
  State<EnhancedBrowserPage> createState() => _EnhancedBrowserPageState();
}

class _EnhancedBrowserPageState extends State<EnhancedBrowserPage> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final TextEditingController _urlController = TextEditingController();
  final EncryptionService _encryption = EncryptionService();
  
  InAppWebViewController? _webViewController;
  bool _isLoading = false;
  double _progress = 0;
  String _currentUrl = '';
  String _currentBaseUrl = '';
  
  final List<String> _history = [];
  int _historyIndex = -1;
  bool _encryptionEnabled = true;
  
  late AnimationController _lockAnimationController;
  late Animation<double> _lockAnimation;
  
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';
  final http.Client _httpClient = http.Client();
  http.Client? _currentRequestClient;
  
  bool get _canGoBack => _webViewController != null && _historyIndex > 0;
  bool get _canGoForward => _webViewController != null && _historyIndex < _history.length - 1;

  bool _viewInitialized = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _encryption.initialize();
    
    _lockAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _lockAnimation = CurvedAnimation(
      parent: _lockAnimationController,
      curve: Curves.easeInOut,
    );
    
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(widget.initialUrl!));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewInitialized) {
      // Defer heavy webview init until first frame after this widget is visible
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _viewInitialized = true);
      });
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    _lockAnimationController.dispose();
    super.dispose();
  }
  
  /// Get authenticated headers for HTTP requests
  Future<Map<String, String>> _getAuthenticatedHeaders({Map<String, String>? additionalHeaders}) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.ensureAuthenticated();
      
      final headers = Map<String, String>.from(authService.getAuthHeaders());
      
      // Add browser-specific headers
      headers.addAll({
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
      });
      
      // Add any additional headers
      if (additionalHeaders != null) {
        headers.addAll(additionalHeaders);
      }
      
      return headers;
    } catch (e) {
      DebugService.instance.logBrowser('Browser authentication failed: $e');
      
      // Fallback to basic headers (will fail on server, but prevents crash)
      final headers = <String, String>{
        'User-Agent': appUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
      };
      
      if (additionalHeaders != null) {
        headers.addAll(additionalHeaders);
      }
      
      return headers;
    }
  }

  void _log(String message) {
    DebugService.instance.logBrowser(message);
  }

  WebUri? _getBaseUrlForPage(String fullUrl) {
    // Extract base URL (protocol + domain) from full URL and convert to WebUri
    try {
      final uri = Uri.parse(fullUrl);
      final baseUrlString = '${uri.scheme}://${uri.host}${uri.port != 80 && uri.port != 443 && uri.port > 0 ? ':${uri.port}' : ''}';
      return WebUri(baseUrlString);
    } catch (e) {
      _log('Error parsing baseUrl from $fullUrl: $e');
      // Fallback: extract everything before the path
      try {
        if (fullUrl.contains('://')) {
          final parts = fullUrl.split('/');
          if (parts.length >= 3) {
            final fallbackUrl = '${parts[0]}//${parts[2]}';
            return WebUri(fallbackUrl);
          }
        }
        // Last resort - try to use the full URL
        return WebUri(fullUrl);
      } catch (fallbackError) {
        _log('Fallback baseUrl parsing also failed: $fallbackError');
        return null; // Return null if all parsing attempts fail
      }
    }
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

  void _stop() {
    if (_isLoading) {
      _log('Stopping current request');
      
      // Cancel HTTP request if in progress
      if (_currentRequestClient != null) {
        _currentRequestClient!.close();
        _currentRequestClient = null;
      }
      
      // Stop WebView loading
      if (_webViewController != null) {
        _webViewController!.stopLoading();
      }
      
      setState(() {
        _isLoading = false;
        _progress = 0.0;
      });
    }
  }

  Future<void> _loadPage(String url, {bool fromHistory = false, bool forceRefresh = false}) async {
    _log('🌍 _loadPage CALLED with: $url (fromHistory: $fromHistory, forceRefresh: $forceRefresh)');
    
    if (url.trim().isEmpty) {
      _log('❌ _loadPage: Empty URL provided, returning');
      return;
    }
    
    // Ultra-simple URL processing
    String cleanInput = url.trim();
    String fullUrl = cleanInput.startsWith('http') ? cleanInput : 'http://$cleanInput';
    String cleanUrl = cleanInput.replaceFirst(RegExp(r'^https?://'), '');
    
    _log('🌍 _loadPage START: $fullUrl');
    _log('   - Original input: $url');
    _log('   - From history: $fromHistory');
    _log('   - Force refresh: $forceRefresh');
    _log('   - Full URL: $fullUrl');
    _log('   - Clean URL: $cleanUrl');
    _log('   - Current loading state: $_isLoading');
    DebugService.instance.logBrowser('Loading: $fullUrl');
    
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
        // Set proper baseUrl so relative links work correctly
        final baseUrl = _getBaseUrlForPage(fullUrl);
        _log('Loading data with baseUrl: $baseUrl');
        
        await _webViewController!.loadData(
          data: enhancedHtml,
          mimeType: "text/html",
          encoding: "utf8",
          baseUrl: baseUrl,
        );
      }
      
      setState(() => _progress = 1.0);
      _log('Page loaded successfully: $cleanUrl');
      
    } catch (e) {
      _log('Error loading page: $e');
      _log('ERROR in _loadPage: $e');
      _log('Stack trace: ${StackTrace.current}');
      
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

  String _cleanupAndReturn(String content) {
    // Clean up the request client
    _currentRequestClient?.close();
    _currentRequestClient = null;
    return content;
  }

  Future<String> _fetchFromBridge(String fullUrl) async {
    const maxRetries = 2;
    
    // Clean up any existing client first
    _currentRequestClient?.close();
    
    // Create a new client for this request that can be cancelled
    _currentRequestClient = http.Client();
    _log('🔧 Created new HTTP client for request: $fullUrl');
    
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        _log('🌉 Fetching from bridge (attempt ${attempt + 1}): $fullUrl');
        DebugService.instance.logHttp('Bridge request attempt ${attempt + 1}: $fullUrl');
        
        _log('Making encrypted request to bridge for: $fullUrl');
        
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

          final authService = Provider.of<AuthService>(context, listen: false);
          await authService.ensureAuthenticated();
          headers.addAll(authService.getAuthHeaders());
          
          final body = 'url=${Uri.encodeComponent(encryptedUrl)}&encrypted=true';
          
          DebugService.instance.logHttp('POST https://bridge.stormycloud.org/api/v1/browse - Encrypted request for: $fullUrl');
          final response = await _currentRequestClient!.post(
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
              return _cleanupAndReturn(content.toString());
            } catch (jsonError) {
              return _cleanupAndReturn(response.body);
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
          final authService = Provider.of<AuthService>(context, listen: false);
          await authService.ensureAuthenticated();
          headers.addAll(authService.getAuthHeaders());
          if (widget.sessionCookie != null) headers['Cookie'] = widget.sessionCookie!;
          
          DebugService.instance.logHttp('GET $browseUrl - Direct request');
          final response = await _currentRequestClient!.get(browseUrl, headers: headers).timeout(const Duration(seconds: 45));
          DebugService.instance.logHttp('Response: ${response.statusCode} (${response.body.length} bytes)');
          
          _log('Bridge response: ${response.statusCode}');          
          if (response.statusCode == 200) {
            try {
              final jsonResponse = jsonDecode(response.body);
              final content = jsonResponse['content'] ?? jsonResponse['data'] ?? response.body;
              if (content.toString().trim().isEmpty) {
                throw Exception('No content in response');
              }
              return _cleanupAndReturn(content.toString());
            } catch (jsonError) {
              return _cleanupAndReturn(response.body);
            }
          } else {
            throw Exception('Server returned ${response.statusCode}: ${response.reasonPhrase}');
          }
        }
      } catch (e) {
        _log('❌ Bridge fetch error (attempt ${attempt + 1}): $e');
        DebugService.instance.logBrowser('Bridge error attempt ${attempt + 1}: $e');
        _log('Bridge fetch error: $e');
        _log('Error type: ${e.runtimeType}');
        
        if (attempt == maxRetries) {
          _log('Max retries reached, rethrowing error');
          rethrow;
        }
        await Future.delayed(Duration(seconds: attempt + 1));
      }
    }
    
    // Clean up the request client
    _currentRequestClient?.close();
    _currentRequestClient = null;
    
    throw Exception('Failed after $maxRetries retries');
  }

  String _enhanceHtmlForMobile(String html, String baseUrl) {
    _log('Enhancing HTML for mobile (simple mode)');
    
    // Fix relative links SAFELY - no complex URI parsing
    html = _fixLinksSimple(html, baseUrl);
    
    // Add mobile CSS
    
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

  // Enhanced link fixing to handle more cases
  String _fixLinksSimple(String html, String baseUrl) {
    final baseUri = _getBaseUrlForPage(baseUrl);
    _log('Fixing links with base URI: ${baseUri?.toString() ?? 'null'}');
    
    try {
      final uri = Uri.parse(baseUrl);
      final scheme = uri.scheme;
      final host = uri.host;
      final port = uri.port != 80 && uri.port != 443 && uri.port > 0 ? ':${uri.port}' : '';
      
      // Fix href="/path" -> href="http://domain/path"  
      html = html.replaceAllMapped(
        RegExp(r'href="(/[^"]*)"', caseSensitive: false),
        (match) => 'href="$scheme://$host$port${match.group(1)}"',
      );
      
      // Fix href='/path' -> href='http://domain/path'
      html = html.replaceAllMapped(
        RegExp(r"href='(/[^']*)'", caseSensitive: false),
        (match) => "href='$scheme://$host$port${match.group(1)}'",
      );
      
      // Fix relative paths like href="page.html" -> href="http://domain/currentdir/page.html"
      final currentPath = uri.path.endsWith('/') ? uri.path : '${uri.path.substring(0, uri.path.lastIndexOf('/') + 1)}';
      
      html = html.replaceAllMapped(
        RegExp(r'href="([^":/]+(?:\.[^"]*)?)"', caseSensitive: false),
        (match) {
          final relativePath = match.group(1)!;
          if (!relativePath.startsWith('#') && !relativePath.contains('://')) {
            return 'href="$scheme://$host$port$currentPath$relativePath"';
          }
          return match.group(0)!; // Keep unchanged
        },
      );
      
      html = html.replaceAllMapped(
        RegExp(r"href='([^':/]+(?:\.[^']*)?)'", caseSensitive: false),
        (match) {
          final relativePath = match.group(1)!;
          if (!relativePath.startsWith('#') && !relativePath.contains('://')) {
            return "href='$scheme://$host$port$currentPath$relativePath'";
          }
          return match.group(0)!; // Keep unchanged
        },
      );
      
      // Fix src attributes for images too
      html = html.replaceAllMapped(
        RegExp(r'src="(/[^"]*)"', caseSensitive: false),
        (match) => 'src="$scheme://$host$port${match.group(1)}"',
      );
      
      _log('✅ Fixed relative links for: $scheme://$host$port');
      
    } catch (e) {
      _log('⚠️ Error parsing baseUrl for link fixing: $e, falling back to simple method');
      
      // Fallback to simple method
      String domain = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
      if (domain.contains('/')) {
        domain = domain.split('/')[0];
      }
      
      html = html.replaceAllMapped(
        RegExp(r'href="(/[^"]*)"', caseSensitive: false),
        (match) => 'href="http://$domain${match.group(1)}"',
      );
      
      html = html.replaceAllMapped(
        RegExp(r"href='(/[^']*)'", caseSensitive: false),
        (match) => "href='http://$domain${match.group(1)}'",
      );
    }
    
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
        <div class="debug-info">Debug Info:\nCurrent URL: $_currentUrl\nBase URL: $_currentBaseUrl\nEncryption: Always Enabled</div>
      </div>
    </body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        // Address bar, controls, etc. remain light
        _buildTopBar(context),
        const Divider(height: 1),
        Expanded(
          child: _viewInitialized
              ? _buildWebView()
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchBar(
                      hintText: 'Enter address or search',
                      leading: GestureDetector(
                        onTap: () {},
                        child: AnimatedBuilder(
                          animation: _lockAnimation,
                          builder: (context, child) {
                            return Icon(
                              _encryptionEnabled ? Icons.lock : Icons.lock_open,
                              color: ColorTween(begin: Colors.grey, end: Colors.green).evaluate(_lockAnimation),
                            );
                          },

                        ),
                      ),
                      trailing: [
                        IconButton(
                          icon: Icon(_isLoading ? Icons.stop : Icons.refresh),
                          onPressed: _isLoading ? _stop : _refresh,
                          tooltip: _isLoading ? 'Stop' : 'Refresh',
                        ),
                      ],
                      onSubmitted: (value) => _loadPage(value),
                      controller: _urlController,
                    ),
                    if (_progress > 0 && _progress < 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: LinearProgressIndicator(
                          value: _progress,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Removed quick-launch chips per feedback

          const SizedBox(height: 12),

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
    return InAppWebView(
      initialOptions: InAppWebViewGroupOptions(
        crossPlatform: InAppWebViewOptions(userAgent: appUserAgent),
      ),
      onWebViewCreated: (controller) => _webViewController = controller,
      onLoadStart: (controller, url) {
        setState(() {
          _isLoading = true;
        });
      },
      onLoadStop: (controller, url) async {
        setState(() {
          _isLoading = false;
        });
      },
      onProgressChanged: (controller, progress) {
        setState(() => _progress = progress / 100.0);
      },
    );
  }
}