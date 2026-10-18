import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/eventzone_theme.dart';
import '../utils/avatar_helper.dart';
import '../widgets/glass_container.dart';
import 'direct_messages_screen.dart';
import 'professional_profile_screen.dart';
import 'chat_detail_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/export_contacts_sheet.dart';
import '../services/supabase_service.dart';
import '../models/connection_request_model.dart';
import '../models/meeting_model.dart';
import '../providers/connection_providers.dart';

enum NetworkTab { contacts, requests, meetings }
enum RequestsSubTab { received, sent }
enum MeetingsSubTab { upcoming, requests }
enum MeetingRequestsSubFilter { received, sent }

class MyNetworkScreen extends ConsumerStatefulWidget {
  const MyNetworkScreen({super.key});

  @override
  ConsumerState<MyNetworkScreen> createState() => _MyNetworkScreenState();
}

class _MyNetworkScreenState extends ConsumerState<MyNetworkScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  String _searchQuery = "";
  String? _selectedTag;
  List<Map<String, dynamic>> _supabaseConnections = [];
  List<ConnectionRequestModel> _incomingRequests = [];
  List<ConnectionRequestModel> _sentRequests = [];
  List<MeetingModel> _upcomingMeetings = [];
  List<MeetingModel> _receivedMeetingRequests = [];
  List<MeetingModel> _sentMeetingRequests = [];
  bool _isLoading = true;
  bool _isLoadingRequests = false;
  bool _isLoadingMeetings = false;
  RealtimeChannel? _connectionsChannel;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _meetingsChannel;
  int _unreadCount = 0;

  NetworkTab _currentTab = NetworkTab.contacts;
  RequestsSubTab _requestsSubTab = RequestsSubTab.received;
  MeetingsSubTab _meetingsSubTab = MeetingsSubTab.upcoming;
  MeetingRequestsSubFilter _meetingRequestsFilter = MeetingRequestsSubFilter.received;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _subscribeToConnections();
    _subscribeToMessages();
    _subscribeToMeetings();
  }

  void _subscribeToMessages() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    _fetchUnreadCount(currentUserId);

    _messagesChannel = Supabase.instance.client
        .channel('public:messages:unread')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) {
            _fetchUnreadCount(currentUserId);
          },
        )
        .subscribe();
  }

  void _fetchUnreadCount(String currentUserId) async {
    try {
      final data = await Supabase.instance.client
          .from('messages')
          .select('id')
          .eq('recipient_id', currentUserId)
          .or('is_read.eq.false,is_read.is.null');
      if (mounted) {
        setState(() {
          _unreadCount = data.length;
        });
      }
    } catch (e) {
      debugPrint("Error fetching unread count: $e");
    }
  }

  @override
  void dispose() {
    _connectionsChannel?.unsubscribe();
    _messagesChannel?.unsubscribe();
    _meetingsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToConnections() {
    _connectionsChannel = Supabase.instance.client
        .channel('network_connections_updates_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'connections',
          callback: (_) {
            if (mounted) {
              _loadAllData();
            }
          },
        )
        .subscribe();
  }

  void _subscribeToMeetings() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    _meetingsChannel = Supabase.instance.client
        .channel('network_meetings_updates_${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'meetings',
          callback: (_) {
            if (mounted) {
              _loadMeetings();
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadAllData() async {
    await Future.wait([
      _loadConnections(),
      _loadRequests(),
      _loadMeetings(),
    ]);
  }

  Future<void> _loadMeetings() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        if (mounted) setState(() => _isLoadingMeetings = false);
        return;
      }

      final allMeetings = await _supabaseService.fetchMeetings(currentUserId);
      final upcoming = <MeetingModel>[];
      final receivedReqs = <MeetingModel>[];
      final sentReqs = <MeetingModel>[];

      for (final m in allMeetings) {
        if (m.status == 'accepted') {
          upcoming.add(m);
        } else if (m.status == 'pending') {
          if (m.attendeeId == currentUserId) {
            receivedReqs.add(m);
          } else if (m.organizerId == currentUserId) {
            sentReqs.add(m);
          }
        }
      }

      if (mounted) {
        setState(() {
          _upcomingMeetings = upcoming;
          _receivedMeetingRequests = receivedReqs;
          _sentMeetingRequests = sentReqs;
          _isLoadingMeetings = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading meetings in MyNetwork: $e");
      if (mounted) setState(() => _isLoadingMeetings = false);
    }
  }

  Future<void> _acceptMeeting(MeetingModel meeting) async {
    try {
      final success = await _supabaseService.updateMeetingStatus(meeting.id, 'accepted');
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Meeting accepted! Added to upcoming meetings.".tr()),
              backgroundColor: EventzoneTheme.accentSuccess,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadMeetings();
      }
    } catch (e) {
      debugPrint("Error accepting meeting: $e");
    }
  }

  Future<void> _declineMeeting(MeetingModel meeting) async {
    try {
      final success = await _supabaseService.updateMeetingStatus(meeting.id, 'declined');
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Meeting request declined.".tr()),
              backgroundColor: Colors.white24,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadMeetings();
      }
    } catch (e) {
      debugPrint("Error declining meeting: $e");
    }
  }

  Future<void> _cancelMeeting(MeetingModel meeting) async {
    try {
      final success = await _supabaseService.updateMeetingStatus(meeting.id, 'cancelled');
      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Meeting cancelled.".tr()),
              backgroundColor: Colors.white24,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        await _loadMeetings();
      }
    } catch (e) {
      debugPrint("Error cancelling meeting: $e");
    }
  }

  Future<void> _loadConnections() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserId = currentUser?.id;
      if (currentUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final response = await Supabase.instance.client
          .from('connections')
          .select()
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false);

      List<Map<String, dynamic>> loaded = List<Map<String, dynamic>>.from(
        response,
      ).where((row) => row['status'] != 'pending').toList();

      if (mounted) {
        setState(() {
          _supabaseConnections = loaded;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _supabaseConnections = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRequests() async {
    try {
      if (mounted) setState(() => _isLoadingRequests = true);
      final incoming = await _supabaseService.fetchIncomingConnectionRequests();
      final sent = await _supabaseService.fetchSentConnectionRequests();
      if (mounted) {
        setState(() {
          _incomingRequests = incoming;
          _sentRequests = sent;
          _isLoadingRequests = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading connection requests: $e");
      if (mounted) setState(() => _isLoadingRequests = false);
    }
  }

  void _confirmDeleteConnection(Map<String, dynamic> connection) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B0F19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: Text(
            "Delete Contact".tr(),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            "Are you sure you want to delete ${connection['name']} from your contacts?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                "Cancel".tr(),
                style: const TextStyle(color: Colors.white38),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(context);
                setState(() => _isLoading = true);

                try {
                  if (connection['id'] != null) {
                    await Supabase.instance.client
                        .from('connections')
                        .delete()
                        .eq('id', connection['id']);
                  }

                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text("Deleted ${connection['name']}!"),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                } catch (e) {
                  debugPrint("Error deleting connection: $e");
                }

                _loadConnections();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                "Delete".tr(),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showExportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return ExportContactsSheet(connections: _supabaseConnections);
      },
    );
  }

  Future<void> _acceptRequest(ConnectionRequestModel request) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await _supabaseService.acceptConnectionRequest(
      request.id,
      request.senderId,
    );

    if (success) {
      ref.invalidate(connectionStatusProvider(request.senderId));
      ref.invalidate(incomingRequestsCountProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text("Connected with ${request.senderName ?? 'user'}! Added to contacts."),
          backgroundColor: EventzoneTheme.accentSuccess,
        ),
      );
      _loadAllData();
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Failed to accept request. Please try again."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _declineRequest(ConnectionRequestModel request) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await _supabaseService.declineConnectionRequest(request.id);

    if (success) {
      ref.invalidate(connectionStatusProvider(request.senderId));
      ref.invalidate(incomingRequestsCountProvider);
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Request declined"),
          backgroundColor: Colors.white24,
        ),
      );
      _loadRequests();
    }
  }

  Future<void> _cancelSentRequest(ConnectionRequestModel request) async {
    final messenger = ScaffoldMessenger.of(context);
    final success = await _supabaseService.cancelSentConnectionRequest(request.id);

    if (success) {
      ref.invalidate(connectionStatusProvider(request.receiverId));
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Request cancelled"),
          backgroundColor: Colors.white24,
        ),
      );
      _loadRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: RefreshIndicator(
            color: EventzoneTheme.primaryAction,
            backgroundColor: const Color(0xFF0B0F19),
            onRefresh: _loadAllData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  _buildTabBar(),
                  if (_currentTab == NetworkTab.contacts) ...[
                    _buildPendingRequestsBanner(),
                    _buildSearchBar(),
                    _buildTagsList(),
                    _buildSection(
                      context,
                      "Connected Professionals".tr(),
                      _buildContactsGrid(),
                    ),
                  ] else if (_currentTab == NetworkTab.requests) ...[
                    _buildRequestsView(),
                  ] else ...[
                    _buildMeetingsView(),
                  ],
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                "My Network".tr(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  fontSize: 32,
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showExportOptions,
                    child: const Icon(
                      LucideIcons.download,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DirectMessagesScreen(),
                        ),
                      ).then((_) {
                        final uid = Supabase.instance.client.auth.currentUser?.id;
                        if (uid != null) _fetchUnreadCount(uid);
                      });
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        const Icon(
                          LucideIcons.messageCircle,
                          color: Colors.white,
                          size: 26,
                        ),
                        if (_unreadCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                "$_unreadCount",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "Manage your connections, leads and requests".tr(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final incomingCount = _incomingRequests.length;
    final incomingMeetingsCount = _receivedMeetingRequests.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            // 1. Contacts Tab
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _currentTab = NetworkTab.contacts),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                  decoration: BoxDecoration(
                    color: _currentTab == NetworkTab.contacts
                        ? EventzoneTheme.primaryAction
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          "Contacts".tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _currentTab == NetworkTab.contacts
                                ? Colors.white
                                : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (_supabaseConnections.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: _currentTab == NetworkTab.contacts
                                ? Colors.white.withValues(alpha: 0.22)
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "${_supabaseConnections.length}",
                            style: TextStyle(
                              color: _currentTab == NetworkTab.contacts
                                  ? Colors.white
                                  : Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 4),

            // 2. Requests Tab
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _currentTab = NetworkTab.requests),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                  decoration: BoxDecoration(
                    color: _currentTab == NetworkTab.requests
                        ? EventzoneTheme.primaryAction
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          "Requests".tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _currentTab == NetworkTab.requests
                                ? Colors.white
                                : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (incomingCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.redAccent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "$incomingCount",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 4),

            // 3. Meetings Tab
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _currentTab = NetworkTab.meetings),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                  decoration: BoxDecoration(
                    color: _currentTab == NetworkTab.meetings
                        ? EventzoneTheme.primaryAction
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          "Meetings".tr(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _currentTab == NetworkTab.meetings
                                ? Colors.white
                                : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (incomingMeetingsCount > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            "$incomingMeetingsCount",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingRequestsBanner() {
    if (_incomingRequests.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        onTap: () {
          setState(() {
            _currentTab = NetworkTab.requests;
            _requestsSubTab = RequestsSubTab.received;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: EventzoneTheme.primaryAction.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: EventzoneTheme.primaryAction.withOpacity(0.5),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EventzoneTheme.primaryAction.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  LucideIcons.userPlus,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${_incomingRequests.length} pending connection request${_incomingRequests.length > 1 ? 's' : ''}",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      "Tap to review and connect",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const Icon(
                LucideIcons.chevronRight,
                color: Colors.white,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        borderRadius: 30,
        child: TextField(
          style: const TextStyle(color: Colors.white),
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
          decoration: InputDecoration(
            hintText: "Search connections...".tr(),
            hintStyle: const TextStyle(color: Colors.white38),
            border: InputBorder.none,
            icon: const Icon(LucideIcons.search, color: Colors.white38, size: 20),
          ),
        ),
      ),
    );
  }

  List<String> get _allTags {
    final Set<String> tags = {};
    for (var conn in _supabaseConnections) {
      if (conn['tags'] != null && conn['tags'] is List) {
        for (var t in conn['tags']) {
          tags.add(t.toString());
        }
      }
    }
    return tags.toList()..sort();
  }

  Widget _buildTagsList() {
    final tags = _allTags;
    if (tags.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            _buildTagChip("All".tr(), _selectedTag == null, () {
              setState(() => _selectedTag = null);
            }),
            ...tags.map((tag) => _buildTagChip(tag, _selectedTag == tag, () {
              setState(() => _selectedTag = tag);
            })),
          ],
        ),
      ),
    );
  }

  Widget _buildTagChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? EventzoneTheme.primaryAction
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? EventzoneTheme.primaryAction : Colors.white12,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.white24,
              ),
            ],
          ),
        ),
        content,
      ],
    );
  }

  Widget _buildContactsGrid() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(40.0),
        child: Center(
          child: CircularProgressIndicator(color: EventzoneTheme.primaryAction),
        ),
      );
    }

    final filteredConnections = _supabaseConnections.where((c) {
      final name = (c['name'] ?? '').toString().toLowerCase();
      final title = (c['title'] ?? '').toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = name.contains(query) || title.contains(query);

      final matchesTag = _selectedTag == null ||
          (c['tags'] != null &&
              (c['tags'] as List).map((e) => e.toString()).contains(_selectedTag));

      return matchesSearch && matchesTag;
    }).toList();

    if (filteredConnections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.users, size: 48, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 12),
              Text(
                _searchQuery.isNotEmpty
                    ? "No connections found matching search."
                    : "You haven't connected with anyone yet.\nExplore the attendee directory to connect!",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: filteredConnections.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final connection = filteredConnections[index];
          final String name = connection['name'] ?? 'Attendee';
          final String rawTitle = connection['title'] ?? '';
          final String title = rawTitle.replaceAll(' @', ' @');
          final String avatarUrl = connection['avatar_url'] ?? '';
          final String? source = connection['source'];
          final bool isNew = connection['is_new'] == true;

          return GestureDetector(
            onLongPress: () => _confirmDeleteConnection(connection),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfessionalProfileScreen(
                    name: name,
                    title: title,
                    avatarUrl: avatarUrl,
                    source: source,
                    isNew: isNew ? 'true' : 'false',
                    email: connection['email'],
                    phone: connection['phone'],
                    website: connection['website'],
                    company: connection['company'],
                    department: connection['department'],
                    notes: connection['notes'],
                    tags: connection['tags'] != null
                        ? List<String>.from(connection['tags'])
                        : null,
                    address: connection['address'],
                    connectionId: connection['id'],
                    createdAt: connection['created_at'],
                    targetUserId:
                        connection['linked_profile_id'] ??
                        connection['connected_user_id'] ??
                        connection['target_user_id'],
                  ),
                ),
              ).then((_) => _loadAllData());
            },
            child: GlassContainer(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white10,
                    backgroundImage: getAvatarProvider(avatarUrl),
                    child: getAvatarProvider(avatarUrl) == null
                        ? const Icon(
                            LucideIcons.user,
                            size: 20,
                            color: Colors.white54,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Colors.white,
                              ),
                            ),
                            if (isNew) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: EventzoneTheme.primaryAction
                                      .withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: EventzoneTheme.primaryAction
                                        .withOpacity(0.4),
                                    width: 1,
                                  ),
                                ),
                                child: const Text(
                                  "NEW",
                                  style: TextStyle(
                                    color: EventzoneTheme.primaryAction,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (title.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    LucideIcons.chevronRight,
                    color: Colors.white24,
                    size: 18,
                  ),
                ],
              ),
            ),
          )
              .animate(delay: (index * 20).ms)
              .fade(duration: 150.ms)
              .slideY(
                begin: 0.1,
                end: 0,
                duration: 150.ms,
                curve: Curves.easeOutQuad,
              );
        },
      ),
    );
  }

  // 📬 Requests View (Received / Sent)
  Widget _buildRequestsView() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSubTabChip(
                  "Received".tr(),
                  _incomingRequests.length,
                  _requestsSubTab == RequestsSubTab.received,
                  () => setState(() => _requestsSubTab = RequestsSubTab.received),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSubTabChip(
                  "Sent".tr(),
                  _sentRequests.length,
                  _requestsSubTab == RequestsSubTab.sent,
                  () => setState(() => _requestsSubTab = RequestsSubTab.sent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoadingRequests)
            const Padding(
              padding: EdgeInsets.all(40.0),
              child: Center(
                child: CircularProgressIndicator(color: EventzoneTheme.primaryAction),
              ),
            )
          else if (_requestsSubTab == RequestsSubTab.received)
            _buildReceivedRequestsList()
          else
            _buildSentRequestsList(),
        ],
      ),
    );
  }

  Widget _buildSubTabChip(
    String label,
    int count,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? EventzoneTheme.primaryAction
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? EventzoneTheme.primaryAction : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$count",
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceivedRequestsList() {
    if (_incomingRequests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.inbox, size: 48, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 12),
              const Text(
                "No pending connection requests received.",
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _incomingRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final request = _incomingRequests[index];
        final name = request.senderName ?? 'Attendee';
        final job = request.senderTitle ?? '';
        final company = request.senderCompany ?? '';
        final subtitle = company.isNotEmpty
            ? (job.isNotEmpty ? "$job @$company" : company)
            : job;

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white10,
                    backgroundImage: getAvatarProvider(request.senderAvatarUrl ?? ''),
                    child: getAvatarProvider(request.senderAvatarUrl ?? '') == null
                        ? const Icon(LucideIcons.user, color: Colors.white54, size: 22)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              if (request.message != null && request.message!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.quote, size: 14, color: Colors.white38),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          request.message!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptRequest(request),
                      icon: const Icon(LucideIcons.check, size: 16),
                      label: Text("Accept".tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EventzoneTheme.primaryAction,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _declineRequest(request),
                      icon: const Icon(LucideIcons.x, size: 16),
                      label: Text("Decline".tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSentRequestsList() {
    if (_sentRequests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.send, size: 48, color: Colors.white.withOpacity(0.2)),
              const SizedBox(height: 12),
              const Text(
                "No pending requests sent.",
                style: TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sentRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final request = _sentRequests[index];
        final name = request.receiverName ?? 'Attendee';
        final job = request.receiverTitle ?? '';
        final company = request.receiverCompany ?? '';
        final subtitle = company.isNotEmpty
            ? (job.isNotEmpty ? "$job @$company" : company)
            : job;

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white10,
                backgroundImage: getAvatarProvider(request.receiverAvatarUrl ?? ''),
                child: getAvatarProvider(request.receiverAvatarUrl ?? '') == null
                    ? const Icon(LucideIcons.user, color: Colors.white54, size: 20)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.clock, size: 10, color: Colors.amber),
                          SizedBox(width: 4),
                          Text(
                            "Pending response",
                            style: TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _cancelSentRequest(request),
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
        );
      },
    );
  }

  Widget _buildMeetingsView() {
    final totalRequests = _receivedMeetingRequests.length + _sentMeetingRequests.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-tabs row: Upcoming vs Requests
          Row(
            children: [
              Expanded(
                child: _buildSubTabChip(
                  "Upcoming".tr(),
                  _upcomingMeetings.length,
                  _meetingsSubTab == MeetingsSubTab.upcoming,
                  () => setState(() => _meetingsSubTab = MeetingsSubTab.upcoming),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSubTabChip(
                  "Requests".tr(),
                  totalRequests,
                  _meetingsSubTab == MeetingsSubTab.requests,
                  () => setState(() => _meetingsSubTab = MeetingsSubTab.requests),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (_isLoadingMeetings)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(color: EventzoneTheme.primaryAction),
              ),
            )
          else if (_meetingsSubTab == MeetingsSubTab.upcoming) ...[
            _buildUpcomingMeetingsList(),
          ] else ...[
            // Secondary filter for Requests: Received vs Sent
            Row(
              children: [
                Expanded(
                  child: _buildMeetingFilterChip(
                    "Received".tr(),
                    _receivedMeetingRequests.length,
                    _meetingRequestsFilter == MeetingRequestsSubFilter.received,
                    () => setState(() => _meetingRequestsFilter = MeetingRequestsSubFilter.received),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMeetingFilterChip(
                    "Sent".tr(),
                    _sentMeetingRequests.length,
                    _meetingRequestsFilter == MeetingRequestsSubFilter.sent,
                    () => setState(() => _meetingRequestsFilter = MeetingRequestsSubFilter.sent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_meetingRequestsFilter == MeetingRequestsSubFilter.received)
              _buildReceivedMeetingsList()
            else
              _buildSentMeetingsList(),
          ],
        ],
      ),
    );
  }

  Widget _buildMeetingFilterChip(
    String label,
    int count,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2563EB)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12.5,
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$count",
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingMeetingsList() {
    if (_upcomingMeetings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.calendar, size: 48, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                "No upcoming meetings scheduled.".tr(),
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _upcomingMeetings.length,
      separatorBuilder: (context, index) => const SizedBox(height: 14),
      itemBuilder: (context, index) {
        final meeting = _upcomingMeetings[index];
        final currentUserId = Supabase.instance.client.auth.currentUser?.id;
        final otherId = meeting.organizerId == currentUserId ? meeting.attendeeId : meeting.organizerId;
        final name = meeting.otherName ?? 'Attendee';
        final job = meeting.otherTitle ?? '';
        final company = meeting.otherCompany ?? '';
        final subtitle = company.isNotEmpty
            ? (job.isNotEmpty ? "$job @$company" : company)
            : job;

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Attendee info + Confirmed Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white10,
                    backgroundImage: getAvatarProvider(meeting.otherAvatarUrl ?? ''),
                    child: getAvatarProvider(meeting.otherAvatarUrl ?? '') == null
                        ? const Icon(LucideIcons.user, color: Colors.white54, size: 20)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.checkCheck, size: 12, color: Color(0xFF10B981)),
                        const SizedBox(width: 4),
                        Text(
                          "Confirmed".tr(),
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Meeting Title
              Text(
                meeting.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              // Date & Time pills
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.calendar, size: 12, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 5),
                        Text(
                          meeting.date,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.clock, size: 12, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 5),
                        Text(
                          "${meeting.startTime} - ${meeting.endTime}",
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (meeting.location != null && meeting.location!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(LucideIcons.mapPin, size: 13, color: Colors.white54),
                    const SizedBox(width: 5),
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
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(LucideIcons.quote, size: 13, color: Colors.white38),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          meeting.note!.trim(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ChatDetailScreen(
                              contactName: name,
                              avatarUrl: meeting.otherAvatarUrl ?? '',
                              recipientId: otherId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.messageCircle, size: 15),
                      label: Text("Message".tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EventzoneTheme.primaryAction,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfessionalProfileScreen(
                              name: name,
                              title: job,
                              avatarUrl: meeting.otherAvatarUrl ?? '',
                              company: company,
                              connectionId: otherId,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.user, size: 15),
                      label: Text("Profile".tr()),
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
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => _confirmCancelMeeting(meeting),
                    child: Text(
                      "Cancel".tr(),
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmCancelMeeting(MeetingModel meeting) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("Cancel Meeting".tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to cancel this meeting with ${meeting.otherName ?? 'Attendee'}?".tr(),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text("Keep".tr(), style: const TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelMeeting(meeting);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text("Cancel Meeting".tr(), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildReceivedMeetingsList() {
    if (_receivedMeetingRequests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.inbox, size: 48, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                "No pending meeting requests received.".tr(),
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _receivedMeetingRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final meeting = _receivedMeetingRequests[index];
        final name = meeting.otherName ?? 'Attendee';
        final job = meeting.otherTitle ?? '';
        final company = meeting.otherCompany ?? '';
        final subtitle = company.isNotEmpty
            ? (job.isNotEmpty ? "$job @$company" : company)
            : job;

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.white10,
                    backgroundImage: getAvatarProvider(meeting.otherAvatarUrl ?? ''),
                    child: getAvatarProvider(meeting.otherAvatarUrl ?? '') == null
                        ? const Icon(LucideIcons.user, color: Colors.white54, size: 22)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Text(
                meeting.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.calendar, size: 12, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 5),
                        Text(
                          meeting.date,
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.clock, size: 12, color: Color(0xFF38BDF8)),
                        const SizedBox(width: 5),
                        Text(
                          "${meeting.startTime} - ${meeting.endTime}",
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (meeting.note != null && meeting.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Text(
                    "\"${meeting.note!.trim()}\"",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _acceptMeeting(meeting),
                      icon: const Icon(LucideIcons.check, size: 16),
                      label: Text("Accept".tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _declineMeeting(meeting),
                      icon: const Icon(LucideIcons.x, size: 16),
                      label: Text("Decline".tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSentMeetingsList() {
    if (_sentMeetingRequests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Icon(LucideIcons.send, size: 48, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              Text(
                "No pending meeting requests sent.".tr(),
                style: const TextStyle(color: Colors.white38, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _sentMeetingRequests.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final meeting = _sentMeetingRequests[index];
        final name = meeting.otherName ?? 'Attendee';
        final job = meeting.otherTitle ?? '';
        final company = meeting.otherCompany ?? '';
        final subtitle = company.isNotEmpty
            ? (job.isNotEmpty ? "$job @$company" : company)
            : job;

        return GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: 20,
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white10,
                backgroundImage: getAvatarProvider(meeting.otherAvatarUrl ?? ''),
                child: getAvatarProvider(meeting.otherAvatarUrl ?? '') == null
                    ? const Icon(LucideIcons.user, color: Colors.white54, size: 20)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      "${meeting.date} • ${meeting.startTime} - ${meeting.endTime}",
                      style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(LucideIcons.clock, size: 10, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            "Pending response".tr(),
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _cancelMeeting(meeting),
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
        );
      },
    );
  }
}
