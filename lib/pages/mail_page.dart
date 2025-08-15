// lib/pages/mail_page.dart
// Production I2P Mail client with end-to-end encryption

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../services/pop3_mail_service.dart';
import '../services/auth_service.dart';
import 'compose_mail_page.dart';
import 'create_account_page.dart';
import 'read_mail_page.dart' deferred as read_mail;

class MailPage extends StatefulWidget {
  const MailPage({super.key});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  late Pop3MailService _mailService;
  bool _obscurePassword = true;
  
  @override
  void initState() {
    super.initState();
    _mailService = Pop3MailService();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inject AuthService into mail service when available
    final authService = Provider.of<AuthService>(context, listen: false);
    _mailService.setAuthService(authService);
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.mail_lock, size: 80, color: Colors.blueAccent),
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
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.security, color: Colors.green, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'End-to-End Encrypted Mail',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🔒 ', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Text(
                        'Your credentials are encrypted before leaving your device',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🔒 ', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Text(
                        'All emails are encrypted end-to-end',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('🔒 ', style: TextStyle(fontSize: 13)),
                    Expanded(
                      child: Text(
                        'Server cannot read your messages or credentials',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
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
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            obscureText: _obscurePassword,
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
              : const Icon(Icons.lock),
            label: Text(mailService.isLoading ? 'Connecting...' : 'Secure Login'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
            ),
          ),
          
          _buildStatusMessage(mailService),
          
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const CreateAccountPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Create I2P Account'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: Colors.blue.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.blue.withOpacity(0.3)),
                    ),
                  ),
                ),
              ),
            ],
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
              const Icon(Icons.mail_lock, color: Colors.green),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Encrypted Inbox',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.security, size: 12, color: Colors.green),
                            SizedBox(width: 4),
                            Text(
                              'E2E',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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
            icon: const Icon(Icons.lock),
            label: const Text('Compose Encrypted'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              backgroundColor: Colors.green,
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
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: 8,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Shimmer.fromColors(
              baseColor: Colors.white10,
              highlightColor: Colors.white24,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 12, width: double.infinity, color: Colors.white),
                          const SizedBox(height: 8),
                          Container(height: 12, width: 180, color: Colors.white),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    
    if (mailService.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mail_lock,
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
              leading: Stack(
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
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                  ),
                ],
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
                final fullMessage = await mailService.getMessage(message.id);
                if (fullMessage != null && mounted) {
                  await read_mail.loadLibrary();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => read_mail.ReadMailPage(
                        message: fullMessage,
                        mailService: mailService,
                      ),
                    ),
                  );
                  
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