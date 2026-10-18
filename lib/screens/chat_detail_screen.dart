import 'dart:convert';
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
import '../models/meeting_model.dart';
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
  final SupabaseService _supabaseService = SupabaseService();
  
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String? _recipientId;
  bool _canMessage = false;
  RealtimeChannel? _channel;
  RealtimeChannel? _meetingsChannel;
  MeetingModel? _pinnedMeeting;
  bool _isActingOnMeeting = false;
  final Map<String, String> _meetingStatuses = {};
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
    await _loadPendingMeeting();
    await _loadMessages();
    _subscribeRealtime();
    _subscribeMeetingsRealtime();
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

      // Collect meeting IDs present in messages and fetch their live status
      final meetingIds = <String>{};
      for (final msg in response) {
        final content = msg['content']?.toString() ?? '';
        if (content.startsWith('{') && content.endsWith('}')) {
          try {
            final parsed = jsonDecode(content);
            if (parsed is Map && parsed['meeting_id'] != null) {
              meetingIds.add(parsed['meeting_id'].toString());
            }
          } catch (_) {}
        }
      }

      if (meetingIds.isNotEmpty) {
        try {
          final meetingsRes = await _supabase
              .from('meetings')
              .select('id, status')
              .inFilter('id', meetingIds.toList());
          for (final m in meetingsRes) {
            final id = m['id']?.toString();
            final status = m['status']?.toString();
            if (id != null && status != null) {
              _meetingStatuses[id] = status;
            }
          }
        } catch (e) {
          debugPrint("Error fetching meeting statuses: $e");
        }
      }

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

  Future<void> _loadPendingMeeting() async {
    if (_recipientId == null) return;
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final res = await _supabase
          .from('meetings')
          .select('*, organizer_profile:profiles!organizer_id(*), attendee_profile:profiles!attendee_id(*)')
          .or('and(organizer_id.eq.$currentUserId,attendee_id.eq.$_recipientId),and(organizer_id.eq.$_recipientId,attendee_id.eq.$currentUserId)')
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1);

      if (mounted) {
        setState(() {
          if ((res as List).isNotEmpty) {
            _pinnedMeeting = MeetingModel.fromJson(res.first, currentUserId);
            _meetingStatuses[_pinnedMeeting!.id] = _pinnedMeeting!.status;
          } else {
            _pinnedMeeting = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading pending meeting for chat: $e");
    }
  }

  void _subscribeMeetingsRealtime() {
    if (_recipientId == null) return;
    _meetingsChannel = _supabase
        .channel('chat_meetings_${_recipientId}_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'meetings',
          callback: (payload) {
            final newRecord = payload.newRecord;
            final oldRecord = payload.oldRecord;
            final mId = (newRecord['id'] ?? oldRecord['id'])?.toString();
            final mStatus = newRecord['status']?.toString();
            if (mId != null && mStatus != null) {
              if (mounted) {
                setState(() {
                  _meetingStatuses[mId] = mStatus;
                });
              }
            }
            _loadPendingMeeting();
            _loadMessages();
          },
        )
        .subscribe();
  }

  Future<void> _handleMeetingAction(String meetingId, String newStatus) async {
    if (_isActingOnMeeting) return;
    setState(() => _isActingOnMeeting = true);

    try {
      final success = await _supabaseService.updateMeetingStatus(meetingId, newStatus);
      if (success) {
        if (mounted) {
          setState(() {
            _meetingStatuses[meetingId] = newStatus;
            if (_pinnedMeeting?.id == meetingId) {
              _pinnedMeeting = null;
            }
          });
          final message = newStatus == 'accepted'
              ? "Meeting accepted! Added to your schedule.".tr()
              : (newStatus == 'declined'
                  ? "Meeting request declined.".tr()
                  : "Meeting request cancelled.".tr());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: newStatus == 'accepted' ? EventzoneTheme.accentSuccess : Colors.white24,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadPendingMeeting();
        await _loadMessages();
      }
    } catch (e) {
      debugPrint("Error handling meeting action: $e");
    } finally {
      if (mounted) {
        setState(() => _isActingOnMeeting = false);
      }
    }
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
    if (_meetingsChannel != null) {
      _supabase.removeChannel(_meetingsChannel!);
    }
    super.dispose();
  }

  String _cleanMessageContent(String rawContent) {
    if (rawContent.startsWith('{') && rawContent.endsWith('}')) {
      try {
        final map = jsonDecode(rawContent);
        if (map is Map) {
          if (map['content'] != null) {
            return map['content'].toString();
          }
          if (map['message'] != null) {
            return map['message'].toString();
          }
        }
      } catch (_) {}
    }
    return rawContent;
  }

  Widget _buildPinnedMeetingBanner(MeetingModel meeting) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isRecipient = meeting.attendeeId == currentUserId;
    final otherName = widget.contactName;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Tag Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.pin, color: Color(0xFFF59E0B), size: 12),
                    const SizedBox(width: 4),
                    Text(
                      "PINNED MEETING REQUEST".tr(),
                      style: const TextStyle(
                        color: Color(0xFFF59E0B),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "${meeting.date} • ${meeting.startTime} - ${meeting.endTime}",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Title & Note
          Text(
            meeting.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (meeting.location != null && meeting.location!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(LucideIcons.mapPin, size: 12, color: Colors.white54),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    meeting.location!.trim(),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (meeting.note != null && meeting.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              "\"${meeting.note!.trim()}\"",
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11.5,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 12),

          // Action Buttons
          if (isRecipient) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isActingOnMeeting
                        ? null
                        : () => _handleMeetingAction(meeting.id, 'accepted'),
                    icon: _isActingOnMeeting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.check, size: 15),
                    label: Text("Accept".tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isActingOnMeeting
                        ? null
                        : () => _handleMeetingAction(meeting.id, 'declined'),
                    icon: const Icon(LucideIcons.x, size: 15),
                    label: Text("Decline".tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                const Icon(LucideIcons.clock, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Waiting for $otherName to accept or decline...".tr(),
                    style: const TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _isActingOnMeeting
                      ? null
                      : () => _handleMeetingAction(meeting.id, 'cancelled'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    "Cancel".tr(),
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMeetingMessageCard(
    Map<String, dynamic> message,
    Map<String, dynamic> payload,
    bool isMe,
  ) {
    final meetingId = payload['meeting_id']?.toString() ?? '';
    final title = payload['title']?.toString() ?? 'Meeting';
    final date = payload['date']?.toString() ?? '';
    final startTime = payload['start_time']?.toString() ?? '';
    final endTime = payload['end_time']?.toString() ?? '';
    final location = payload['location']?.toString();
    final note = payload['note']?.toString();

    final currentStatus = _meetingStatuses[meetingId] ?? payload['status']?.toString() ?? 'pending';
    final isRecipient = !isMe;

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (currentStatus == 'accepted') {
      statusColor = const Color(0xFF10B981);
      statusLabel = "Meeting Confirmed".tr();
      statusIcon = LucideIcons.calendarCheck;
    } else if (currentStatus == 'declined') {
      statusColor = Colors.redAccent;
      statusLabel = "Meeting Declined".tr();
      statusIcon = LucideIcons.calendarX;
    } else if (currentStatus == 'cancelled') {
      statusColor = Colors.white38;
      statusLabel = "Meeting Cancelled".tr();
      statusIcon = LucideIcons.calendarX;
    } else {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = "Meeting Request".tr();
      statusIcon = LucideIcons.calendarClock;
    }

    String timeStr = "Just now";
    if (message['created_at'] != null) {
      try {
        final dt = DateTime.parse(message['created_at']).toLocal();
        final hour = dt.hour.toString().padLeft(2, '0');
        final min = dt.minute.toString().padLeft(2, '0');
        timeStr = "$hour:$min";
      } catch (_) {}
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: const Color(0xFF141B2D),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(statusIcon, size: 16, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (date.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      date,
                      style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(LucideIcons.clock, size: 13, color: Color(0xFF38BDF8)),
                const SizedBox(width: 5),
                Text(
                  "$startTime - $endTime",
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (location != null && location.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(LucideIcons.mapPin, size: 13, color: Colors.white54),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      location.trim(),
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (note != null && note.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "\"${note.trim()}\"",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],

            if (currentStatus == 'pending' && isRecipient && meetingId.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isActingOnMeeting
                          ? null
                          : () => _handleMeetingAction(meetingId, 'accepted'),
                      icon: const Icon(LucideIcons.check, size: 14),
                      label: Text("Accept".tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isActingOnMeeting
                          ? null
                          : () => _handleMeetingAction(meetingId, 'declined'),
                      icon: const Icon(LucideIcons.x, size: 14),
                      label: Text("Decline".tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                timeStr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusUpdatePill(Map<String, dynamic> payload) {
    final status = payload['status']?.toString() ?? '';
    final title = payload['title']?.toString() ?? 'Meeting';
    final isAccepted = status == 'accepted';

    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: (isAccepted ? const Color(0xFF10B981) : Colors.redAccent).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isAccepted ? const Color(0xFF10B981) : Colors.redAccent).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAccepted ? LucideIcons.calendarCheck : LucideIcons.calendarX,
              size: 14,
              color: isAccepted ? const Color(0xFF10B981) : Colors.redAccent,
            ),
            const SizedBox(width: 6),
            Text(
              isAccepted ? "Meeting accepted: \"$title\"".tr() : "Meeting declined: \"$title\"".tr(),
              style: TextStyle(
                color: isAccepted ? const Color(0xFF10B981) : Colors.redAccent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
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
        actions: [
          IconButton(
            tooltip: "Book Meeting".tr(),
            icon: const Icon(LucideIcons.calendarPlus, color: Colors.white, size: 20),
            onPressed: () async {
              if (_recipientId == null) return;
              final booked = await showModalBottomSheet<bool>(
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
              if (booked == true) {
                await _loadPendingMeeting();
                await _loadMessages();
              }
            },
          ),
          Theme(
            data: Theme.of(context).copyWith(
              cardColor: const Color(0xFF1F2937),
            ),
            child: PopupMenuButton<String>(
              icon: const Icon(LucideIcons.moreVertical, color: Colors.white),
              offset: const Offset(0, 45),
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
                      const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 18),
                      const SizedBox(width: 8),
                      Text('Delete Chat'.tr(), style: const TextStyle(color: Colors.redAccent)),
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
            if (_pinnedMeeting != null)
              _buildPinnedMeetingBanner(_pinnedMeeting!),
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: EventzoneTheme.primaryAction))
                  : _messages.isEmpty
                      ? Center(
                          child: Text(
                            "No messages yet. Send a message to start!".tr(), 
                            style: const TextStyle(color: Colors.white24, fontSize: 13)
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
                            final rawContent = message['content']?.toString() ?? '';

                            // Parse JSON content if present
                            Map<String, dynamic>? parsedJson;
                            if (rawContent.startsWith('{') && rawContent.endsWith('}')) {
                              try {
                                final decoded = jsonDecode(rawContent);
                                if (decoded is Map<String, dynamic>) {
                                  parsedJson = decoded;
                                }
                              } catch (_) {}
                            }

                            if (parsedJson != null && parsedJson['type'] == 'meeting_request') {
                              return _buildMeetingMessageCard(message, parsedJson, isMe);
                            }

                            if (parsedJson != null && parsedJson['type'] == 'meeting_status_update') {
                              return _buildStatusUpdatePill(parsedJson);
                            }

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
                                    color: Colors.white.withValues(alpha: 0.03),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: Text(
                                    _cleanMessageContent(rawContent),
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
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
                                  margin: const EdgeInsets.only(bottom: 16),
                                  padding: const EdgeInsets.all(16),
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                  decoration: BoxDecoration(
                                    color: isMe 
                                        ? EventzoneTheme.primaryAction 
                                        : Colors.white.withValues(alpha: 0.05),
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
                                        _cleanMessageContent(rawContent), 
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
                          decoration: InputDecoration(
                            hintText: "Type your message...".tr(),
                            hintStyle: const TextStyle(color: Colors.white38),
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
