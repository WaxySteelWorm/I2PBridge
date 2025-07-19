// main.dart (Reverted)
import 'package:flutter/material.dart';
import 'pages/browser_page.dart';
import 'pages/upload_page.dart';
import 'pages/irc_page.dart';
import 'pages/mail_page.dart';

void main() {
  runApp(const I2PBridgeApp());
}

class I2PBridgeApp extends StatelessWidget {
  const I2PBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'I2P Bridge',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1F1F1F),
          elevation: 0,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: Color(0xFF1F1F1F),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
        ),
      ),
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

  static final List<Widget> _widgetOptions = <Widget>[
    const BrowserPage(),
    const IrcPage(),
    const MailPage(),
    const UploadPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.all(8.0),
          child: Icon(Icons.security, size: 28),
        ),
        title: Text(_moduleTitles[_selectedIndex]),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              print("Settings button pressed!");
            },
          ),
        ],
      ),
      body: Center(
        child: _widgetOptions.elementAt(_selectedIndex),
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.public), label: 'Browser'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble_outline), label: 'IRC'),
          BottomNavigationBarItem(icon: Icon(Icons.mail_outline), label: 'Mail'),
          BottomNavigationBarItem(icon: Icon(Icons.upload_file_outlined), label: 'Upload'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}
