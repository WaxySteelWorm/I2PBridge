// lib/pages/browser_page.dart
// This version fixes a typo in an import statement.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../data/popular_sites.dart';

class BrowserPage extends StatefulWidget {
  final String? initialUrl;
  final String? sessionCookie;
  const BrowserPage({this.initialUrl, this.sessionCookie, super.key});
  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  final TextEditingController _urlController = TextEditingController();
  String? _pageContent;
  String _contentType = 'text/html';
  bool _isLoading = false;
  final List<String> _history = [];
  int _historyIndex = -1;
  final Map<String, String> _cache = {};
  
  bool get _canGoBack {
    return _historyIndex > 0 || (_historyIndex == 0 && _pageContent != null);
  }
  bool get _canGoForward => _historyIndex < _history.length - 1;
  bool get _canRefresh => _history.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget.initialUrl != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPage(widget.initialUrl!));
    }
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

  void _goForward() { if (_canGoForward) setState(() { _historyIndex++; _loadPage(_history[_historyIndex], fromHistory: true); }); }
  void _refresh() { if (_canRefresh) _loadPage(_history[_historyIndex], fromHistory: true, forceRefresh: true); }
  
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
    
    setState(() { _isLoading = true; _pageContent = 'Loading $cleanUrl...'; _contentType = 'text/html'; _urlController.text = cleanUrl; });

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

    final Uri browseUrl = Uri.parse('http://bridge.stormycloud.org:3000/api/v1/browse?url=$cleanUrl');

    try {
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
          Row(
            children: [
              IconButton( icon: const Icon(Icons.arrow_back), onPressed: _canGoBack ? _goBack : null, ),
              IconButton( icon: const Icon(Icons.arrow_forward), onPressed: _canGoForward ? _goForward : null, ),
              IconButton( icon: const Icon(Icons.refresh), onPressed: _isLoading || !_canRefresh ? null : _refresh, ),
              Expanded( child: TextField( controller: _urlController, decoration: const InputDecoration( hintText: 'stats.i2p' ), onSubmitted: (value) => _loadPage(value), ), ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox( width: double.infinity, child: ElevatedButton( onPressed: _isLoading ? null : () => _loadPage(_urlController.text), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Go'), ), ),
          const SizedBox(height: 20),
          Expanded( child: Card(
            child: _pageContent == null
              ? _buildPopularSitesList()
              : _isLoading
                ? Center(child: Text(_pageContent!))
                : _contentType.startsWith('image/')
                    ? Center(child: CachedNetworkImage(imageUrl: 'http://bridge.stormycloud.org:3000/api/v1/browse?url=$currentUrl', placeholder: (context, url) => const CircularProgressIndicator(), errorWidget: (context, url, error) => const Text('[Image failed to load]')))
                    : HtmlWidget( _pageContent!, renderMode: RenderMode.listView, customWidgetBuilder: (element) { if (element.localName == 'img') { final src = element.attributes['src']; if (src != null) { if (src.startsWith('data:image')) { try { final parts = src.split(','); final imageBytes = base64Decode(parts[1]); return Image.memory(imageBytes); } catch (e) { return const Text('[Invalid Image Data]'); } } final currentUri = Uri.parse('http://$currentUrl'); final imageUrl = currentUri.resolve(src).toString(); final proxiedUrl = 'http://bridge.stormycloud.org:3000/api/v1/browse?url=${imageUrl.replaceFirst(RegExp(r'^https?://'), '')}'; if (proxiedUrl.endsWith('.svg')) { return SvgPicture.network( proxiedUrl, colorFilter: ColorFilter.mode(svgColor, BlendMode.srcIn), placeholderBuilder: (context) => const CircularProgressIndicator(), ); } else { return CachedNetworkImage( imageUrl: proxiedUrl, placeholder: (context, url) => const CircularProgressIndicator(), errorWidget: (context, url, error) => const Text('[Image failed to load]'), ); } } } return null; }, onTapUrl: (url) { _loadPage(url); return true; }, textStyle: const TextStyle(color: Colors.white), ),
          ), ),
        ],
      ),
    );
  }

  Widget _buildPopularSitesList() {
    return ListView.builder(
      itemCount: popularSites.length,
      itemBuilder: (context, index) {
        final site = popularSites[index];
        return ListTile(
          title: Text(site.name, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
          subtitle: Text(site.description, style: const TextStyle(color: Colors.grey)),
          onTap: () => _loadPage(site.url),
        );
      },
    );
  }
}
