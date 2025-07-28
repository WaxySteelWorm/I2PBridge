// lib/pages/email_settings_page.dart
// Handles email-related settings like prefetch count.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmailSettingsPage extends StatefulWidget {
  const EmailSettingsPage({super.key});

  @override
  State<EmailSettingsPage> createState() => _EmailSettingsPageState();
}

class _EmailSettingsPageState extends State<EmailSettingsPage> {
  int _prefetchCount = 5; // Default prefetch count

  @override
  void initState() {
    super.initState();
    _loadPrefetchCount();
  }

  // Load the prefetch count from shared preferences
  Future<void> _loadPrefetchCount() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _prefetchCount = prefs.getInt('prefetch_count') ?? 5;
    });
  }

  // Save the prefetch count to shared preferences
  Future<void> _savePrefetchCount(int count) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('prefetch_count', count);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Email Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Prefetch Messages Setting
          const ListTile(
            title: Text(
              'Prefetch Messages',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Select the number of messages to prefetch when loading emails.',
            ),
          ),
          Slider(
            value: _prefetchCount.toDouble(),
            min: 0,
            max: 15,
            divisions: 15,
            label: '$_prefetchCount',
            onChanged: (value) {
              setState(() {
                _prefetchCount = value.toInt();
              });
            },
            onChangeEnd: (value) {
              _savePrefetchCount(value.toInt());
            },
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Current prefetch count: $_prefetchCount messages',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}