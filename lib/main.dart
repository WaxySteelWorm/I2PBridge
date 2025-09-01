// main.dart
// This version includes a comment explaining how to adjust the logo size.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/irc_service.dart';
import 'services/pop3_mail_service.dart';  // Add this import
import 'services/debug_service.dart';
import 'services/auth_service.dart';
import 'pages/enhanced_browser_page.dart';  // Changed from browser_page.dart
import 'pages/upload_page.dart';
import 'pages/irc_page.dart';
import 'pages/mail_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'assets/stormycloud_logo.dart';

void main(List<String> args) {
  // Initialize debug service with command line arguments
  DebugService.instance.initialize(args);
  
  // Always show app startup message
  DebugService.instance.forceLog('🚀 I2P Bridge starting...');
  runApp(
    MultiProvider(  // Changed from ChangeNotifierProvider to MultiProvider
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProxyProvider<AuthService, IrcService>(
          create: (context) => IrcService(),
          update: (context, authService, ircService) {
            ircService?.setAuthService(authService);
            return ircService!;
          },
        ),
        ChangeNotifierProvider(create: (context) => Pop3MailService()),  // Add this line
      ],
      child: const I2PBridgeApp(),
    ),
  );
}

class I2PBridgeApp extends StatelessWidget {
  const I2PBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I2P Bridge',
      theme: appTheme,
      home: const MainScaffold(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _selectedIndex = 0;
  bool _showDebugBanner = false;

  @override
  void initState() {
    super.initState();
    // Check server debug status when app starts
    DebugService.instance.checkServerDebugStatus().then((_) {
      if (mounted) {
        setState(() {
          _showDebugBanner = DebugService.instance.serverDebugMode;
        });
      }
    });
    
    // Show I2P info dialog if needed
    _checkAndShowI2PInfoDialog();
  }
  
  Future<void> _checkAndShowI2PInfoDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final hideDialog = prefs.getBool('hideI2PWarning') ?? false;
    
    if (!hideDialog && mounted) {
      // Small delay to ensure the main UI is rendered first
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _showI2PInfoDialog();
      }
    }
  }
  
  void _showI2PInfoDialog() {
    bool dontShowAgain = false;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Welcome to I2P Bridge'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• The I2P network can be slow and unstable at times\n'
                    '• Connections may take 30-60 seconds to establish\n'
                    '• If your attempt fails, please try again',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: dontShowAgain,
                        onChanged: (value) {
                          setState(() {
                            dontShowAgain = value ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          "Don't show this again",
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (dontShowAgain) {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hideI2PWarning', true);
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text('OK, I Understand'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static const List<String> _moduleTitles = <String>[
    'I2P Browser',
    'IRC Chat',
    'I2P Mail',
    'Image Upload',
  ];

  final List<Widget> _pages = const [
    EnhancedBrowserPage(),  // Changed from BrowserPage()
    IrcPage(),
    MailPage(),
    UploadPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // --- HOW-TO: Adjust this value to change the logo size ---
        leadingWidth: 160,
        leading: Padding(
          // --- UPDATE: Adjusted padding to better center the logo vertically ---
          padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 4.0),
          child: SvgPicture.string(stormycloudLogoSvg),
        ),
        title: Text(_moduleTitles[_selectedIndex]),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsPage()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Server debug banner (self-dismissable)
          if (_showDebugBanner && DebugService.instance.serverDebugMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              color: Colors.orange.withOpacity(0.1),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Server debug mode active - detailed logging enabled on server',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _showDebugBanner = false),
                    child: const Text('DISMISS'),
                  )
                ],
              ),
            ),
          // Main content
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.travel_explore), label: 'Browse'),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.mail_lock), label: 'Mail'),
          NavigationDestination(icon: Icon(Icons.cloud_upload_outlined), label: 'Upload'),
        ],
      ),
    );
  }
}