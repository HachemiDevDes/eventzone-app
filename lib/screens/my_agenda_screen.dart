import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../providers/session_providers.dart';
import 'schedule_screen.dart';
import 'session_detail_screen.dart';

class MyAgendaScreen extends ConsumerStatefulWidget {
  final String eventId;
  const MyAgendaScreen({super.key, required this.eventId});

  @override
  ConsumerState<MyAgendaScreen> createState() => _MyAgendaScreenState();
}

class _MyAgendaScreenState extends ConsumerState<MyAgendaScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 72),
              
              // Header Title
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "MY HUB".tr(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: EventzoneTheme.primaryAction,
                            letterSpacing: 2,
                          ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      "My Agenda".tr(),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                          ),
                    ),
                  ],
                ),
              ),

              // Tab Bar Selector
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: EventzoneTheme.primaryAction,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white38,
                    labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, ),
                    unselectedLabelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, ),
                    dividerColor: Colors.transparent,
                    padding: EdgeInsets.all(4),
                    tabs: const [
                      Tab(text: "Saved Sessions"),
                      Tab(text: "Meetings"),
                    ],
                  ),
                ),
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSessionsTab(),
                    MyMeetingsScreen(embedMode: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSessionsTab() {
    final sessionsAsync = ref.watch(sessionsProvider(widget.eventId));
    final favoritesAsync = ref.watch(sessionFavoritesProvider);

    return favoritesAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: EventzoneTheme.primaryAction)),
      error: (err, _) => Center(child: Text("Error: $err", style: TextStyle(color: Colors.white38))),
      data: (favIds) {
        if (favIds.isEmpty) {
          return _buildSessionsEmptyState();
        }

        return sessionsAsync.when(
          loading: () => Center(child: CircularProgressIndicator(color: EventzoneTheme.primaryAction)),
          error: (err, _) => Center(child: Text("Error: $err", style: TextStyle(color: Colors.white38))),
          data: (sessions) {
            // Filter sessions that are in favorites
            final favoritedSessions = sessions.where((s) => favIds.contains(s.id)).toList();

            if (favoritedSessions.isEmpty) {
              return _buildSessionsEmptyState();
            }

            return ListView.builder(
              physics: BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              itemCount: favoritedSessions.length,
              itemBuilder: (context, index) {
                final session = favoritedSessions[index];
                final startTimeStr = _formatTime(session.startTime);
                final endTimeStr = _formatTime(session.endTime);
                final dayLabel = session.resolveDayLabel(sessions);
                final fullDayLabel = session.resolveFullDayLabel(sessions);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SessionDetailScreen(session: session),
                        ),
                      ).then((_) {
                        ref.invalidate(sessionFavoritesProvider);
                      });
                    },
                    child: GlassContainer(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time & Day Tag
                          SizedBox(
                            width: 88,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  startTimeStr,
                                  style: const TextStyle(
                                    color: EventzoneTheme.primaryAction,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  endTimeStr,
                                  style: const TextStyle(
                                    color: Colors.white38,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: EventzoneTheme.primaryAction.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: EventzoneTheme.primaryAction.withValues(alpha: 0.35)),
                                  ),
                                  child: Text(
                                    dayLabel,
                                    style: const TextStyle(
                                      color: EventzoneTheme.primaryAction,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(width: 1, height: 72, color: Colors.white10),
                          const SizedBox(width: 16),

                          // Content
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Day & Date Pill and Track (Flexible Wrap prevents overflow on any screen)
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    return Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.white10),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(LucideIcons.calendar, size: 10, color: Colors.white60),
                                              const SizedBox(width: 4),
                                              Text(
                                                fullDayLabel,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 10.5,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (session.track != null && session.track!.trim().isNotEmpty)
                                          Container(
                                            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                            decoration: BoxDecoration(
                                              color: EventzoneTheme.primaryAction.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: EventzoneTheme.primaryAction.withValues(alpha: 0.25),
                                              ),
                                            ),
                                            child: Text(
                                              session.track!.trim().toUpperCase(),
                                              style: const TextStyle(
                                                color: EventzoneTheme.primaryAction,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                letterSpacing: 0.5,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  session.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.white,
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(LucideIcons.mapPin, size: 12, color: Colors.white38),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        session.location ?? 'TBA',
                                        style: const TextStyle(fontSize: 12, color: Colors.white38),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    if (session.speakers.isNotEmpty) ...[
                                      CircleAvatar(
                                        radius: 13,
                                        backgroundImage: session.speakers.first.avatarUrl.isNotEmpty
                                            ? NetworkImage(session.speakers.first.avatarUrl)
                                            : null,
                                        child: session.speakers.first.avatarUrl.isEmpty
                                            ? const Icon(LucideIcons.user, size: 12, color: Colors.white)
                                            : null,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          session.speakers.first.name +
                                              (session.speakers.length > 1
                                                  ? " +${session.speakers.length - 1}"
                                                  : ""),
                                          style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ] else
                                      const Spacer(),
                                    GestureDetector(
                                      onTap: () {
                                        ref.read(sessionFavoritesProvider.notifier).toggleFavorite(session.id);
                                      },
                                      child: const Icon(
                                        LucideIcons.bookmarkCheck,
                                        size: 20,
                                        color: EventzoneTheme.accentSuccess,
                                      ),
                                    ),
                                  ],
                                ),
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
          },
        );
      },
    );
  }

  Widget _buildSessionsEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.bookmarkPlus, color: Colors.white24, size: 48),
            SizedBox(height: 16),
            Text(
              "Your Agenda is Empty".tr(),
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              "Browse the list of sessions and add them to your agenda to construct your summit schedule.".tr(),
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            SizedBox(
              width: 180,
              height: 44,
              child: ElevatedButton(
                onPressed: () {
                  // Navigate to Sessions List (index 7 in event view)
                  final navigator = Navigator.of(context);
                  if (navigator.canPop()) {
                    navigator.pop();
                  }
                  // Callback is onNavigate, which we can trigger by updating main state. 
                  // But since we are inside case 1 of EventScreen, we can pop or navigate directly.
                  // We can access ref/context to update main navigation or since it's case 7, we can trigger the parent tab change.
                  // Actually, to trigger tab switch, we can just use the parent's index callbacks.
                  // Wait, can we call the navigation callback? We can trigger a rebuild in the parent, or since _eventIndex is state,
                  // we can use a provider for event navigation!
                  // Wait, we can implement an eventNavigationProvider or just let the user browse by clicking the Event Hub grid.
                  // Let's keep it simple and just show a message, or we can use ref.read(eventIndexProvider) if we define one!
                  // Let's check how _eventIndex is managed in main.dart: it is a local state variable in _MainScreenState.
                  // That's fine, we can explain how to access all sessions from the hub!
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: EventzoneTheme.primaryAction,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text("Go to Hub".tr(), style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final hour = localTime.hour;
    final min = localTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return "$formattedHour:$min $period";
  }
}
