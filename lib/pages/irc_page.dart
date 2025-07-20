// lib/pages/irc_page.dart
// This is a major UI overhaul, adding a user list drawer, timestamps,
// color-coded nicks, and moderator actions.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart'; // For formatting timestamps
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
          // --- NEW: User List Drawer ---
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
        const Icon(Icons.connect_without_contact, size: 80, color: Colors.grey),
        const SizedBox(height: 24),
        Text('Connecting as: ${ircService.nickname}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        TextField(
          controller: _channelController,
          decoration: const InputDecoration(
            labelText: 'Channel',
            border: OutlineInputBorder(),
            hintText: '#channel',
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => ircService.connect(_channelController.text),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Connect', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildChatView(BuildContext context, IrcService ircService) {
    final currentMessages = ircService.currentBufferMessages;
    return Column(
      children: [
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
                  child: RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
                      children: <TextSpan>[
                        // --- NEW: Timestamp ---
                        TextSpan(
                          text: '${DateFormat('HH:mm').format(msg.timestamp)} ',
                          style: const TextStyle(color: Colors.grey),
                        ),
                        // --- NEW: Color-Coded Nickname ---
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
                  hintText: 'Message ${ircService.currentBuffer}...',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  ircService.handleUserInput(_messageController.text);
                  _messageController.clear();
                },
              ),
            ),
            const SizedBox(width: 8),
            // --- NEW: User List Button ---
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
        TextButton(
          onPressed: () => ircService.disconnect(),
          child: const Text('Disconnect'),
        )
      ],
    );
  }

  // --- NEW: User List Drawer Widget ---
  Widget _buildUserListDrawer(BuildContext context, IrcService ircService) {
    final userList = ircService.currentUserList;
    userList.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())); // Sort alphabetically

    return Drawer(
      child: Column(
        children: [
          AppBar(
            title: Text('Users in ${ircService.currentBuffer}'),
            automaticallyImplyLeading: false,
          ),
          Expanded(
            child: ListView.builder(
              itemCount: userList.length,
              itemBuilder: (context, index) {
                final user = userList[index];
                return ListTile(
                  title: Text(user),
                  onTap: () {
                    // Start a private message
                    ircService.handleUserInput('/query $user');
                    Navigator.of(context).pop(); // Close the drawer
                  },
                  // --- NEW: Moderator Actions ---
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

  // --- NEW: Moderator Actions Menu ---
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
                Navigator.pop(context); // Close the menu first
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

  // --- NEW: Dialog for Kick/Ban reason ---
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
                  // A simple ban, more complex masks could be added later
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
