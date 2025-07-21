// lib/pages/irc_page.dart
// Enhanced IRC page with encryption indicators

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/irc_service.dart';

class IrcPage extends StatefulWidget {
  const IrcPage({super.key});

  @override
  State<IrcPage> createState() => _IrcPageState();
}

class _IrcPageState extends State<IrcPage> with AutomaticKeepAliveClientMixin {
  final TextEditingController _channelController = TextEditingController(text: '#i2p');
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ircService = Provider.of<IrcService>(context);
    if (ircService.buffers.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<IrcService>(
      builder: (context, ircService, child) {
        return Scaffold(
          key: _scaffoldKey,
          endDrawer: _buildUserListDrawer(context, ircService),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: ircService.isConnected
                ? _buildChatView(context, ircService)
                : _buildConnectionView(context, ircService),
          ),
        );
      },
    );
  }

  Widget _buildConnectionView(BuildContext context, IrcService ircService) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.lock, size: 80, color: Colors.green),
        const SizedBox(height: 24),
        const Text(
          'Encrypted IRC Chat',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your messages are end-to-end encrypted',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 24),
        Text('Connecting as: ${ircService.nickname}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        TextField(
          controller: _channelController,
          decoration: const InputDecoration(
            labelText: 'Channel',
            border: OutlineInputBorder(),
            hintText: '#channel',
            prefixIcon: Icon(Icons.tag),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => ircService.connect(_channelController.text),
          icon: const Icon(Icons.lock),
          label: const Text('Connect Securely', style: TextStyle(fontSize: 16)),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildChatView(BuildContext context, IrcService ircService) {
    final currentMessages = ircService.currentBufferMessages;
    return Column(
      children: [
        // Channel tabs with encryption indicators
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ircService.buffers.keys.map((bufferName) {
              return GestureDetector(
                onTap: () => ircService.setCurrentBuffer(bufferName),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: ircService.currentBuffer == bufferName ? Colors.blueAccent : Colors.grey.shade800,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      if (bufferName != 'Status')
                        const Icon(Icons.lock, size: 14, color: Colors.green),
                      if (bufferName != 'Status')
                        const SizedBox(width: 4),
                      Text(bufferName),
                      if (ircService.unreadBuffers.contains(bufferName))
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        // Encryption status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock, size: 16, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                ircService.currentBuffer == 'Status' 
                  ? 'Server messages' 
                  : 'End-to-end encrypted',
                style: const TextStyle(fontSize: 12, color: Colors.green),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              controller: _scrollController,
              itemCount: currentMessages.length,
              itemBuilder: (context, index) {
                final msg = currentMessages[index];
                if (msg.isNotice || msg.sender == 'Status') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      '--- ${msg.content} ---',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Encryption indicator
                      Icon(
                        msg.isEncrypted ? Icons.lock : Icons.lock_open,
                        size: 12,
                        color: msg.isEncrypted ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
                            children: <TextSpan>[
                              TextSpan(
                                text: '${DateFormat('HH:mm').format(msg.timestamp)} ',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              TextSpan(
                                text: '${msg.sender}: ',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: ircService.getUserColor(msg.sender),
                                ),
                              ),
                              TextSpan(text: msg.content),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Encrypted message to ${ircService.currentBuffer}...',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock, size: 16, color: Colors.green),
                ),
                onSubmitted: (_) {
                  ircService.handleUserInput(_messageController.text);
                  _messageController.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.people_outline),
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                ircService.handleUserInput(_messageController.text);
                _messageController.clear();
              },
              style: IconButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        // Help text
        const SizedBox(height: 8),
        Text(
          'Use /key <password> to set a custom channel encryption key',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        TextButton(
          onPressed: () => ircService.disconnect(),
          child: const Text('Disconnect'),
        )
      ],
    );
  }

  Widget _buildUserListDrawer(BuildContext context, IrcService ircService) {
    final userList = ircService.currentUserList;
    userList.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: Text('Users in ${ircService.currentBuffer}'),
            automaticallyImplyLeading: false,
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.green.withOpacity(0.1),
            child: Row(
              children: const [
                Icon(Icons.lock, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Private messages are encrypted',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: userList.length,
              itemBuilder: (context, index) {
                final user = userList[index];
                return ListTile(
                  leading: const Icon(Icons.person, size: 20),
                  title: Text(user),
                  subtitle: const Text('Tap to start encrypted chat', style: TextStyle(fontSize: 12)),
                  onTap: () {
                    ircService.handleUserInput('/query $user');
                    Navigator.of(context).pop();
                  },
                  onLongPress: () {
                    _showModeratorActions(context, ircService, user);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showModeratorActions(BuildContext context, IrcService ircService, String user) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.record_voice_over),
              title: const Text('Voice'),
              onTap: () {
                ircService.handleUserInput('/mode ${ircService.currentBuffer} +v $user');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.security),
              title: const Text('Op'),
              onTap: () {
                ircService.handleUserInput('/mode ${ircService.currentBuffer} +o $user');
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app),
              title: const Text('Kick'),
              onTap: () {
                Navigator.pop(context);
                _showKickBanDialog(context, ircService, user, 'KICK');
              },
            ),
             ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Ban'),
              onTap: () {
                 Navigator.pop(context);
                _showKickBanDialog(context, ircService, user, 'BAN');
              },
            ),
          ],
        );
      },
    );
  }

  void _showKickBanDialog(BuildContext context, IrcService ircService, String user, String action) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('$action $user'),
          content: TextField(
            controller: reasonController,
            decoration: const InputDecoration(hintText: 'Reason (optional)'),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text(action),
              onPressed: () {
                final reason = reasonController.text.isNotEmpty ? reasonController.text : 'No reason specified';
                if (action == 'KICK') {
                  ircService.handleUserInput('/kick ${ircService.currentBuffer} $user $reason');
                } else if (action == 'BAN') {
                  ircService.handleUserInput('/mode ${ircService.currentBuffer} +b $user!*@*');
                }
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}