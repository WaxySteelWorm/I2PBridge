// lib/pages/settings_page.dart
// This version adds links to the new Privacy Policy and TOS pages.

import 'package:flutter/material.dart';
import 'irc_settings_page.dart';
import 'privacy_policy_page.dart'; // Import new page
import 'tos_page.dart'; // Import new page

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
          // --- NEW: Legal Section ---
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
