import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'professional_profile_screen.dart';
import '../widgets/meeting_scheduler_sheet.dart';
import '../utils/avatar_helper.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import 'package:easy_localization/easy_localization.dart';

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
        debugPrint("Error resolving profile: $e");
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
      debugPrint("Error resolving contact details for profile redirection: $e");
    }

    setState(() {
      _canMessage = true;
    });
    if (_recipientId != null) {
      NotificationService().activeChatRecipientId = _recipientId;
    }
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
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    
    try {
      final response = await _supabase
          .from('messages')
          .select()
          .or('and(sender_id.eq.$currentUserId,recipient_id.eq.$_recipientId),and(sender_id.eq.$_recipientId,recipient_id.eq.$currentUserId)')
          .order('created_at', ascending: true);

      // Mark incoming messages as read FIRST (before setState) to avoid race condition
      // where the realtime provider re-fetches before the DB update completes.
      await _markMessagesAsRead(currentUserId);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Error loading messages: $e");
    }
  }

  /// Marks all messages from [_recipientId] to the current user as read in the DB.
  Future<void> _markMessagesAsRead(String currentUserId) async {
    if (_recipientId == null) return;
    try {
      debugPrint('[MARK-READ] Marking messages as read: recipient=$currentUserId, sender=$_recipientId');
      final result = await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('recipient_id', currentUserId)
          .eq('sender_id', _recipientId!)
          .select();
      debugPrint('[MARK-READ] Updated ${result.length} messages');

      // Clear 'is_new' tag in connections if they open the chat
      try {
        await _supabase
            .from('connections')
            .update({'is_new': false})
            .eq('user_id', currentUserId)
            .eq('linked_profile_id', _recipientId!);
      } catch (e) {
        debugPrint("Error clearing is_new from chat: $e");
      }
    } catch (e) {
      debugPrint('[MARK-READ] ERROR: $e');
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('chat_$_recipientId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final String senderId = newRecord['sender_id'] ?? '';
            final String recipientId = newRecord['recipient_id'] ?? '';
            final currentUserId = _supabase.auth.currentUser?.id;
            if (currentUserId == null) return;
            
            // Only process if it belongs to this active conversation
            if ((senderId == currentUserId && recipientId == _recipientId) ||
                (senderId == _recipientId && recipientId == currentUserId)) {
              // If the message is incoming (from the other person), mark as read immediately
              // since the user is actively viewing this chat.
              if (senderId == _recipientId && recipientId == currentUserId) {
                _markMessagesAsRead(currentUserId);
              }
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

    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

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

      // Asynchronously dispatch push notification to recipient
      if (_recipientId != null && _recipientId!.isNotEmpty) {
        _dispatchPushNotification(currentUserId, _recipientId!, text);
      }
    } catch (e) {
      debugPrint("Error sending message: $e");
      // Remove message on failure
      setState(() {
        _messages.remove(localMsg);
      });
      String errorMsg = "Failed to send message.";
      if (e is PostgrestException) {
        errorMsg = "Database Error: ${e.message}";
      } else if (e is AuthException) {
        errorMsg = "Auth Error: ${e.message}";
      } else {
        errorMsg = "Error: ${e.toString()}";
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _dispatchPushNotification(
    String senderId,
    String recipientId,
    String messageContent,
  ) {
    () async {
      try {
        final profile = await _supabase
            .from('profiles')
            .select('full_name, avatar_url')
            .eq('id', senderId)
            .maybeSingle();

        final String senderName = profile?['full_name']?.toString().trim() ?? 'Eventzone Attendee';
        final String senderAvatar = profile?['avatar_url']?.toString().trim() ?? '';

        await SupabaseService().sendPushNotification(
          targetUserId: recipientId,
          title: senderName,
          message: messageContent,
          data: {
            'type': 'message',
            'sender_id': senderId,
            'sender_name': senderName,
            'sender_avatar': senderAvatar,
            'content': messageContent,
          },
        );
      } catch (e) {
        debugPrint("Error dispatching push notification for message: $e");
      }
    }();
  }

  void _showDeleteDialog(String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1F2937),
        title: Text("Delete Message".tr(), style: TextStyle(color: Colors.white)),
        content: Text("Are you sure you want to delete this message?".tr(), style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Cancel".tr(), style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(messageId);
            },
            child: Text("Delete".tr(), style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _supabase.from('messages').delete().eq('id', messageId);
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == messageId);
        });
      }
    } catch (e) {
      debugPrint("Error deleting message: $e");
    }
  }

  void _showDeleteChatDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: GlassContainer(
            borderRadius: 32,
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(height: 32),
                Text(
                  "Delete Chat".tr(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 24,
                      ),
                ),
                SizedBox(height: 16),
                Text(
                  "Are you sure you want to delete this conversation? This cannot be undone.".tr(),
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Cancel".tr(), style: TextStyle(color: Colors.white38, fontSize: 16)),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(context);
                          final currentUserId = _supabase.auth.currentUser?.id;
                          if (currentUserId != null && _recipientId != null) {
                            try {
                              await _supabase.from('messages').delete().or(
                                  'and(sender_id.eq.$currentUserId,recipient_id.eq.$_recipientId),and(sender_id.eq.$_recipientId,recipient_id.eq.$currentUserId)');
                              if (mounted) {
                                setState(() {
                                  _messages.clear();
                                });
                              }
                            } catch (e) {
                              debugPrint("Error deleting chat: $e");
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: Text("Delete".tr(), style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    if (NotificationService().activeChatRecipientId == _recipientId) {
      NotificationService().activeChatRecipientId = null;
    }
    _messageController.dispose();
    _scrollController.dispose();
    if (_channel != null) {
      _supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id ?? "";

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
                backgroundImage: getAvatarProvider(widget.avatarUrl),
                child: getAvatarProvider(widget.avatarUrl) == null
                    ? Icon(LucideIcons.user, size: 14, color: Colors.white)
                    : null,
              ),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.contactName, 
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
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
          icon: Icon(LucideIcons.chevronLeft, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: "Book Meeting".tr(),
            icon: Icon(LucideIcons.calendarPlus, color: Colors.white, size: 20),
            onPressed: () {
              if (_recipientId == null) return;
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => FractionallySizedBox(
                  heightFactor: 0.9,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    child: MeetingSchedulerSheet(
                      otherUserId: _recipientId!,
                      otherName: widget.contactName,
                      otherAvatarUrl: widget.avatarUrl,
                    ),
                  ),
                ),
              );
            },
          ),
          Theme(
            data: Theme.of(context).copyWith(
              cardColor: Color(0xFF1F2937),
            ),
            child: PopupMenuButton<String>(
              icon: Icon(LucideIcons.moreVertical, color: Colors.white),
              offset: Offset(0, 45),
              onSelected: (value) {
                if (value == 'delete') {
                  _showDeleteChatDialog();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(LucideIcons.trash2, color: Colors.redAccent, size: 18),
                      SizedBox(width: 8),
                      Text('Delete Chat'.tr(), style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: EventzoneTheme.buildPlayfulBackground(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: EventzoneTheme.primaryAction))
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            "No messages yet. Send a message to start!".tr(), 
                            style: TextStyle(color: Colors.white24, fontSize: 13)
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.all(24),
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
                                  margin: EdgeInsets.only(bottom: 16),
                                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Text(
                                    message['content'] ?? '',
                                    style: TextStyle(color: Colors.white38, fontSize: 11),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            }

                            return GestureDetector(
                              onLongPress: () {
                                if (message['id'] != null) {
                                  _showDeleteDialog(message['id']);
                                }
                              },
                              child: Align(
                                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 16),
                                  padding: EdgeInsets.all(16),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  decoration: BoxDecoration(
                                    color: isMe 
                                        ? EventzoneTheme.primaryAction 
                                        : Colors.white.withOpacity(0.05),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(16),
                                      topRight: Radius.circular(16),
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
                                        style: TextStyle(color: Colors.white, fontSize: 14)
                                      ),
                                      SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.bottomRight,
                                        child: Text(
                                          timeStr,
                                          style: TextStyle(color: Colors.white30, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            SafeArea(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: EventzoneTheme.backgroundStart,
                child: Row(
                  children: [
                    Expanded(
                      child: GlassContainer(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        borderRadius: 30,
                        child: TextField(
                          controller: _messageController,
                          style: TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "Type your message...".tr(),
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    CircleAvatar(
                      backgroundColor: EventzoneTheme.primaryAction,
                      child: IconButton(
                        icon: Icon(LucideIcons.send, color: Colors.white, size: 18),
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
