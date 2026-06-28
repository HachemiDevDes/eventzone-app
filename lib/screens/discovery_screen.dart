import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/event_card.dart';
import '../models/event_model.dart';
import 'event_details_screen.dart';
import 'edit_profile_screen.dart';
import '../services/supabase_service.dart';
import '../widgets/glass_container.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class DiscoveryScreen extends StatefulWidget {
  final List<EventModel> events;
  final Function(EventModel) onEventJoined;
  final Function(EventModel) onAccessEvent;

  const DiscoveryScreen({
    super.key, 
    required this.events,
    required this.onEventJoined,
    required this.onAccessEvent,
  });

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _supabaseService = SupabaseService();
  static const String _profileId = "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
  String _fullName = "Hachemi Mohamed";
  String _avatarUrl = "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&fit=crop";
  String _searchQuery = "";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final data = await _supabaseService.fetchProfile(_profileId);
    if (data != null) {
      setState(() {
        if (data['full_name'] != null) _fullName = data['full_name'];
        if (data['avatar_url'] != null) _avatarUrl = data['avatar_url'];
      });
    }
  }

  ImageProvider _getAvatarProvider(String url) {
    if (url.startsWith("data:image")) {
      try {
        final base64Content = url.split(",")[1];
        return MemoryImage(base64Decode(base64Content));
      } catch (_) {
        // Fallback
      }
    }
    return NetworkImage(url);
  }

  @override
  Widget build(BuildContext context) {
    final filteredEvents = widget.events.where((event) {
      final title = event.title.toLowerCase();
      final category = event.category.toLowerCase();
      final location = event.location.toLowerCase();
      final query = _searchQuery.toLowerCase();
      return title.contains(query) || category.contains(query) || location.contains(query);
    }).toList();

    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Welcome back,",
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white60,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                          Text(
                            _fullName,
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 28,
                                ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const EditProfileScreen()),
                          );
                          if (result == true) {
                            _loadProfile();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: EventzoneTheme.primaryAction, width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 24,
                            backgroundImage: _getAvatarProvider(_avatarUrl),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
                      decoration: const InputDecoration(
                        hintText: "Search events...",
                        hintStyle: TextStyle(color: Colors.white38),
                        border: InputBorder.none,
                        icon: Icon(LucideIcons.search, color: Colors.white38, size: 20),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              
              if (filteredEvents.isEmpty)
                const SliverFillRemaining(
                  child: Center(
                    child: Text("No events found matching search.", style: TextStyle(color: Colors.white24)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final event = filteredEvents[index];
                        return EventCard(
                          title: event.title,
                          date: event.date,
                          location: event.location,
                          category: event.category,
                          imageUrl: event.imageUrl,
                          isJoined: event.isJoined,
                          onRegister: () {
                            widget.onEventJoined(event);
                          },
                          onViewDetails: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EventDetailsScreen(
                                  event: event,
                                  onRegister: () => widget.onEventJoined(event),
                                  onAccess: () => widget.onAccessEvent(event),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: filteredEvents.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}
