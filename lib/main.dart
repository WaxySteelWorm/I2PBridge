// main.dart
// This version includes a comment explaining how to adjust the logo size.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'services/irc_service.dart';
import 'pages/browser_page.dart';
import 'pages/upload_page.dart';
import 'pages/irc_page.dart';
import 'pages/mail_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'assets/stormycloud_logo.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => IrcService(),
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

  static const List<String> _moduleTitles = <String>[
    'HTTP Browser',
    'IRC Chat',
    'I2P Mail',
    'Image Upload',
  ];

  final List<Widget> _pages = const [
    BrowserPage(),
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
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
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
