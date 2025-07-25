// lib/pages/read_mail_page.dart
// Read mail page for I2P Bridge app

import 'package:flutter/material.dart';
import '../services/pop3_mail_service.dart';
import 'compose_mail_page.dart';

class ReadMailPage extends StatelessWidget {
  final EmailMessage message;
  final Pop3MailService mailService;

  const ReadMailPage({
    super.key,
    required this.message,
    required this.mailService,
  });

  @override
  Widget build(BuildContext context) {
    // Check if message is encrypted
    final bool isEncrypted = message.body.contains('-----BEGIN PGP MESSAGE-----') ||
        message.body.contains('Content-Type: multipart/encrypted') ||
        message.subject == '(Encrypted)' ||
        message.subject.contains('...');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Read Mail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.reply),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ComposeMailPage(
                    mailService: mailService,
                    replyTo: message,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              // TODO: Implement delete
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Delete feature coming soon')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Message header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blueAccent.withOpacity(0.2),
                        child: Text(
                          message.from.isNotEmpty 
                            ? message.from[0].toUpperCase()
                            : '?',
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'From',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              message.from,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Subject',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (isEncrypted) ...[
                            Icon(
                              Icons.lock,
                              size: 16,
                              color: Colors.orange.shade600,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              message.subject,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message.date,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // Encrypted message notice
            if (isEncrypted) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Encrypted Message',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'This message is PGP encrypted. You\'ll need to decrypt it with your private key.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
            
            // Message body
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.2)),
              ),
              child: SelectableText(
                message.body.isEmpty ? '(No content)' : message.body,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  fontFamily: isEncrypted || message.body.contains('-----BEGIN') 
                    ? 'monospace' 
                    : null,
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Message info
            Text(
              'Message size: ${_formatBytes(message.size)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}