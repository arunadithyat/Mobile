import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';

class WebViewScreen extends StatefulWidget {
  final String title;
  final String url;

  const WebViewScreen({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late WebViewController _webViewController;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
            setState(() => _isLoading = false);
          },
        ),
      );

    // Inject session cookie before loading URL
    await _injectSessionCookie();
    await _webViewController.loadRequest(Uri.parse(widget.url));
  }

  Future<void> _injectSessionCookie() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cookie = prefs.getString('cookie') ?? '';
      if (cookie.isEmpty) return;

      final cookieManager = WebViewCookieManager();
      final uri = Uri.parse(AppConfig.baseUrl);

      // Parse cookie string — format: "sid=abc123; user_id=xyz"
      final cookies = cookie.split(';');
      for (final c in cookies) {
        final trimmed = c.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split('=');
        if (parts.length < 2) continue;

        final name = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();

        await cookieManager.setCookie(
          WebViewCookie(
            name: name,
            value: value,
            domain: uri.host,
            path: '/',
          ),
        );
      }
      debugPrint('[WEBVIEW] ✅ Session cookie injected');
    } catch (e) {
      debugPrint('[WEBVIEW] ❌ Cookie injection error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController.reload(),
            tooltip: "Reload",
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _webViewController),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}
