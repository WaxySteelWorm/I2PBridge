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

class _EnhancedBrowserPageState extends State<EnhancedBrowserPage> with TickerProviderStateMixin {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final EncryptionService _encryption = EncryptionService();
  
  InAppWebViewController? _webViewController;
  bool _isLoading = false;
  double _progress = 0;
  String _currentUrl = '';
  String _currentBaseUrl = '';
  String _lastLoadedUrl = ''; // Track last successfully loaded URL to prevent duplicates
  bool _encryptionEnabled = true;
  late AnimationController _lockAnimationController;
  late Animation<double> _lockAnimation;
  
  final List<String> _history = [];
  int _historyIndex = -1;
  
  static const String appUserAgent = 'I2PBridge/1.0.0 (Mobile; Flutter)';
  final http.Client _httpClient = http.Client();
  http.Client? _currentRequestClient;
  
  bool get _canGoBack => _webViewController != null && _historyIndex > 0;
  bool get _canGoForward => _webViewController != null && _historyIndex < _history.length - 1;

  @override
  void initState() {
    super.initState();
    _encryption.initialize();
    
    // Initialize animation controller
    _lockAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _lockAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _lockAnimationController, curve: Curves.easeInOut),
    );
    
    // Start with encryption enabled animation
    if (_encryptionEnabled) {
      _lockAnimationController.forward();
    }

    
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(widget.initialUrl!));
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    _lockAnimationController.dispose();

    _searchController.dispose();

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
    
    // Convert query text into search URL if needed
    String fullUrl = _normalizeInputToUrl(url.trim());
    String cleanUrl = fullUrl.replaceFirst(RegExp(r'^https?://'), '');
    
    // Check if we're already loading this exact URL to prevent duplicate loads
    if (!forceRefresh && _isLoading && (fullUrl == _currentBaseUrl || fullUrl == _lastLoadedUrl)) {
      _log('⏭️ Already loading or loaded this URL, skipping duplicate load');
      return;
    }
    
    // Check if this is the same URL we just loaded (prevent infinite loops)
    if (!forceRefresh && fullUrl == _lastLoadedUrl && !_isLoading) {
      _log('⏭️ This URL was just loaded successfully, skipping duplicate');
      return;
    }
    
    _log('🌍 _loadPage START: $fullUrl');
    _log('   - Original input: $url');
    _log('   - From history: $fromHistory');
    _log('   - Force refresh: $forceRefresh');
    _log('   - Full URL: $fullUrl');
    _log('   - Clean URL: $cleanUrl');
    _log('   - Current loading state: $_isLoading');
    _log('   - Last loaded URL: $_lastLoadedUrl');
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
        
        // Mark this URL as successfully loaded to prevent duplicate loads
        _lastLoadedUrl = fullUrl;
        
        // Update the URL in the address bar
        _urlController.text = cleanUrl;
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

  // Determine whether input should be treated as a search and map to shinobi.i2p
  String _normalizeInputToUrl(String input) {
    final txt = input.trim();
    if (txt.isEmpty) return 'http://';

    bool looksLikeUrl = RegExp(r'^(https?://)').hasMatch(txt) ||
        // has a dot in first token or a known tld like .i2p
        RegExp(r'^[^\s/]+\.[^\s]+').hasMatch(txt) ||
        txt.startsWith('localhost') || txt.startsWith('127.0.0.1');

    // If it contains whitespace or no dot and not starting with a scheme, treat as search
    final containsSpace = txt.contains(RegExp(r'\s'));
    final isLikelySearch = !looksLikeUrl || containsSpace;

    if (isLikelySearch) {
      final q = Uri.encodeQueryComponent(txt);
      final searchUrl = 'http://shinobi.i2p/search?query=$q';
      _log('🔎 Treating input as search; redirecting to $searchUrl');
      return searchUrl;
    }

    // Ensure scheme
    return txt.startsWith('http') ? txt : 'http://$txt';
  }

  void _performSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    final url = 'http://shinobi.i2p/search?query=${Uri.encodeQueryComponent(q)}';
    _loadPage(url);
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
          final auth = authService.getAuthHeaders();
          headers.addAll(auth);

          
          // Server expects 'data' field when encrypted
          final body = 'data=${Uri.encodeComponent(encryptedUrl)}&encrypted=true';
          
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
          final auth = authService.getAuthHeaders();
          headers.addAll(auth);

          if (widget.sessionCookie != null) headers['Cookie'] = widget.sessionCookie!;
          
          DebugService.instance.logHttp('GET $browseUrl - Direct request');
          final response = await _currentRequestClient!.get(browseUrl, headers: headers).timeout(const Duration(seconds: 45));
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

          } else if (response.statusCode == 401 || response.statusCode == 403) {
            // Authentication error - try to handle TOKEN_OUTDATED
            try {
              final jsonResponse = jsonDecode(response.body);
              if (jsonResponse['code'] == 'TOKEN_OUTDATED') {
                _log('Token outdated - clearing and re-authenticating');
                final authService = Provider.of<AuthService>(context, listen: false);
                await authService.handleAuthError(errorResponse: jsonResponse);
                // Retry the request with new token
                if (attempt < maxRetries) {
                  continue; // Retry with new token
                }
              }
              throw Exception(jsonResponse['message'] ?? jsonResponse['error'] ?? 'Authentication failed');
            } catch (e) {
              if (e.toString().contains('TOKEN_OUTDATED')) {
                rethrow;
              }
              throw Exception('Authentication failed. Please check your API key.');
            }
          } else if (response.statusCode == 503) {
            // Service unavailable - check for custom message
            try {
              final jsonResponse = jsonDecode(response.body);
              final message = jsonResponse['message'] ?? jsonResponse['error'] ?? 'Service Unavailable';
              throw Exception(message);
            } catch (jsonError) {
              throw Exception('Service temporarily unavailable');
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
    // Check if this is a service disabled error
    bool isServiceDisabled = error.contains('temporarily disabled') || 
                            error.contains('Service Unavailable') ||
                            error.contains('service is disabled');
    
    String icon = isServiceDisabled ? '🚫' : '⚠️';
    String title = isServiceDisabled ? 'Service Temporarily Unavailable' : 'Connection Error';
    String message = error;
    
    // Clean up the error message for service disabled cases
    if (isServiceDisabled && error.contains('Exception:')) {
      message = error.replaceAll('Exception:', '').trim();
    }
    
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
          border: 1px solid ${isServiceDisabled ? '#ff9800' : '#444'};
        }
        .error-icon {
          font-size: 48px;
          margin-bottom: 16px;
        }
        h2 {
          color: ${isServiceDisabled ? '#ff9800' : '#ffffff'};
          margin: 16px 0;
        }
        p {
          margin: 12px 0;
          line-height: 1.5;
          font-size: 16px;
        }
        .retry-button {
          background: ${isServiceDisabled ? '#ff9800' : '#4A9EFF'};
          color: white;
          border: none;
          padding: 12px 24px;
          border-radius: 8px;
          font-size: 16px;
          margin-top: 16px;
          cursor: pointer;
        }
        .info-message {
          margin-top: 16px;
          padding: 12px;
          background: rgba(255, 152, 0, 0.1);
          border-radius: 8px;
          font-size: 14px;
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
        <div class="error-icon">$icon</div>
        <h2>$title</h2>
        <p>$message</p>
        ${isServiceDisabled ? '<div class="info-message">This service has been temporarily disabled by the administrator. Please try again later.</div>' : ''}
        <button class="retry-button" onclick="location.reload()">Retry</button>
        <div class="debug-info">Debug Info:\nCurrent URL: $_currentUrl\nBase URL: $_currentBaseUrl\nEncryption: Always Enabled</div>
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
                    const SizedBox(height: 8),
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

          const SizedBox(height: 6),

          // Removed quick-launch chips per feedback
          // Landing content will be rendered inside the webview area when no history

          const SizedBox(height: 6),

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
      return _buildLanding();
    }

    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        userAgent: appUserAgent,
        javaScriptEnabled: true,
        transparentBackground: true,
        supportZoom: true,
        cacheEnabled: true, // Enable caching to reduce redundant requests
        // iOS specific settings
        allowsInlineMediaPlayback: true,
        allowsBackForwardNavigationGestures: true,
        // Better navigation handling
        useShouldOverrideUrlLoading: true,
        useOnLoadResource: true,
      ),
      onWebViewCreated: (controller) {
        _webViewController = controller;
        
        // Add JavaScript handler for link clicks
        controller.addJavaScriptHandler(
          handlerName: 'linkClicked',
          callback: (args) {
            _log('🔗 JavaScript handler called with args: $args');
            if (args.isNotEmpty) {
              final url = args[0].toString();
              _log('🔗 JavaScript link click detected: $url');
              DebugService.instance.logBrowser('Link click from JS: $url');
              
              // Call _loadPage directly - no need for postFrameCallback
              _log('🔄 Processing JavaScript link click: $url');
              _loadPage(url);
            } else {
              _log('❌ JavaScript handler called with no arguments');
            }
          },
        );
        
        _log('WebView controller initialized with link handler');
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
        
        // Inject request throttling JavaScript first
        _log('🔧 Injecting request throttling JavaScript');
        try {
          await controller.evaluateJavascript(source: '''
          (function() {
            console.log('🚦 Installing request throttling...');
            
            // Request throttling configuration
            const THROTTLE_DELAY = 500; // Minimum 500ms between requests
            const CACHE_DURATION = 5000; // Cache responses for 5 seconds
            const MAX_REQUESTS_PER_SECOND = 2;
            
            // Request queue and cache
            const requestQueue = [];
            const responseCache = new Map();
            const requestTimestamps = [];
            let isProcessing = false;
            
            // Helper to create cache key
            function getCacheKey(url, options) {
              return url + JSON.stringify(options || {});
            }
            
            // Helper to check if we're rate limited
            function isRateLimited() {
              const now = Date.now();
              // Remove timestamps older than 1 second
              while (requestTimestamps.length > 0 && requestTimestamps[0] < now - 1000) {
                requestTimestamps.shift();
              }
              return requestTimestamps.length >= MAX_REQUESTS_PER_SECOND;
            }
            
            // Process request queue
            async function processQueue() {
              if (isProcessing || requestQueue.length === 0) return;
              isProcessing = true;
              
              while (requestQueue.length > 0) {
                if (isRateLimited()) {
                  // Wait before processing next request
                  await new Promise(resolve => setTimeout(resolve, THROTTLE_DELAY));
                  continue;
                }
                
                const { url, options, resolve, reject } = requestQueue.shift();
                const cacheKey = getCacheKey(url, options);
                
                // Check cache first
                const cached = responseCache.get(cacheKey);
                if (cached && Date.now() - cached.timestamp < CACHE_DURATION) {
                  console.log('📦 Returning cached response for:', url);
                  resolve(cached.response.clone());
                  continue;
                }
                
                try {
                  // Record timestamp
                  requestTimestamps.push(Date.now());
                  
                  // Special handling for known problematic endpoints
                  if (url.includes('/favorites/') || url.includes('/poll/') || url.includes('/heartbeat/')) {
                    console.log('⚠️ Throttling problematic endpoint:', url);
                    await new Promise(resolve => setTimeout(resolve, 2000)); // Extra delay for these
                  }
                  
                  console.log('🌐 Making throttled request to:', url);
                  const response = await window.originalFetch(url, options);
                  
                  // Cache successful responses
                  if (response.ok && (!options || options.method === 'GET' || !options.method)) {
                    responseCache.set(cacheKey, {
                      response: response.clone(),
                      timestamp: Date.now()
                    });
                    
                    // Clean old cache entries
                    for (const [key, value] of responseCache.entries()) {
                      if (Date.now() - value.timestamp > CACHE_DURATION * 2) {
                        responseCache.delete(key);
                      }
                    }
                  }
                  
                  resolve(response);
                } catch (error) {
                  reject(error);
                }
                
                // Minimum delay between requests
                if (requestQueue.length > 0) {
                  await new Promise(resolve => setTimeout(resolve, THROTTLE_DELAY));
                }
              }
              
              isProcessing = false;
            }
            
            // Store original fetch
            if (!window.originalFetch) {
              window.originalFetch = window.fetch;
              
              // Override fetch with throttled version
              window.fetch = function(url, options) {
                // Convert relative URLs to absolute
                if (typeof url === 'string' && !url.startsWith('http')) {
                  url = new URL(url, window.location.href).href;
                }
                
                return new Promise((resolve, reject) => {
                  requestQueue.push({ url, options, resolve, reject });
                  processQueue();
                });
              };
              
              console.log('✅ Fetch throttling installed');
            }
            
            // Override XMLHttpRequest
            const OriginalXHR = window.XMLHttpRequest;
            if (!window.XMLHttpRequestOriginal) {
              window.XMLHttpRequestOriginal = OriginalXHR;
              
              window.XMLHttpRequest = function() {
                const xhr = new OriginalXHR();
                const originalOpen = xhr.open;
                const originalSend = xhr.send;
                
                xhr.open = function(method, url, ...args) {
                  this._url = url;
                  this._method = method;
                  return originalOpen.call(this, method, url, ...args);
                };
                
                xhr.send = function(data) {
                  const url = this._url;
                  const method = this._method;
                  
                  // Log and potentially throttle
                  console.log('📡 XHR request intercepted:', method, url);
                  
                  // Add delay for problematic endpoints
                  if (url && (url.includes('/favorites/') || url.includes('/poll/'))) {
                    console.log('⏱️ Delaying XHR request to:', url);
                    setTimeout(() => originalSend.call(this, data), 2000);
                  } else {
                    return originalSend.call(this, data);
                  }
                };
                
                return xhr;
              };
              
              console.log('✅ XMLHttpRequest throttling installed');
            }
            
            console.log('🚦 Request throttling fully configured');
            
            // Prevent rapid page reloads
            let lastReloadTime = 0;
            const MIN_RELOAD_INTERVAL = 5000; // 5 seconds minimum between reloads
            
            // Override location.reload
            const originalReload = window.location.reload;
            window.location.reload = function() {
              const now = Date.now();
              if (now - lastReloadTime < MIN_RELOAD_INTERVAL) {
                console.warn('⛔ Blocked rapid reload attempt');
                return;
              }
              lastReloadTime = now;
              console.log('🔄 Allowing reload after cooldown');
              return originalReload.call(window.location);
            };
            
            // Monitor location.href changes
            let lastLocationChange = 0;
            const originalLocationSetter = Object.getOwnPropertyDescriptor(window.location, 'href').set;
            Object.defineProperty(window.location, 'href', {
              set: function(value) {
                const now = Date.now();
                if (now - lastLocationChange < MIN_RELOAD_INTERVAL && value === window.location.href) {
                  console.warn('⛔ Blocked rapid navigation to same URL:', value);
                  return;
                }
                lastLocationChange = now;
                console.log('🔗 Allowing navigation to:', value);
                return originalLocationSetter.call(window.location, value);
              },
              get: function() {
                return window.location.toString();
              }
            });
            
            // Block meta refresh tags that are too aggressive
            document.querySelectorAll('meta[http-equiv="refresh"]').forEach(meta => {
              const content = meta.getAttribute('content');
              if (content) {
                const seconds = parseInt(content.split(';')[0]);
                if (seconds < 5) {
                  console.warn('⛔ Removing aggressive meta refresh tag with interval:', seconds);
                  meta.remove();
                }
              }
            });
            
            console.log('🛡️ Page reload protection installed');
          })();
          ''');
          _log('✓ Request throttling and reload protection JavaScript injected');
        } catch (e) {
          _log('❌ Failed to inject throttling JavaScript: $e');
        }
        
        // Inject comprehensive link handling JavaScript
        _log('🔧 Injecting link handling JavaScript');
        
        try {
          await controller.evaluateJavascript(source: '''
          (function() {
            console.log('🚀 I2P Browser link handler starting...');
            console.log('🔍 Checking flutter_inappwebview availability:', typeof window.flutter_inappwebview);
            
            // Remove any existing listeners
            if (window.i2pLinkHandler) {
              document.removeEventListener('click', window.i2pLinkHandler, true);
              console.log('🧹 Removed existing link handler');
            }
            
            // Create comprehensive link click handler
            window.i2pLinkHandler = function(e) {
              console.log('Click detected on:', e.target.tagName, e.target.href || 'no href');
              
              var target = e.target;
              var attempts = 0;
              
              // Walk up the DOM tree to find an anchor tag (max 5 levels)
              while (target && target.tagName !== 'A' && attempts < 5) {
                target = target.parentElement;
                attempts++;
                if (target) {
                  console.log('Walking up to:', target.tagName);
                }
              }
              
              if (target && target.tagName === 'A' && target.href) {
                console.log('Found anchor with href:', target.href);
                
                // Skip anchor links (#section)
                if (target.href.indexOf('#') === target.href.length - target.href.split('#')[1].length - 1 && 
                    target.href.split('#')[1] && 
                    target.href.split('#')[0] === window.location.href.split('#')[0]) {
                  console.log('Ignoring anchor link:', target.href);
                  return;
                }
                
                // Skip javascript: links
                if (target.href.toLowerCase().startsWith('javascript:')) {
                  console.log('Ignoring javascript link:', target.href);
                  return;
                }
                
                // Skip mailto: links
                if (target.href.toLowerCase().startsWith('mailto:')) {
                  console.log('Ignoring mailto link:', target.href);
                  return;
                }
                
                console.log('🚫 Preventing default and calling Flutter handler');
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
                
                // Multiple attempts to call the handler
                var handlerCalled = false;
                
                // Method 1: Direct handler call
                try {
                  if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
                    window.flutter_inappwebview.callHandler('linkClicked', target.href);
                    console.log('✅ Successfully called Flutter handler with:', target.href);
                    handlerCalled = true;
                  } else {
                    console.log('❌ flutter_inappwebview not available');
                  }
                } catch (err) {
                  console.error('❌ Error calling Flutter handler:', err);
                }
                
                // Method 2: Fallback using window.location (will trigger shouldOverrideUrlLoading)
                if (!handlerCalled) {
                  console.log('🔄 Fallback: Using window.location navigation');
                  setTimeout(function() {
                    try {
                      window.location.href = target.href;
                    } catch (err) {
                      console.error('❌ Fallback navigation failed:', err);
                    }
                  }, 100);
                }
                
                return false;
              } else {
                console.log('No valid anchor found after walking up DOM');
              }
            };
            
            // Add click listener with capture=true to catch early
            document.addEventListener('click', window.i2pLinkHandler, true);
            
            var linkCount = document.querySelectorAll('a[href]').length;
            console.log('I2P link handler installed. Found', linkCount, 'links on page');
            
            // Debug: Log all links found
            var allLinks = document.querySelectorAll('a[href]');
            for (var i = 0; i < Math.min(allLinks.length, 10); i++) {
              console.log('Link', i + ':', allLinks[i].href);
            }
            if (allLinks.length > 10) {
              console.log('... and', allLinks.length - 10, 'more links');
            }
          })();
          ''');
        
          _log('✓ Link handling JavaScript injection completed');
        
        } catch (jsError) {
          _log('❌ JavaScript injection failed: $jsError');
        }
        
        setState(() {
          _isLoading = false;
          _progress = 1.0;
        });
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final uri = navigationAction.request.url!;
        final url = uri.toString();
        final navigationType = navigationAction.navigationType;
        final isUserInitiated = navigationAction.isForMainFrame;
        
        _log('🧭 Navigation attempt: $url');
        _log('   - Type: $navigationType');
        _log('   - Main frame: $isUserInitiated');
        _log('   - Current URL: $_currentUrl');
        _log('   - Loading state: $_isLoading');
        DebugService.instance.logBrowser('Navigation: $url (type: $navigationType)');
        
        // Allow data URLs and about:blank - these are needed for our loadData calls
        if (url.startsWith('data:') || url.startsWith('about:blank')) {
          final displayUrl = url.length > 50 ? '${url.substring(0, 50)}...' : url;
          _log('✅ Allowing data/blank URL: $displayUrl');
          return NavigationActionPolicy.ALLOW;
        }
        
        // For HTTP/HTTPS URLs, only intercept if it's a user-initiated navigation (link click)
        // and not an automatic redirect or refresh
        if (url.startsWith('http://') || url.startsWith('https://')) {
          // Check if this is the same URL we just loaded - prevent loops
          if (url == _currentUrl || url == 'http://$_currentUrl' || url == _currentBaseUrl) {
            _log('⏭️ Same URL as current, allowing to prevent loop');
            return NavigationActionPolicy.ALLOW;
          }
          
          // ONLY intercept true user-initiated actions
          // LINK_ACTIVATED: User clicked a link
          // FORM_SUBMITTED: User submitted a form
          // Do NOT intercept OTHER - let JavaScript navigation happen naturally
          if (navigationType == NavigationType.LINK_ACTIVATED || 
              navigationType == NavigationType.FORM_SUBMITTED) {
            _log('🚫 Intercepting user action (${navigationType.toString()}) to load through bridge: $url');
            DebugService.instance.logBrowser('Intercepting user navigation: $url');
            
            // Load the page immediately
            _loadPage(url);
            
            return NavigationActionPolicy.CANCEL;
          }
          
          // Allow other navigation types (reload, back/forward)
          _log('✅ Allowing navigation type: $navigationType');
          return NavigationActionPolicy.ALLOW;
        }
        
        // Log and allow other protocols
        _log('✅ Allowing other protocol: $url');
        return NavigationActionPolicy.ALLOW;
      },
      onConsoleMessage: (controller, consoleMessage) {
        _log('📝 JS Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
        DebugService.instance.logBrowser('JS Console: ${consoleMessage.message}');
      },
    );
  }

  Widget _buildLanding() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          // Search area inside card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Search the I2P network',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const SizedBox(height: 8),
                  // Framed search to make it pop a bit more
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: SearchBar(
                      hintText: 'Search shinobi.i2p',
                      leading: const Icon(Icons.search),
                      onSubmitted: _performSearch,
                      controller: _searchController,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type a query and press enter to search via shinobi.i2p, or paste any .i2p address in the bar above to browse directly.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Popular sites
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Popular I2P sites', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double cardPadding = 12;
                      final double gap = 8;
                      final double itemWidth = (constraints.maxWidth - cardPadding*2 - gap) / 2;
                      return Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: [
                          for (final site in popularSites.take(4))
                            SizedBox(
                              width: itemWidth,
                              child: InkWell(
                                onTap: () => _loadPage(site.url),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.language, size: 18, color: Colors.blueAccent),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(site.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 2),
                                            Text(
                                              site.description,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}