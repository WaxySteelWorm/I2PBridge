// lib/pages/irc_settings_page.dart
// This version adds a switch to hide join/quit messages.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IrcSettingsPage extends StatefulWidget {
  const IrcSettingsPage({super.key});

  @override
  State<IrcSettingsPage> createState() => _IrcSettingsPageState();
}

class _IrcSettingsPageState extends State<IrcSettingsPage> {
  final _nickController = TextEditingController();
  final _passwordController = TextEditingController();
  // --- NEW: State for the switch ---
  bool _hideJoinQuit = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nickController.text = prefs.getString('irc_nickname') ?? 'i2p-user';
      _passwordController.text = prefs.getString('irc_password') ?? '';
      _hideJoinQuit = prefs.getBool('irc_hide_join_quit') ?? false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('irc_nickname', _nickController.text);
    await prefs.setString('irc_password', _passwordController.text);
    await prefs.setBool('irc_hide_join_quit', _hideJoinQuit);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings Saved!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('IRC Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            controller: _nickController,
            decoration: const InputDecoration(
              labelText: 'Default Nickname',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'NickServ Password (optional)',
              helperText: 'Used to automatically identify with NickServ on connect.',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          // --- NEW: UI for the switch ---
          SwitchListTile(
            title: const Text('Hide Join/Quit Messages'),
            subtitle: const Text('Reduces clutter in busy channels.'),
            value: _hideJoinQuit,
            onChanged: (bool value) {
              setState(() {
                _hideJoinQuit = value;
              });
            },
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _saveSettings,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text('Save Settings'),
          )
        ],
      ),
    );
  }
}
