// main.dart
// This version includes a comment explaining how to adjust the logo size.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/irc_service.dart';
// import 'services/pop3_mail_service.dart';  // Removed: create mail service inside its page
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

	// Reduce web font network fetches for faster first paint and privacy
	GoogleFonts.config.allowRuntimeFetching = false;

	// Always show app startup message
	DebugService.instance.forceLog('🚀 I2P Bridge starting...');
	runApp(
		MultiProvider(
			providers: [
				ChangeNotifierProvider(create: (context) => AuthService()),
				ChangeNotifierProvider(create: (context) => IrcService()),
				// ChangeNotifierProvider(create: (context) => Pop3MailService()),  // Removed: instantiate in page when needed
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

	// Lazily created pages (to avoid heavy init on startup)
	Widget? _browserPage;
	Widget? _ircPage;
	Widget? _mailPage;
	Widget? _uploadPage;

	@override
	void initState() {
		super.initState();
		// Check server debug status when app starts (non-blocking)
		DebugService.instance.checkServerDebugStatus().then((_) {
			if (mounted) {
				setState(() {
					_showDebugBanner = DebugService.instance.serverDebugMode;
				});
			}
		});
	}

	static const List<String> _moduleTitles = <String>[
		'I2P Browser',
		'IRC Chat',
		'I2P Mail',
		'Image Upload',
	];

	Widget _getPage(int index) {
		switch (index) {
			case 0:
				return _browserPage ??= const EnhancedBrowserPage();
			case 1:
				return _ircPage ??= const IrcPage();
			case 2:
				return _mailPage ??= const MailPage();
			case 3:
				return _uploadPage ??= const UploadPage();
			default:
				return _browserPage ??= const EnhancedBrowserPage();
		}
	}

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(
				// --- HOW-TO: Adjust this value to change the logo size ---
				leadingWidth: 160,
				leading: Padding(
					// --- UPDATE: Adjusted padding to better center the logo vertically ---
					padding: const EdgeInsets.only(left: 16.0, top: 12.0, bottom: 4.0),
					child: SvgPicture.asset(stormycloudLogoAssetPath),
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
					// Main content (lazy page)
					Expanded(
						child: _getPage(_selectedIndex),
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