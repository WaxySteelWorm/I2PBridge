// lib/pages/compose_mail_page.dart
// Production compose mail page with end-to-end encryption

import 'package:flutter/material.dart';
import '../services/pop3_mail_service.dart';

class ComposeMailPage extends StatefulWidget {
  final Pop3MailService mailService;
  final EmailMessage? replyTo;

  const ComposeMailPage({
    super.key,
    required this.mailService,
    this.replyTo,
  });

  @override
  State<ComposeMailPage> createState() => _ComposeMailPageState();
}

class _ComposeMailPageState extends State<ComposeMailPage> {
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    
    // If replying, pre-fill fields
    if (widget.replyTo != null) {
      final replyTo = widget.replyTo!;
      
      // Extract email from "Name <email>" format
      String toEmail = replyTo.from;
      final emailMatch = RegExp(r'<([^>]+)>').firstMatch(replyTo.from);
      if (emailMatch != null) {
        toEmail = emailMatch.group(1) ?? replyTo.from;
      }
      
      _toController.text = toEmail;
      _subjectController.text = widget.mailService.getReplySubject(replyTo.subject);
      _bodyController.text = widget.mailService.formatReplyBody(replyTo);
      
      // Position cursor at beginning of body for typing reply
      _bodyController.selection = TextSelection.fromPosition(
        const TextPosition(offset: 0),
      );
    }
  }

  @override
  void dispose() {
    _toController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isReply = widget.replyTo != null;
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.lock, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(isReply ? 'Encrypted Reply' : 'Encrypted Compose'),
          ],
        ),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: _sending 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.send),
            onPressed: _sending ? null : _sendMail,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Encryption status banner
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'End-to-End Encrypted Email',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                        Text(
                          'Your message will be encrypted before sending',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            TextField(
              controller: _toController,
              decoration: InputDecoration(
                labelText: 'To',
                hintText: 'recipient@mail.i2p',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: Icon(Icons.lock, color: Colors.green.shade600, size: 16),
                filled: isReply,
                fillColor: isReply ? Colors.grey.withOpacity(0.1) : null,
              ),
              keyboardType: TextInputType.emailAddress,
              readOnly: isReply,
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                labelText: 'Subject',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.subject),
                suffixIcon: Icon(Icons.lock, color: Colors.green.shade600, size: 16),
                filled: isReply,
                fillColor: isReply ? Colors.grey.withOpacity(0.1) : null,
              ),
            ),
            const SizedBox(height: 12),
            
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(Icons.lock, color: Colors.green.shade600, size: 16),
                  ),
                ),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
              ),
            ),
            const SizedBox(height: 12),
            
            // Privacy notice
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your message will be sent securely through the I2P network',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendMail() async {
    final to = _toController.text.trim();
    final subject = _subjectController.text.trim();
    final body = _bodyController.text.trim();

    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a recipient'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a subject'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a message'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      final success = await widget.mailService.sendEmail(
        to: to,
        subject: subject,
        body: body,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Message sent successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send message'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }
}