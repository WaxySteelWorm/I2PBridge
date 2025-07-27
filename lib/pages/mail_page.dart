// lib/pages/mail_page.dart
// I2P Mail client with POP3/SMTP

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/pop3_mail_service.dart';
import 'compose_mail_page.dart';
import 'read_mail_page.dart';

class MailPage extends StatefulWidget {
  const MailPage({super.key});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late Pop3MailService _mailService;
  
  @override
  void initState() {
    super.initState();
    _mailService = Pop3MailService();
  }
  
  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _mailService.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _mailService,
      child: Consumer<Pop3MailService>(
        builder: (context, mailService, child) {
          if (!mailService.isConnected) {
            return _buildLoginView(context, mailService);
          }
          return _buildInboxView(context, mailService);
        },
      ),
    );
  }
  
  Widget _buildLoginView(BuildContext context, Pop3MailService mailService) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mail_outline, size: 80, color: Colors.blueAccent),
          const SizedBox(height: 24),
          // Privacy info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Column(
              children: const [
                Icon(Icons.lock, color: Colors.green, size: 24),
                SizedBox(height: 8),
                Text(
                  'Secure I2P Mail',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  '• Encrypted connection to mail server',
                  style: TextStyle(fontSize: 13),
                ),
                Text(
                  '• Messages parsed server-side for security',
                  style: TextStyle(fontSize: 13),
                ),
                Text(
                  '• No local storage on device',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
              hintText: 'username',
              helperText: 'Just your username, not @mail.i2p',
            ),
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: mailService.isLoading ? null : () async {
              final username = _usernameController.text.trim();
              final password = _passwordController.text;
              
              if (username.isEmpty || password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter username and password'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              
              final success = await mailService.connect(username, password);
              if (!success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(mailService.lastError.isNotEmpty 
                      ? mailService.lastError 
                      : 'Login failed. Check your credentials.'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            },
            icon: mailService.isLoading 
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.login),
            label: Text(mailService.isLoading ? 'Connecting...' : 'Login'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          _buildStatusMessage(mailService),
          _buildDebugSection(mailService),
          const SizedBox(height: 16),
          const Text(
            'Need an account? Create one at:\nhttp://127.0.0.1:7657/susimail/',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage(Pop3MailService mailService) {
    if (mailService.statusMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mailService.statusMessage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDebugSection(Pop3MailService mailService) {
    if (!mailService.debugMode || mailService.debugLog.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      children: [
        const SizedBox(height: 16),
        TextButton.icon(
          onPressed: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (context) => Container(
                height: MediaQuery.of(context).size.height * 0.7,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Debug Log',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: mailService.debugLog.length,
                        itemBuilder: (context, index) {
                          return Text(
                            mailService.debugLog[index],
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          icon: const Icon(Icons.bug_report),
          label: Text('View Debug Log (${mailService.debugLog.length})'),
        ),
      ],
    );
  }
  
  Widget _buildInboxView(BuildContext context, Pop3MailService mailService) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.inbox, color: Colors.blueAccent),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Inbox',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${mailService.username}@mail.i2p',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: mailService.isLoading ? null : () => mailService.refresh(),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => mailService.disconnect(),
              ),
            ],
          ),
        ),
        
        // Message list
        Expanded(
          child: Column(
            children: [
              _buildLoadingIndicator(mailService),
              Expanded(
                child: _buildMessageList(mailService),
              ),
            ],
          ),
        ),
        
        // Compose button
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ComposeMailPage(
                    mailService: mailService,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.create),
            label: const Text('Compose'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingIndicator(Pop3MailService mailService) {
    if (mailService.statusMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mailService.statusMessage,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(Pop3MailService mailService) {
    if (mailService.isLoading && mailService.messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (mailService.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => mailService.refresh(),
      child: ListView.builder(
        itemCount: mailService.messages.length,
        itemBuilder: (context, index) {
          final message = mailService.messages[index];
          return Card(
            margin: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            child: ListTile(
              leading: CircleAvatar(
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
              title: Text(
                message.from,
                style: TextStyle(
                  fontWeight: message.isRead 
                    ? FontWeight.normal 
                    : FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.subject,
                    style: TextStyle(
                      fontWeight: message.isRead 
                        ? FontWeight.normal 
                        : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    message.date,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    message.isRead 
                      ? Icons.mail_outline 
                      : Icons.mark_email_unread,
                    size: 20,
                    color: message.isRead 
                      ? Colors.grey 
                      : Colors.blueAccent,
                  ),
                  if (message.attachments.isNotEmpty)
                    const Icon(
                      Icons.attach_file,
                      size: 14,
                      color: Colors.grey,
                    ),
                ],
              ),
              onTap: () async {
                // Load full message
                final fullMessage = await mailService.getMessage(message.id);
                if (fullMessage != null && mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReadMailPage(
                        message: fullMessage,
                        mailService: mailService,
                      ),
                    ),
                  );
                  
                  // Mark as read in list
                  setState(() {
                    message.isRead = true;
                  });
                }
              },
            ),
          );
        },
      ),
    );
  }
}