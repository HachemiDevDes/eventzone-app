import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'professional_profile_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String contactName;
  final String avatarUrl;
  final String? recipientId;
  final String? recipientEmail;

  const ChatDetailScreen({
    super.key,
    required this.contactName,
    required this.avatarUrl,
    this.recipientId,
    this.recipientEmail,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String? _recipientId;
  bool _canMessage = false;
  RealtimeChannel? _channel;
  Map<String, dynamic>? _resolvedContactDetails;

  @override
  void initState() {
    super.initState();
    _recipientId = widget.recipientId;
    _initChat();
  }

  Future<void> _initChat() async {
    // 1. Resolve recipient profile ID if not supplied directly
    if (_recipientId == null) {
      try {
        final emailQuery = widget.recipientEmail ?? '';
        final nameQuery = widget.contactName;

        // First attempt: resolve by email
        if (emailQuery.isNotEmpty) {
          final res = await _supabase
              .from('profiles')
              .select('id')
              .eq('email', emailQuery)
              .maybeSingle();
          if (res != null) {
            _recipientId = res['id'];
          }
        }

        // Second attempt: resolve by full name
        if (_recipientId == null) {
          final res = await _supabase
              .from('profiles')
              .select('id')
              .eq('full_name', nameQuery)
              .maybeSingle();
          if (res != null) {
            _recipientId = res['id'];
          }
        }
      } catch (e) {
        print("Error resolving profile: $e");
      }
    }

    // 2. Fallback: Create a deterministic UUID based on their email or name
    if (_recipientId == null) {
      final uniqueString = widget.recipientEmail?.isNotEmpty == true
          ? widget.recipientEmail!
          : widget.contactName;
      final hash = uniqueString.hashCode.abs().toString().padLeft(12, '0');
      _recipientId = "00000000-0000-0000-0000-$hash";
    }

    // 3. Resolve the full contact details for profile redirection
    try {
      final connRes = await _supabase
          .from('connections')
          .select()
          .eq('id', _recipientId!)
          .maybeSingle();
      if (connRes != null) {
        _resolvedContactDetails = connRes;
      } else {
        final profRes = await _supabase
            .from('profiles')
            .select()
            .eq('id', _recipientId!)
            .maybeSingle();
        if (profRes != null) {
          _resolvedContactDetails = {
            'name': profRes['full_name'],
            'title': profRes['job_title'],
            'avatar_url': profRes['avatar_url'],
            'email': profRes['email'],
            'company': profRes['company_name'],
            'address': profRes['address'],
          };
        }
      }
    } catch (e) {
      print("Error resolving contact details for profile redirection: $e");
    }

    setState(() {
      _canMessage = true;
    });
    await _loadMessages();
    _subscribeRealtime();
  }

  void _navigateToProfile() {
    final details = _resolvedContactDetails;
    if (details == null) {
      // Fallback redirection using widget parameters if DB query yielded nothing
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProfessionalProfileScreen(
            name: widget.contactName,
            title: 'Attendee',
            avatarUrl: widget.avatarUrl,
            email: widget.recipientEmail,
            connectionId: _recipientId,
          ),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfessionalProfileScreen(
          name: details['name'] ?? details['full_name'] ?? widget.contactName,
          title: details['title'] ?? details['job_title'] ?? 'Attendee',
          avatarUrl: details['avatar_url'] ?? widget.avatarUrl,
          email: details['email'] ?? widget.recipientEmail,
          phone: details['phone'],
          website: details['website'],
          company: details['company'] ?? details['company_name'],
          department: details['department'],
          notes: details['notes'],
          tags: details['tags'] != null ? List<String>.from(details['tags']) : null,
          address: details['address'],
          connectionId: _recipientId,
        ),
      ),
    );
  }

  Future<void> _loadMessages() async {
    if (_recipientId == null) return;
    final currentUserId = _supabase.auth.currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
    
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$currentUserId,recipient_id.eq.$_recipientId),and(sender_id.eq.$_recipientId,recipient_id.eq.$currentUserId)')
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
        _scrollToBottom();

        // Mark incoming messages as read
        await _supabase
            .from('messages')
            .update({'is_read': true})
            .eq('recipient_id', currentUserId)
            .eq('sender_id', _recipientId!)
            .eq('is_read', false);
      }
    } catch (e) {
      print("Error loading messages: $e");
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('chat_${_recipientId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final String senderId = newRecord['sender_id'] ?? '';
            final String recipientId = newRecord['recipient_id'] ?? '';
            final currentUserId = _supabase.auth.currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
            
            // Only add if it belongs to this active conversation
            if ((senderId == currentUserId && recipientId == _recipientId) ||
                (senderId == _recipientId && recipientId == currentUserId)) {
              _loadMessages();
            }
          },
        );
    _channel!.subscribe();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _messageController.clear();

    final currentUserId = _supabase.auth.currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";

    // Add locally immediately for instant UI feedback
    final Map<String, dynamic> localMsg = {
      'content': text,
      'sender_id': currentUserId,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };

    setState(() {
      _messages.add(localMsg);
    });
    _scrollToBottom();

    try {
      await _supabase.from('messages').insert({
        'sender_id': currentUserId,
        'recipient_id': _recipientId,
        'content': text,
      });
    } catch (e) {
      print("Error sending message: $e");
      // Remove message on failure
      setState(() {
        _messages.remove(localMsg);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to send message."), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";

    return Scaffold(
      appBar: AppBar(
        backgroundColor: EventzoneTheme.backgroundStart,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: GestureDetector(
          onTap: _navigateToProfile,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.avatarUrl.isNotEmpty && widget.avatarUrl.startsWith('http')
                    ? NetworkImage(widget.avatarUrl)
                    : (widget.avatarUrl.isNotEmpty ? FileImage(File(widget.avatarUrl)) : null) as ImageProvider?,
                child: widget.avatarUrl.isEmpty
                    ? const Icon(LucideIcons.user, size: 14, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName, 
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
                  ),
                  Text(
                    _canMessage ? "Online" : "Offline Contact", 
                    style: TextStyle(
                      fontSize: 11, 
                      color: _canMessage ? EventzoneTheme.accentSuccess : Colors.white30
                    )
                  ),
                ],
              ),
            ],
          ),
        ),
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: EventzoneTheme.buildPlayfulBackground(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: EventzoneTheme.primaryAction))
                  : _messages.isEmpty
                      ? const Center(
                          child: Text(
                            "No messages yet. Send a message to start!", 
                            style: TextStyle(color: Colors.white24, fontSize: 13)
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(24),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final String senderId = message['sender_id'] ?? '';
                            final bool isMe = senderId == currentUserId || senderId == 'me';
                            final bool isSystem = senderId == 'system';
                            
                            String timeStr = "Just now";
                            if (message['created_at'] != null) {
                              try {
                                final dt = DateTime.parse(message['created_at']).toLocal();
                                final hour = dt.hour.toString().padLeft(2, '0');
                                final min = dt.minute.toString().padLeft(2, '0');
                                timeStr = "$hour:$min";
                              } catch (_) {}
                            }

                            if (isSystem) {
                              return Align(
                                alignment: Alignment.center,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Text(
                                    message['content'] ?? '',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            return Align(
                              alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                padding: const EdgeInsets.all(16),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                decoration: BoxDecoration(
                                  color: isMe 
                                      ? EventzoneTheme.primaryAction 
                                      : Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(16),
                                    topRight: const Radius.circular(16),
                                    bottomLeft: Radius.circular(isMe ? 16 : 0),
                                    bottomRight: Radius.circular(isMe ? 0 : 16),
                                  ),
                                  border: Border.all(
                                    color: isMe ? Colors.transparent : Colors.white12,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message['content'] ?? '', 
                                      style: const TextStyle(color: Colors.white, fontSize: 14)
                                    ),
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: Text(
                                        timeStr,
                                        style: const TextStyle(color: Colors.white30, fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: EventzoneTheme.backgroundStart,
                child: Row(
                  children: [
                    Expanded(
                      child: GlassContainer(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        borderRadius: 30,
                        child: TextField(
                          controller: _messageController,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            hintText: "Type your message...",
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    CircleAvatar(
                      backgroundColor: EventzoneTheme.primaryAction,
                      child: IconButton(
                        icon: const Icon(LucideIcons.send, color: Colors.white, size: 18),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
