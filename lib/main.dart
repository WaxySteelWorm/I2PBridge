// main.dart
// This version includes a comment explaining how to adjust the logo size.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
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
        ChangeNotifierProvider(create: (context) => IrcService()),
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

  @override
  void initState() {
    super.initState();
    // Check server debug status when app starts
    DebugService.instance.checkServerDebugStatus().then((_) {
      // Rebuild UI if server debug mode was detected
      if (mounted) setState(() {});
    });
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
          // Server debug banner
          if (DebugService.instance.serverDebugMode)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.orange.shade100,
              child: Row(
                children: [
                  Icon(
                    Icons.bug_report,
                    size: 16,
                    color: Colors.orange.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Server debug mode active - detailed logging enabled on server',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange.shade800,
                      ),
                      
                    ),
                  ),
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
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Browser'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'IRC'),
          BottomNavigationBarItem(icon: Icon(Icons.mail_outline), label: 'Mail'),
          BottomNavigationBarItem(icon: Icon(Icons.upload_file_outlined), label: 'Upload'),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}