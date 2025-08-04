// lib/pages/irc_page.dart
// IRC page with privacy-focused design

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
  final TextEditingController _channelController = TextEditingController(text: 'i2p');
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
        const Icon(Icons.chat_bubble_outline, size: 80, color: Colors.blueAccent),
        const SizedBox(height: 24),
        // Privacy information box
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Column(
            children: const [
              Icon(Icons.lock, color: Colors.green, size: 32),
              SizedBox(height: 8),
              Text(
                'Privacy Protected IRC',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              SizedBox(height: 8),
              Text(
                '• Messages encrypted in transit',
                style: TextStyle(fontSize: 14),
              ),
              Text(
                '• No chat data is logged',
                style: TextStyle(fontSize: 14),
              ),
              Text(
                '• Your IP is hidden from IRC servers',
                style: TextStyle(fontSize: 14),
              ),
              Text(
                '• Anonymous connection statistics only',
                style: TextStyle(fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Nickname: ${ircService.nickname}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        TextField(
          controller: _channelController,
          decoration: const InputDecoration(
            labelText: 'Channel',
            border: OutlineInputBorder(),
            hintText: 'i2p',
            prefixText: '#',
            prefixStyle: TextStyle(color: Colors.grey, fontSize: 16),
          ),
          onChanged: (value) {
            // Remove any # that user types since we show it as prefix
            if (value.startsWith('#')) {
              _channelController.text = value.substring(1);
              _channelController.selection = TextSelection.fromPosition(
                TextPosition(offset: _channelController.text.length),
              );
            }
          },
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () {
            String channel = _channelController.text.trim();
            // Ensure channel starts with #
            if (channel.isNotEmpty && !channel.startsWith('#')) {
              channel = '#$channel';
            }
            if (channel.isEmpty) {
              channel = '#i2p'; // Default channel
            }
            ircService.connect(channel);
          },
          icon: const Icon(Icons.connect_without_contact),
          label: const Text('Connect', style: TextStyle(fontSize: 16)),
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
        // Channel tabs
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
                if (msg.isNotice || msg.sender == 'Status' || msg.sender == 'Server') {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      msg.sender == 'Server' ? msg.content : '--- ${msg.content} ---',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                        fontSize: msg.sender == 'Server' ? 12 : 14,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: RichText(
                    text: TextSpan(
                      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 15),
                      children: <TextSpan>[
                        TextSpan(
                          text: '${DateFormat('HH:mm').format(msg.timestamp)} ',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        if (msg.sender.startsWith('* '))
                          TextSpan(
                            text: msg.sender + ' ' + msg.content,
                            style: TextStyle(
                              color: ircService.getUserColor(msg.sender.substring(2)),
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        else ...[
                          TextSpan(
                            text: '<${msg.sender}> ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: ircService.getUserColor(msg.sender),
                            ),
                          ),
                          TextSpan(text: msg.content),
                        ],
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

  Widget _buildUserListDrawer(BuildContext context, IrcService ircService) {
    final userList = ircService.currentUserList;

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
                final cleanNick = user.replaceAll(RegExp(r'[@+~&%]'), '');
                final isOp = user.startsWith('@');
                final isVoice = user.startsWith('+');
                
                return ListTile(
                  leading: Icon(
                    isOp ? Icons.star : (isVoice ? Icons.mic : Icons.person),
                    size: 20,
                    color: isOp ? Colors.orange : (isVoice ? Colors.green : null),
                  ),
                  title: Text(user),
                  subtitle: Text(
                    isOp ? 'Operator' : (isVoice ? 'Voice' : 'User'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () {
                    ircService.handleUserInput('/query $cleanNick');
                    Navigator.of(context).pop();
                  },
                  onLongPress: () {
                    if (isOp || isVoice) return; // Don't show mod actions for ops/voice
                    _showModeratorActions(context, ircService, cleanNick);
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