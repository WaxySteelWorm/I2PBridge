// lib/pages/settings_page.dart
// Adds link to the new Email Settings page.

import 'package:flutter/material.dart';
import 'irc_settings_page.dart';
import 'email_settings_page.dart'; // Import Email Settings
import 'privacy_policy_page.dart';
import 'tos_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // IRC Settings
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('IRC Settings'),
            subtitle: const Text('Set your nickname and authentication'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const IrcSettingsPage()),
              );
            },
          ),
          const Divider(),
          // Email Settings
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Email Settings'),
            subtitle: const Text('Configure email preferences like prefetch count'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const EmailSettingsPage()),
              );
            },
          ),
          const Divider(),
          // Legal Section
          const ListTile(
            title: Text('Legal', style: TextStyle(color: Colors.grey)),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const PrivacyPolicyPage()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Terms of Service'),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const TermsOfServicePage()),
              );
            },
          ),
        ],
      ),
    );
  }
}
