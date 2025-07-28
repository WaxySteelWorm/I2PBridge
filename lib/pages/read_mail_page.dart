// lib/pages/read_mail_page.dart
// Read mail page with improved styling and UX

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../services/pop3_mail_service.dart';
import 'compose_mail_page.dart';

class ReadMailPage extends StatefulWidget {
  final EmailMessage message;
  final Pop3MailService mailService;

  const ReadMailPage({
    super.key,
    required this.message,
    required this.mailService,
  });

  @override
  State<ReadMailPage> createState() => _ReadMailPageState();
}

class _ReadMailPageState extends State<ReadMailPage> {
  bool _showHtml = false;
  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final hasHtmlContent = message.htmlBody != null && message.htmlBody!.isNotEmpty;
    
    // Check if message is encrypted
    final bool isEncrypted = message.body.contains('-----BEGIN PGP MESSAGE-----') ||
        message.body.contains('Content-Type: multipart/encrypted') ||
        message.subject == '(Encrypted)' ||
        message.subject.contains('...');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Read Mail'),
        actions: [
          // Toggle HTML/Plain text if HTML is available
          if (hasHtmlContent && !isEncrypted)
            IconButton(
              icon: Icon(_showHtml ? Icons.text_fields : Icons.web),
              tooltip: _showHtml ? 'Show plain text' : 'Show HTML',
              onPressed: () {
                setState(() {
                  _showHtml = !_showHtml;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.reply),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ComposeMailPage(
                    mailService: widget.mailService,
                    replyTo: message,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: _isDeleting 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.delete),
            onPressed: _isDeleting ? null : () => _deleteMessage(context),
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
                          _getDisplayName(message.from).isNotEmpty 
                            ? _getDisplayName(message.from)[0].toUpperCase()
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
                              _getDisplayName(message.from),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_getEmailAddress(message.from) != _getDisplayName(message.from))
                              Text(
                                _getEmailAddress(message.from),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade600,
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
            
            // Content type indicator
            if (hasHtmlContent && !isEncrypted) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showHtml ? Icons.web : Icons.text_fields,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _showHtml ? 'HTML View' : 'Plain Text View',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            
            // Attachments section with improved styling
            if (message.attachments.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.attach_file, 
                          size: 20, 
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Attachments (${message.attachments.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...message.attachments.asMap().entries.map((entry) {
                      final index = entry.key;
                      final attachment = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                _getAttachmentIcon(attachment.contentType),
                                size: 20,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    attachment.filename ?? 'Unnamed attachment',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${attachment.contentType} • ${_formatBytes(attachment.size)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.blue.shade700,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: IconButton(
                                icon: const Icon(Icons.download, color: Colors.white),
                                onPressed: () => _downloadAttachment(attachment, index),
                                tooltip: 'Download attachment',
                                constraints: const BoxConstraints(
                                  minWidth: 36,
                                  minHeight: 36,
                                ),
                                padding: const EdgeInsets.all(6),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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
              child: _buildMessageContent(message, isEncrypted),
            ),
            
            const SizedBox(height: 20),
            
            // Message info
            Row(
              children: [
                Text(
                  'Message size: ${_formatBytes(message.size)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const Spacer(),
                if (message.attachments.isNotEmpty)
                  Text(
                    '${message.attachments.length} attachment${message.attachments.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Extract display name from email address
  String _getDisplayName(String fromAddress) {
    // Handle "Name <email>" format
    final match = RegExp(r'^(.+?)\s*<.+>$').firstMatch(fromAddress);
    if (match != null) {
      return match.group(1)?.replaceAll('"', '').trim() ?? fromAddress;
    }
    
    // Handle plain email address
    if (fromAddress.contains('@')) {
      return fromAddress.split('@')[0];
    }
    
    return fromAddress;
  }

  // Extract email address from from field
  String _getEmailAddress(String fromAddress) {
    // Handle "Name <email>" format
    final match = RegExp(r'<([^>]+)>').firstMatch(fromAddress);
    if (match != null) {
      return match.group(1) ?? fromAddress;
    }
    
    // Return as-is if it's already just an email
    return fromAddress;
  }
  
  Future<void> _deleteMessage(BuildContext context) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      setState(() {
        _isDeleting = true;
      });

      // Close the message view immediately for better UX
      Navigator.pop(context);
      
      // Show a snackbar to indicate deletion is in progress
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 12),
              Text('Deleting message...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );

      // Delete in background
      final success = await widget.mailService.deleteMessage(widget.message.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message deleted'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to delete message'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
  
  Future<void> _downloadAttachment(EmailAttachment attachment, int index) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Text('Downloading ${attachment.filename ?? 'attachment'}...'),
            ],
          ),
          duration: const Duration(seconds: 10),
        ),
      );
      
      // TODO: Implement actual download from server
      await Future.delayed(const Duration(seconds: 2));
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download of ${attachment.filename ?? 'attachment'} completed'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('File opening not yet implemented'),
                  ),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download attachment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  Widget _buildMessageContent(EmailMessage message, bool isEncrypted) {
    // Show HTML content if available and selected
    if (_showHtml && message.htmlBody != null && !isEncrypted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HTML content warning
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber,
                  size: 16,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'HTML content - external links may not work in I2P',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // HTML content
          Html(
            data: message.htmlBody!,
            style: {
              "body": Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(14),
                lineHeight: const LineHeight(1.5),
              ),
              "p": Style(
                margin: Margins.only(bottom: 12),
              ),
              "blockquote": Style(
                margin: Margins.only(left: 16, top: 8, bottom: 8),
                padding: HtmlPaddings.only(left: 12),
                border: Border(
                  left: BorderSide(
                    color: Colors.grey.shade400,
                    width: 3,
                  ),
                ),
                backgroundColor: Colors.grey.shade50,
              ),
              "a": Style(
                color: Colors.blue,
                textDecoration: TextDecoration.underline,
              ),
              "pre": Style(
                backgroundColor: Colors.grey.shade100,
                padding: HtmlPaddings.all(8),
                margin: Margins.symmetric(vertical: 8),
                fontFamily: 'monospace',
                fontSize: FontSize(13),
              ),
              "code": Style(
                backgroundColor: Colors.grey.shade100,
                padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 2),
                fontFamily: 'monospace',
                fontSize: FontSize(13),
              ),
            },
            onLinkTap: (url, attributes, element) {
              if (url != null) {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('External Link'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('This email contains a link to:'),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: SelectableText(
                            url,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'External links may not work in I2P. Only .i2p domains are accessible.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        ],
      );
    }
    
    // Otherwise show plain text
    return SelectableText(
      message.body.isEmpty ? '(No content)' : message.body,
      style: TextStyle(
        fontSize: 14,
        height: 1.5,
        fontFamily: isEncrypted || message.body.contains('-----BEGIN') 
          ? 'monospace' 
          : null,
      ),
    );
  }
  
  IconData _getAttachmentIcon(String contentType) {
    if (contentType.startsWith('image/')) return Icons.image;
    if (contentType.startsWith('text/')) return Icons.description;
    if (contentType.contains('pdf')) return Icons.picture_as_pdf;
    if (contentType.contains('zip') || contentType.contains('archive') || contentType.contains('compressed')) return Icons.archive;
    if (contentType.startsWith('audio/')) return Icons.audiotrack;
    if (contentType.startsWith('video/')) return Icons.videocam;
    if (contentType.contains('word') || contentType.contains('document')) return Icons.article;
    if (contentType.contains('spreadsheet') || contentType.contains('excel')) return Icons.table_chart;
    if (contentType.contains('presentation') || contentType.contains('powerpoint')) return Icons.slideshow;
    if (contentType.contains('pgp') || contentType.contains('encrypted')) return Icons.lock;
    return Icons.attach_file;
  }
  
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}