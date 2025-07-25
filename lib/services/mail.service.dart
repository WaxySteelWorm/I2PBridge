// lib/services/mail_service.dart
// IMAP/SMTP client for I2P mail

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MailMessage {
  final int id;
  final String from;
  final String to;
  final String subject;
  final String body;
  final DateTime date;
  final bool isRead;
  final bool hasAttachments;

  MailMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.subject,
    required this.body,
    required this.date,
    this.isRead = false,
    this.hasAttachments = false,
  });
}

class MailFolder {
  final String name;
  final String path;
  final int messageCount;
  final int unreadCount;
  final IconData icon;

  MailFolder({
    required this.name,
    required this.path,
    required this.messageCount,
    required this.unreadCount,
    required this.icon,
  });
}

class MailService with ChangeNotifier {
  // Connection settings - using bridge server as proxy
  static const String _imapHost = 'bridge.stormycloud.org';
  static const int _imapPort = 7660; // You'll need to set up IMAP tunnel on this port
  static const String _smtpHost = 'bridge.stormycloud.org';
  static const int _smtpPort = 7659; // You'll need to set up SMTP tunnel on this port
  
  ImapClient? _imapClient;
  SmtpClient? _smtpClient;
  
  bool _isConnected = false;
  bool _isLoading = false;
  String? _username;
  String? _password;
  
  List<MailFolder> _folders = [];
  List<MailMessage> _messages = [];
  MailFolder? _currentFolder;
  
  bool get isConnected => _isConnected;
  bool get isLoading => _isLoading;
  String? get username => _username;
  List<MailFolder> get folders => _folders;
  List<MailMessage> get messages => _messages;
  MailFolder? get currentFolder => _currentFolder;

  // Connect to mail server
  Future<bool> connect(String username, String password) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Store credentials in memory only (no local storage for security)
      _username = username;
      _password = password;
      
      // Initialize IMAP client
      _imapClient = ImapClient(isLogEnabled: false);
      
      try {
        // Connect to IMAP server through bridge
        await _imapClient!.connectToServer(_imapHost, _imapPort, 
          isSecure: false // Since we're going through the bridge
        );
        
        // Authenticate
        await _imapClient!.login(username, password);
        
        _isConnected = true;
        
        // Load folders
        await _loadFolders();
        
        // Select INBOX by default
        await selectFolder('INBOX');
        
        _isLoading = false;
        notifyListeners();
        return true;
        
      } catch (e) {
        print('IMAP connection error: $e');
        _isConnected = false;
        _isLoading = false;
        notifyListeners();
        return false;
      }
      
    } catch (e) {
      print('Mail service error: $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Load mail folders
  Future<void> _loadFolders() async {
    if (_imapClient == null || !_isConnected) return;
    
    try {
      final mailboxes = await _imapClient!.listMailboxes();
      
      _folders = mailboxes.map((mailbox) {
        IconData icon;
        switch (mailbox.name.toLowerCase()) {
          case 'inbox':
            icon = Icons.inbox;
            break;
          case 'sent':
            icon = Icons.send;
            break;
          case 'drafts':
            icon = Icons.drafts;
            break;
          case 'trash':
            icon = Icons.delete;
            break;
          case 'spam':
            icon = Icons.report;
            break;
          default:
            icon = Icons.folder;
        }
        
        return MailFolder(
          name: mailbox.name,
          path: mailbox.path,
          messageCount: mailbox.messagesExists,
          unreadCount: mailbox.messagesUnread,
          icon: icon,
        );
      }).toList();
      
      notifyListeners();
    } catch (e) {
      print('Error loading folders: $e');
    }
  }

  // Select a folder and load messages
  Future<void> selectFolder(String folderName) async {
    if (_imapClient == null || !_isConnected) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      // Select the mailbox
      final mailbox = await _imapClient!.selectMailbox(folderName);
      
      _currentFolder = _folders.firstWhere((f) => f.name == folderName);
      
      // Fetch recent messages (last 50)
      _messages.clear();
      
      if (mailbox.messagesExists > 0) {
        final sequence = MessageSequence.fromRange(
          max(1, mailbox.messagesExists - 49), 
          mailbox.messagesExists
        );
        
        final messages = await _imapClient!.fetchMessages(
          sequence,
          'ENVELOPE BODY.PEEK[]'
        );
        
        // Convert to our format
        _messages = messages.map((msg) {
          final envelope = msg.envelope;
          return MailMessage(
            id: msg.sequenceId!,
            from: envelope?.from?.first.toString() ?? 'Unknown',
            to: envelope?.to?.first.toString() ?? '',
            subject: envelope?.subject ?? '(No Subject)',
            body: _extractBody(msg),
            date: envelope?.date ?? DateTime.now(),
            isRead: !msg.isSeen,
            hasAttachments: msg.hasAttachments,
          );
        }).toList();
        
        // Sort by date, newest first
        _messages.sort((a, b) => b.date.compareTo(a.date));
      }
      
      _isLoading = false;
      notifyListeners();
      
    } catch (e) {
      print('Error selecting folder: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  // Extract plain text body from message
  String _extractBody(MimeMessage message) {
    try {
      return message.decodeTextPlainPart() ?? 
             message.decodeTextHtmlPart() ?? 
             '(No content)';
    } catch (e) {
      return '(Error reading message)';
    }
  }

  // Send an email
  Future<bool> sendMail({
    required String to,
    required String subject,
    required String body,
  }) async {
    if (_username == null || _password == null) return false;
    
    try {
      // Initialize SMTP client if needed
      _smtpClient ??= SmtpClient('I2P Bridge Mail');
      
      if (!_smtpClient!.isConnected) {
        await _smtpClient!.connectToServer(_smtpHost, _smtpPort, 
          isSecure: false
        );
        await _smtpClient!.authenticate(_username!, _password!);
      }
      
      // Build message
      final builder = MessageBuilder()
        ..from = [MailAddress(_username!, _username!)]
        ..to = [MailAddress(to, to)]
        ..subject = subject
        ..text = body;
      
      final message = builder.buildMimeMessage();
      
      // Send
      await _smtpClient!.sendMessage(message);
      
      return true;
      
    } catch (e) {
      print('Error sending mail: $e');
      return false;
    }
  }

  // Mark message as read
  Future<void> markAsRead(int messageId) async {
    if (_imapClient == null || !_isConnected) return;
    
    try {
      await _imapClient!.store(
        MessageSequence.fromId(messageId),
        ['\\Seen'],
        action: StoreAction.add,
      );
      
      // Update local state
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = MailMessage(
          id: _messages[index].id,
          from: _messages[index].from,
          to: _messages[index].to,
          subject: _messages[index].subject,
          body: _messages[index].body,
          date: _messages[index].date,
          isRead: true,
          hasAttachments: _messages[index].hasAttachments,
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  // Delete message
  Future<void> deleteMessage(int messageId) async {
    if (_imapClient == null || !_isConnected) return;
    
    try {
      // Mark as deleted
      await _imapClient!.store(
        MessageSequence.fromId(messageId),
        ['\\Deleted'],
        action: StoreAction.add,
      );
      
      // Expunge to actually delete
      await _imapClient!.expunge();
      
      // Remove from local list
      _messages.removeWhere((m) => m.id == messageId);
      notifyListeners();
      
    } catch (e) {
      print('Error deleting message: $e');
    }
  }

  // Refresh current folder
  Future<void> refresh() async {
    if (_currentFolder != null) {
      await selectFolder(_currentFolder!.name);
    }
  }

  // Disconnect
  void disconnect() async {
    try {
      await _imapClient?.logout();
      await _imapClient?.disconnect();
      await _smtpClient?.disconnect();
    } catch (e) {
      print('Error disconnecting: $e');
    }
    
    _isConnected = false;
    _username = null;
    _password = null;
    _messages.clear();
    _folders.clear();
    _currentFolder = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}