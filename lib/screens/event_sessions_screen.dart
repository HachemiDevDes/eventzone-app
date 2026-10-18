import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/status_pill.dart';
import '../providers/session_providers.dart';
import 'schedule_screen.dart';
import 'session_detail_screen.dart';

class EventSessionsScreen extends ConsumerStatefulWidget {
  final String eventId;
  const EventSessionsScreen({super.key, required this.eventId});

  @override
  ConsumerState<EventSessionsScreen> createState() => _EventSessionsScreenState();
}

class _EventSessionsScreenState extends ConsumerState<EventSessionsScreen> {
  String? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final sessionsAsync = ref.watch(sessionsProvider(widget.eventId));
    final favoritesAsync = ref.watch(sessionFavoritesProvider);

    final canPop = Navigator.canPop(context);

    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: canPop ? 12 : 72),
              
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (canPop)
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                "Back".tr(),
                                style: const TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "SCHEDULE".tr(),
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                      color: EventzoneTheme.primaryAction,
                                      letterSpacing: 2,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Sessions & Agenda".tr(),
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 28,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(LucideIcons.calendarClock, color: Colors.white, size: 24),
                          tooltip: "My Meetings".tr(),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const MyMeetingsScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Async State Builder
              Expanded(
                child: sessionsAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: EventzoneTheme.primaryAction),
                  ),
                  error: (err, stack) => Center(
                    child: Text(
                      "Error loading sessions: $err",
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  data: (sessions) {
                    if (sessions.isEmpty) {
                      return Center(
                        child: Text("No sessions scheduled for this event.".tr(), style: TextStyle(color: Colors.white38)),
                      );
                    }

                    // Extract unique day keys dynamically
                    final Map<String, String> dayKeyToTabLabel = {};
                    final distinctKeys = <String>{};
                    for (final s in sessions) {
                      distinctKeys.add(s.dateKey);
                    }
                    final sortedKeys = distinctKeys.toList()..sort();
                    for (int i = 0; i < sortedKeys.length; i++) {
                      final key = sortedKeys[i];
                      final sampleSession = sessions.firstWhere((s) => s.dateKey == key);
                      final dayNum = "Day ${i + 1}";
                      dayKeyToTabLabel[key] = "$dayNum • ${sampleSession.shortDate}";
                    }

                    // Default selection
                    if (_selectedDay == null || !sortedKeys.contains(_selectedDay)) {
                      _selectedDay = sortedKeys.isNotEmpty ? sortedKeys.first : '';
                    }

                    // Filter sessions for selected day
                    final filteredSessions = sessions.where((s) => s.dateKey == _selectedDay).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Day Selector Tabs
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          child: Row(
                            children: sortedKeys.map((key) {
                              final isSelected = _selectedDay == key;
                              final tabLabel = dayKeyToTabLabel[key] ?? key;
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _selectedDay = key;
                                  });
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 12),
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isSelected ? EventzoneTheme.primaryAction : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(color: isSelected ? Colors.transparent : Colors.white10),
                                  ),
                                  child: Text(
                                    tabLabel,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white60,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Sessions List
                        Expanded(
                          child: filteredSessions.isEmpty
                              ? Center(
                                  child: Text("No sessions on this day.".tr(), style: TextStyle(color: Colors.white38)),
                                )
                              : ListView.builder(
                                  physics: BouncingScrollPhysics(),
                                  padding: EdgeInsets.symmetric(horizontal: 24),
                                  itemCount: filteredSessions.length,
                                  itemBuilder: (context, index) {
                                    final session = filteredSessions[index];
                                    final favList = favoritesAsync.value ?? [];
                                    final isFav = favList.contains(session.id);

                                    final startTimeStr = _formatTime(session.startTime);
                                    final endTimeStr = _formatTime(session.endTime);
                                    final isLive = _isSessionLive(session.startTime, session.endTime);
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
                                            // Refresh favorites count / list in parent on pop
                                            ref.invalidate(sessionFavoritesProvider);
                                          });
                                        },
                                        child: GlassContainer(
                                          padding: const EdgeInsets.all(20),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              // Time slot column with Day badge
                                              SizedBox(
                                                width: 88,
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      startTimeStr,
                                                      style: TextStyle(
                                                        color: isLive ? EventzoneTheme.primaryAction : Colors.white,
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
                                                    // Prominent Day badge on session card
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
                                                    if (isLive) ...[
                                                      const SizedBox(height: 8),
                                                      const StatusPill(label: "LIVE", isLive: true),
                                                    ]
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Container(width: 1, height: 72, color: Colors.white10),
                                              const SizedBox(width: 16),
                                              
                                              // Content column
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
                                                            session.location ?? "TBA",
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
                                                        // Speakers avatar stack / indicator
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
                                                          
                                                        // Agenda quick-favorite toggle button
                                                        GestureDetector(
                                                          onTap: () {
                                                            ref.read(sessionFavoritesProvider.notifier).toggleFavorite(session.id);
                                                          },
                                                          child: Icon(
                                                            isFav ? LucideIcons.bookmarkCheck : LucideIcons.bookmarkPlus,
                                                            size: 20,
                                                            color: isFav ? EventzoneTheme.accentSuccess : EventzoneTheme.primaryAction,
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
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Format Start Time
  String _formatTime(DateTime dateTime) {
    final localTime = dateTime.toLocal();
    final hour = localTime.hour;
    final min = localTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return "$formattedHour:$min $period";
  }

  // Determine if the session is currently happening
  bool _isSessionLive(DateTime start, DateTime end) {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }
}
