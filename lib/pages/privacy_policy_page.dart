// lib/pages/privacy_policy_page.dart

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../assets/privacy_policy_text.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
      ),
      body: const Markdown(
        data: privacyPolicyText,
        padding: EdgeInsets.all(16.0),
      ),
    );
  }
}
