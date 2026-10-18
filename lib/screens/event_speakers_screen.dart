import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/session_model.dart';
import '../providers/session_providers.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';

class EventSpeakersScreen extends ConsumerStatefulWidget {
  final String? eventId;

  const EventSpeakersScreen({super.key, this.eventId});

  @override
  ConsumerState<EventSpeakersScreen> createState() => _EventSpeakersScreenState();
}

class _EventSpeakersScreenState extends ConsumerState<EventSpeakersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final eventId = widget.eventId ?? '';
    final speakersAsync = eventId.isNotEmpty
        ? ref.watch(eventSpeakersProvider(eventId))
        : const AsyncValue.data(<SessionSpeaker>[]);

    final canPop = Navigator.canPop(context);

    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header & Top Spacing
              SizedBox(height: canPop ? 12 : 72),
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
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "SPEAKERS".tr(),
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: EventzoneTheme.primaryAction,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Speakers & Experts".tr(),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 26,
                                    color: Colors.white,
                                  ),
                            ),
                          ],
                        ),
                        speakersAsync.maybeWhen(
                          data: (speakers) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: EventzoneTheme.primaryAction.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: EventzoneTheme.primaryAction.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              "${speakers.length}",
                              style: const TextStyle(
                                color: EventzoneTheme.primaryAction,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Search input
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val.trim().toLowerCase();
                          });
                        },
                        decoration: InputDecoration(
                          hintText: "Search speakers, topics, company...".tr(),
                          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13.5),
                          prefixIcon: const Icon(LucideIcons.search, color: Colors.white38, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(LucideIcons.x, color: Colors.white38, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Speakers List or State
              Expanded(
                child: speakersAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(color: EventzoneTheme.primaryAction),
                  ),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        "Failed to load speakers: $err",
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  data: (speakers) {
                    if (speakers.isEmpty) {
                      return _buildEmptyState(
                        icon: LucideIcons.mic2,
                        title: "No Speakers Yet".tr(),
                        subtitle: "No speakers have been announced for this event yet.".tr(),
                      );
                    }

                    final filtered = speakers.where((s) {
                      if (_searchQuery.isEmpty) return true;
                      return s.name.toLowerCase().contains(_searchQuery) ||
                          s.title.toLowerCase().contains(_searchQuery) ||
                          s.company.toLowerCase().contains(_searchQuery) ||
                          (s.bio != null && s.bio!.toLowerCase().contains(_searchQuery));
                    }).toList();

                    if (filtered.isEmpty) {
                      return _buildEmptyState(
                        icon: LucideIcons.searchX,
                        title: "No Matching Speakers".tr(),
                        subtitle: "Try searching with a different name or organization.".tr(),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      physics: const BouncingScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final speaker = filtered[index];
                        return _buildSpeakerCard(context, speaker, eventId);
                      },
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

  Widget _buildSpeakerCard(BuildContext context, SessionSpeaker speaker, String eventId) {
    final subtitleText = speaker.company.isNotEmpty
        ? (speaker.title.isNotEmpty ? "${speaker.title} • ${speaker.company}" : speaker.company)
        : speaker.title;

    final hasRoleBadge = speaker.role != null &&
        speaker.role!.trim().isNotEmpty &&
        speaker.role!.toLowerCase() != 'speaker';

    return GestureDetector(
      onTap: () => _showSpeakerDetailsSheet(context, speaker, eventId),
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Speaker Avatar
            _buildSpeakerAvatar(speaker, size: 56),
            const SizedBox(width: 16),

            // Info Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          speaker.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasRoleBadge) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            speaker.role!.toUpperCase(),
                            style: const TextStyle(
                              color: Color(0xFFA78BFA),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitleText.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12.5,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (speaker.bio != null && speaker.bio!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      speaker.bio!.trim(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11.5,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(LucideIcons.chevronRight, color: Colors.white24, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeakerAvatar(SessionSpeaker speaker, {required double size}) {
    final avatarUrl = speaker.avatarUrl.trim();
    if (avatarUrl.isNotEmpty &&
        (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) &&
        !avatarUrl.contains('ui-avatars.com')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF2563EB).withValues(alpha: 0.45), width: 2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.15),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            avatarUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _buildInitialsAvatar(speaker.name, size),
          ),
        ),
      );
    }
    return _buildInitialsAvatar(speaker.name, size);
  }

  Widget _buildInitialsAvatar(String name, double size) {
    final trimmed = name.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? "${parts[0][0]}${parts[1][0]}".toUpperCase()
        : (trimmed.isNotEmpty ? trimmed[0].toUpperCase() : "S");

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            EventzoneTheme.primaryAction.withValues(alpha: 0.4),
            EventzoneTheme.primaryAction.withValues(alpha: 0.15),
          ],
        ),
        border: Border.all(color: EventzoneTheme.primaryAction.withValues(alpha: 0.4), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: Icon(icon, color: Colors.white30, size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeakerDetailsSheet(BuildContext context, SessionSpeaker speaker, String eventId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Consumer(
          builder: (context, ref, _) {
            final sessionsAsync = eventId.isNotEmpty
                ? ref.watch(sessionsProvider(eventId))
                : const AsyncValue.data(<SessionModel>[]);

            // Filter sessions by this speaker
            final speakerSessions = sessionsAsync.maybeWhen(
              data: (allSessions) => allSessions.where((sess) {
                return sess.speakers.any((s) =>
                    s.name.trim().toLowerCase() == speaker.name.trim().toLowerCase() ||
                    (s.email != null && speaker.email != null && s.email!.toLowerCase() == speaker.email!.toLowerCase()));
              }).toList(),
              orElse: () => <SessionModel>[],
            );

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFF0F1523),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: Colors.white12, width: 0.8)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Header with Avatar and Basic Info
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSpeakerAvatar(speaker, size: 70),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    speaker.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (speaker.title.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      speaker.title,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.8),
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                  if (speaker.company.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      speaker.company,
                                      style: const TextStyle(
                                        color: EventzoneTheme.primaryAction,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (speaker.role != null && speaker.role!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: EventzoneTheme.primaryAction.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        speaker.role!,
                                        style: const TextStyle(
                                          color: EventzoneTheme.primaryAction,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Email contact action
                        if (speaker.email != null && speaker.email!.trim().isNotEmpty) ...[
                          const SizedBox(height: 20),
                          GestureDetector(
                            onTap: () async {
                              final Uri emailUri = Uri(
                                scheme: 'mailto',
                                path: speaker.email!.trim(),
                              );
                              if (await canLaunchUrl(emailUri)) {
                                await launchUrl(emailUri);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(LucideIcons.mail, color: EventzoneTheme.primaryAction, size: 16),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      speaker.email!.trim(),
                                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const Icon(LucideIcons.externalLink, color: Colors.white30, size: 14),
                                ],
                              ),
                            ),
                          ),
                        ],

                        // Biography section
                        if (speaker.bio != null && speaker.bio!.trim().isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            "ABOUT".tr(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            speaker.bio!.trim(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              height: 1.55,
                            ),
                          ),
                        ],

                        // Sessions section
                        if (speakerSessions.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Text(
                            "SESSIONS WITH THIS SPEAKER".tr(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...speakerSessions.map((sess) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: EventzoneTheme.primaryAction.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        sess.resolveDayLabel(),
                                        style: const TextStyle(
                                          color: EventzoneTheme.primaryAction,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            sess.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            sess.formattedDate,
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],

                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text("Close".tr()),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
