import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/status_pill.dart';
import '../models/event_model.dart';
import '../models/ticket_model.dart';
import '../models/session_model.dart';
import '../models/sponsor_model.dart';
import '../models/exhibitor_model.dart';
import '../models/form_model.dart';
import '../services/supabase_service.dart';
import '../widgets/ticket_selection_sheet.dart';
import '../widgets/ticket_registration_dialog.dart';
import 'event_speakers_screen.dart';
import 'event_partners_screen.dart';

class EventDetailsScreen extends StatefulWidget {
  final EventModel event;
  final VoidCallback onRegister;
  final VoidCallback onAccess;

  const EventDetailsScreen({
    super.key,
    required this.event,
    required this.onRegister,
    required this.onAccess,
  });

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  final _supabaseService = SupabaseService();
  late bool _isJoined;
  late String _registrationStatus; // 'none', 'pending', 'registered'

  List<TicketModel> _tickets = [];
  List<SessionModel> _sessions = [];
  List<SessionSpeaker> _speakers = [];
  List<SponsorModel> _sponsors = [];
  List<ExhibitorModel> _exhibitors = [];

  @override
  void initState() {
    super.initState();
    _isJoined = widget.event.isJoined;
    _registrationStatus = widget.event.registrationStatus;
    _loadEventData();
  }

  Future<void> _loadEventData() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final currentUserEmail = Supabase.instance.client.auth.currentUser?.email;

    try {
      final futures = await Future.wait([
        _supabaseService.fetchTickets(widget.event.id),
        _supabaseService.fetchEventSessions(widget.event.id),
        _supabaseService.fetchEventSponsors(widget.event.id),
        _supabaseService.fetchEventExhibitors(widget.event.id),
        if (currentUserId != null)
          _supabaseService.checkEventRegistrationStatus(widget.event.id, currentUserId, currentUserEmail)
        else
          Future.value('none'),
        _supabaseService.fetchEventSpeakers(widget.event.id),
      ]);

      if (!mounted) return;

      final fetchedTickets = futures[0] as List<TicketModel>;
      final fetchedSessions = futures[1] as List<SessionModel>;
      final fetchedSponsors = futures[2] as List<SponsorModel>;
      final fetchedExhibitors = futures[3] as List<ExhibitorModel>;
      final fetchedStatus = futures[4] as String;
      final fetchedSpeakers = futures[5] as List<SessionSpeaker>;

      setState(() {
        _tickets = fetchedTickets;
        _sessions = fetchedSessions;
        _speakers = fetchedSpeakers;
        _sponsors = fetchedSponsors;
        _exhibitors = fetchedExhibitors;
        if (fetchedStatus != 'none') {
          _registrationStatus = fetchedStatus;
          _isJoined = fetchedStatus == 'registered';
          widget.event.registrationStatus = fetchedStatus;
          widget.event.isJoined = _isJoined;
        }
      });
    } catch (e) {
      debugPrint('Error loading event modules: $e');
    }
  }

  void _openTicketSelection() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Please sign in to register for this event.".tr()),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TicketSelectionSheet(
        eventTitle: widget.event.title,
        tickets: _tickets,
        onSelectTicket: (selectedTicket) {
          _openRegistrationForm(selectedTicket);
        },
      ),
    );
  }

  Future<void> _openRegistrationForm(TicketModel ticket) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    // Show loading indicator while retrieving form and profile
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    Map<String, dynamic>? profile;
    try {
      profile = await _supabaseService.fetchProfile(currentUserId);
    } catch (_) {}

    FormModel? form;
    try {
      form = await _supabaseService.fetchEventForm(
        widget.event.id,
        formId: ticket.formId,
        ticketId: ticket.id,
      );
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context); // Dismiss loading dialog

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TicketRegistrationDialog(
        eventId: widget.event.id,
        eventTitle: widget.event.title,
        ticket: ticket,
        form: form,
        initialProfile: profile,
        onSubmit: ({
          required String fullName,
          required String email,
          String? phone,
          String? company,
          String? jobTitle,
          Map<String, dynamic>? customAnswers,
        }) async {
          final result = await _supabaseService.registerWithTicket(
            eventId: widget.event.id,
            ticket: ticket,
            profileId: currentUserId,
            fullName: fullName,
            email: email,
            phone: phone,
            company: company,
            jobTitle: jobTitle,
            customAnswers: customAnswers,
          );

          if (!mounted) return;

          if (result.isRegistered) {
            Navigator.pop(ctx); // Close form sheet
            setState(() {
              _isJoined = true;
              _registrationStatus = 'registered';
              widget.event.isJoined = true;
              widget.event.registrationStatus = 'registered';
            });
            widget.onRegister();
            _showRegistrationSuccessDialog(ticket.name);
          } else if (result.isPending) {
            Navigator.pop(ctx); // Close form sheet
            setState(() {
              _isJoined = false;
              _registrationStatus = 'pending';
              widget.event.isJoined = false;
              widget.event.registrationStatus = 'pending';
            });
            _showApprovalPendingDialog(ticket.name);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(result.errorMessage ?? "Registration failed. Please try again.".tr()),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
      ),
    );
  }

  void _showRegistrationSuccessDialog(String ticketName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141927),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(LucideIcons.partyPopper, color: EventzoneTheme.primaryAction, size: 28),
            const SizedBox(width: 10),
            Text("Registered! 🎉".tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "You have successfully registered with the $ticketName ticket for ${widget.event.title}! Get ready to explore the attendees portal.".tr(),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Close dialog
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop(); // Close details screen
              }
              widget.onAccess(); // Navigate to attendees portal
            },
            child: Text("Access Attendees Portal".tr(), style: TextStyle(color: EventzoneTheme.primaryAction, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showApprovalPendingDialog(String ticketName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF141927),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(LucideIcons.clock, color: Color(0xFFF59E0B), size: 28),
            const SizedBox(width: 10),
            Text("Application Submitted! ⏳".tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "Your application for the $ticketName ticket at ${widget.event.title} has been submitted and is currently awaiting organizer approval.\n\nYou will receive access once approved by the event team.",
          style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text("Got It".tr(), style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchWebUrl(String url) async {
    final cleanUrl = url.trim().startsWith('http') ? url.trim() : "https://${url.trim()}";
    final uri = Uri.tryParse(cleanUrl);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  Widget _buildInfoItem(BuildContext context, IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: EventzoneTheme.primaryAction.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: EventzoneTheme.primaryAction, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label.tr(), style: const TextStyle(fontSize: 12, color: Colors.white38, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                value, 
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _sanitizeHtmlForDarkMode(String? html) {
    if (html == null || html.trim().isEmpty) return '';
    String sanitized = html;

    // 1. Remove color and bgcolor HTML attributes (e.g. <font color="#0f172a">, bgcolor="#fff")
    sanitized = sanitized.replaceAll(
      RegExp(r'''\bcolor\s*=\s*(["'][^"']*["']|[^\s>]+)''', caseSensitive: false),
      '',
    );
    sanitized = sanitized.replaceAll(
      RegExp(r'''\bbgcolor\s*=\s*(["'][^"']*["']|[^\s>]+)''', caseSensitive: false),
      '',
    );

    // 2. Remove inline CSS color & background properties inside style="..."
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'''style\s*=\s*(["'])(.*?)\1''', caseSensitive: false),
      (match) {
        final quote = match.group(1)!;
        var styleContent = match.group(2)!;
        // Strip color: ...
        styleContent = styleContent.replaceAll(
          RegExp(r'''(?:^|;)\s*color\s*:\s*[^;"]+;?''', caseSensitive: false),
          ';',
        );
        // Strip background / background-color: ...
        styleContent = styleContent.replaceAll(
          RegExp(r'''(?:^|;)\s*background(?:-color)?\s*:\s*[^;"]+;?''', caseSensitive: false),
          ';',
        );
        styleContent = styleContent.replaceAll(RegExp(r';\s*;+'), ';').trim();
        return 'style=$quote$styleContent$quote';
      },
    );

    // 3. Replace obsolete <font> tags with standard <span>
    sanitized = sanitized.replaceAll(RegExp(r'<\s*font\b', caseSensitive: false), '<span');
    sanitized = sanitized.replaceAll(RegExp(r'<\s*/\s*font\s*>', caseSensitive: false), '</span>');

    return sanitized;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: EventzoneTheme.backgroundStart,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.share2, color: Colors.white, size: 18),
            onPressed: () async {
              final shareText = "Join me at '${widget.event.title}' on Eventzone! 🚀\n\nDownload the app to register and access the attendees portal:\nhttps://eventzone.app/download?event_id=${widget.event.id}";
              
              await Clipboard.setData(ClipboardData(text: shareText));
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Share link copied to clipboard!".tr()),
                    backgroundColor: EventzoneTheme.primaryAction,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }

              try {
                await Share.share(
                  shareText,
                  subject: "Join ${widget.event.title} on Eventzone",
                );
              } catch (_) {}
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: EventzoneTheme.buildPlayfulBackground(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Image Section
              Stack(
                children: [
                  Hero(
                    tag: 'event-image-${widget.event.id}',
                    child: _buildEventImage(widget.event.imageUrl, 300),
                  ),
                  Container(
                    height: 300,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          EventzoneTheme.backgroundStart.withValues(alpha: 0.8),
                          EventzoneTheme.backgroundStart,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.event.isLive) ...[
                          const StatusPill(label: "LIVE NOW", isLive: true),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          widget.event.title,
                          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Info Column
                    GlassContainer(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildInfoItem(context, LucideIcons.calendar, "Date", _formatDate(widget.event.date)),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16.0),
                            child: Divider(color: Colors.white10, height: 1),
                          ),
                          _buildInfoItem(context, LucideIcons.mapPin, "Location", widget.event.location),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // About Section
                    Text("About Event".tr(), style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Html(
                      data: _sanitizeHtmlForDarkMode(widget.event.description),
                      onLinkTap: (url, attributes, element) {
                        if (url != null && url.isNotEmpty) {
                          try {
                            launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                          } catch (_) {}
                        }
                      },
                      style: {
                        "*": Style(
                          color: Colors.white,
                        ),
                        "body": Style(
                          fontSize: FontSize(15.0),
                          color: Colors.white,
                          lineHeight: const LineHeight(1.6),
                          margin: Margins.zero,
                          padding: HtmlPaddings.zero,
                        ),
                        "p": Style(
                          fontSize: FontSize(15.0),
                          color: Colors.white.withValues(alpha: 0.9),
                          lineHeight: const LineHeight(1.6),
                          margin: Margins.only(bottom: 12.0),
                        ),
                        "span": Style(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        "div": Style(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        "li": Style(
                          color: Colors.white.withValues(alpha: 0.9),
                          lineHeight: const LineHeight(1.5),
                        ),
                        "ul": Style(
                          color: Colors.white.withValues(alpha: 0.9),
                          margin: Margins.only(bottom: 10.0),
                        ),
                        "ol": Style(
                          color: Colors.white.withValues(alpha: 0.9),
                          margin: Margins.only(bottom: 10.0),
                        ),
                        "b": Style(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        "strong": Style(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        "h1": Style(color: Colors.white, fontWeight: FontWeight.bold),
                        "h2": Style(color: Colors.white, fontWeight: FontWeight.bold),
                        "h3": Style(color: Colors.white, fontWeight: FontWeight.bold),
                        "h4": Style(color: Colors.white, fontWeight: FontWeight.bold),
                        "a": Style(
                          color: const Color(0xFF60A5FA),
                          textDecoration: TextDecoration.underline,
                        ),
                      },
                    ),

                    // Agenda / Sessions Section (if any)
                    _buildAgendaSection(),

                    // Featured Speakers Section (if any)
                    _buildSpeakersSection(),

                    // Official Sponsors Section (if any)
                    _buildSponsorsSection(),

                    // Exhibitors Showcase Section (if any)
                    _buildExhibitorsSection(),
                    
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: _isJoined
              ? ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EventzoneTheme.primaryAction,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                    widget.onAccess();
                  },
                  child: Text(
                    "Access Attendees Portal".tr(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                )
              : _registrationStatus == 'pending'
                  ? Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                      ),
                      child: InkWell(
                        onTap: () => _showApprovalPendingDialog("Submitted"),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(LucideIcons.clock, color: Color(0xFFF59E0B), size: 20),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Pending Organizer Approval".tr(),
                                  style: const TextStyle(
                                    color: Color(0xFFF59E0B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  "Tap to view application status".tr(),
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EventzoneTheme.primaryAction,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _openTicketSelection,
                      child: Text(
                        "Select Ticket".tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                      ),
                    ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────
  //  AGENDA / SESSIONS SECTION
  // ─────────────────────────────────────────────
  Widget _buildAgendaSection() {
    if (_sessions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          children: [
            Text(
              "Schedule & Agenda".tr(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "${_sessions.length}",
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _sessions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final session = _sessions[index];
            final startTime = DateFormat('HH:mm').format(session.startTime.toLocal());
            final endTime = DateFormat('HH:mm').format(session.endTime.toLocal());
            final timeStr = "$startTime — $endTime";

            return GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: EventzoneTheme.primaryAction.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              session.resolveDayLabel(_sessions),
                              style: const TextStyle(
                                color: EventzoneTheme.primaryAction,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(LucideIcons.clock, color: EventzoneTheme.primaryAction, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: EventzoneTheme.primaryAction,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (session.track != null && session.track!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            session.track!,
                            style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                      if (session.location != null && session.location!.isNotEmpty) ...[
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(LucideIcons.mapPin, color: Colors.white38, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              session.location!,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    session.title,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  if (session.description != null && session.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      session.description!,
                      style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.3),
                    ),
                  ],
                  if (session.speakers.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: session.speakers.map((spk) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141927),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildSpeakerMiniAvatar(spk.avatarUrl, spk.name),
                              const SizedBox(width: 6),
                              Text(
                                spk.name,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  FEATURED SPEAKERS SECTION
  // ─────────────────────────────────────────────
  Widget _buildSpeakersSection() {
    if (_speakers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Featured Speakers & Keynotes".tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Learn directly from leaders steering innovations and market strategies.".tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EventSpeakersScreen(eventId: widget.event.id),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "See all".tr(),
                  style: const TextStyle(
                    color: EventzoneTheme.primaryAction,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 275,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _speakers.length,
            separatorBuilder: (_, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final speaker = _speakers[index];
              final roleText = (speaker.role != null && speaker.role!.trim().isNotEmpty)
                  ? speaker.role!.trim()
                  : "Speaker".tr();
              final hasCompany = speaker.company.trim().isNotEmpty &&
                  speaker.company.trim().toLowerCase() != 'eventzone';

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EventSpeakersScreen(eventId: widget.event.id),
                    ),
                  );
                },
                child: Container(
                  width: 205,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141B2D),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Top Section: Avatar + Name + Role + Title
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildSpeakerAvatar(speaker.avatarUrl, speaker.name, size: 78),
                          const SizedBox(height: 12),
                          Text(
                            speaker.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            roleText,
                            style: const TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (speaker.title.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              speaker.title.trim(),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.65),
                                fontSize: 11,
                                height: 1.25,
                                fontWeight: FontWeight.w400,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),

                      // Bottom Section: Divider + Company Name
                      if (hasCompany) ...[
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              height: 1,
                              width: double.infinity,
                              color: Colors.white.withValues(alpha: 0.08),
                              margin: const EdgeInsets.only(bottom: 8),
                            ),
                            Text(
                              speaker.company.trim().toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  OFFICIAL SPONSORS SECTION
  // ─────────────────────────────────────────────
  // ─────────────────────────────────────────────
  //  OFFICIAL SPONSORS SECTION (2-Column Bento Grid)
  // ─────────────────────────────────────────────
  Widget _buildSponsorsSection() {
    if (_sponsors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Official Sponsors".tr(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EventPartnersScreen(eventId: widget.event.id, type: "Sponsors"),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "See all".tr(),
                  style: const TextStyle(
                    color: EventzoneTheme.primaryAction,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
          ),
          itemCount: _sponsors.length,
          itemBuilder: (context, index) {
            final sponsor = _sponsors[index];
            final hasWebsite = sponsor.website != null && sponsor.website!.isNotEmpty;

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161C2C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (hasWebsite) {
                      _launchWebUrl(sponsor.website!);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EventPartnersScreen(eventId: widget.event.id, type: "Sponsors"),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      if (hasWebsite)
                        const Positioned(
                          top: 10,
                          right: 10,
                          child: Icon(LucideIcons.externalLink, color: Colors.white24, size: 13),
                        ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildPartnerLogo(sponsor.logo, sponsor.name, isSponsor: true, size: 68),
                              const SizedBox(height: 12),
                              Text(
                                sponsor.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────
  //  EXHIBITORS SHOWCASE SECTION (2-Column Bento Grid)
  // ─────────────────────────────────────────────
  Widget _buildExhibitorsSection() {
    if (_exhibitors.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Exhibitors Showcase".tr(),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20),
            ),
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EventPartnersScreen(eventId: widget.event.id, type: "Exhibitors"),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  "See all".tr(),
                  style: const TextStyle(
                    color: EventzoneTheme.primaryAction,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
          ),
          itemCount: _exhibitors.length,
          itemBuilder: (context, index) {
            final exhibitor = _exhibitors[index];
            final hasWebsite = exhibitor.website != null && exhibitor.website!.isNotEmpty;

            return Container(
              decoration: BoxDecoration(
                color: const Color(0xFF161C2C),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    if (hasWebsite) {
                      _launchWebUrl(exhibitor.website!);
                    } else {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EventPartnersScreen(eventId: widget.event.id, type: "Exhibitors"),
                        ),
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      if (hasWebsite)
                        const Positioned(
                          top: 10,
                          right: 10,
                          child: Icon(LucideIcons.externalLink, color: Colors.white24, size: 13),
                        ),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildPartnerLogo(exhibitor.logo, exhibitor.name, isSponsor: false, size: 68),
                              const SizedBox(height: 12),
                              Text(
                                exhibitor.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Helper avatar for speakers
  Widget _buildSpeakerAvatar(String? avatarUrl, String name, {double size = 78}) {
    final validUrl = avatarUrl?.trim() ?? '';
    final hasValidUrl = validUrl.isNotEmpty &&
        (validUrl.startsWith('http://') || validUrl.startsWith('https://')) &&
        !validUrl.contains('ui-avatars.com');

    if (hasValidUrl) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF2563EB).withValues(alpha: 0.45),
            width: 2.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2563EB).withValues(alpha: 0.18),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipOval(
          child: Image.network(
            validUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallbackSpeakerAvatar(name, size),
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Container(
                color: const Color(0xFF1E2638),
                child: Center(
                  child: SizedBox(
                    width: size * 0.3,
                    height: size * 0.3,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                          : null,
                      color: EventzoneTheme.primaryAction,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    return _buildFallbackSpeakerAvatar(name, size);
  }

  Widget _buildSpeakerMiniAvatar(String? avatarUrl, String name) {
    if (avatarUrl != null && avatarUrl.isNotEmpty && !avatarUrl.contains('ui-avatars.com')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          avatarUrl,
          width: 20,
          height: 20,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(LucideIcons.user, size: 14, color: Colors.white54),
        ),
      );
    }
    return const Icon(LucideIcons.user, size: 14, color: Colors.white54);
  }

  Widget _buildFallbackSpeakerAvatar(String name, double size) {
    final trimmed = name.trim();
    final parts = trimmed.split(RegExp(r'\s+'));
    final initials = parts.length >= 2
        ? "${parts[0][0]}${parts[1][0]}".toUpperCase()
        : (trimmed.isNotEmpty ? trimmed[0].toUpperCase() : 'S');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2563EB).withValues(alpha: 0.35),
            const Color(0xFF1D4ED8).withValues(alpha: 0.15),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF2563EB).withValues(alpha: 0.45),
          width: 2.2,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.34,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildPartnerLogo(String? logoUrl, String name, {required bool isSponsor, double size = 68}) {
    if (logoUrl != null && logoUrl.isNotEmpty) {
      Widget imageWidget;
      if (logoUrl.startsWith('data:image')) {
        final base64String = logoUrl.split(',').last;
        try {
          imageWidget = Image.memory(
            base64Decode(base64String),
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _buildFallbackPartnerLogo(isSponsor, size: size),
          );
        } catch (_) {
          imageWidget = _buildFallbackPartnerLogo(isSponsor, size: size);
        }
      } else {
        imageWidget = Image.network(
          logoUrl,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => _buildFallbackPartnerLogo(isSponsor, size: size),
        );
      }

      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: imageWidget,
        ),
      );
    }
    return _buildFallbackPartnerLogo(isSponsor, size: size);
  }

  Widget _buildFallbackPartnerLogo(bool isSponsor, {double size = 68}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isSponsor
            ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
            : EventzoneTheme.primaryAction.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: (isSponsor ? const Color(0xFFF59E0B) : EventzoneTheme.primaryAction).withValues(alpha: 0.25),
        ),
      ),
      child: Center(
        child: Icon(
          isSponsor ? LucideIcons.building : LucideIcons.store,
          color: isSponsor ? const Color(0xFFF59E0B) : EventzoneTheme.primaryAction,
          size: size * 0.42,
        ),
      ),
    );
  }

  Widget _buildEventImage(String imageUrl, double height) {
    if (imageUrl.startsWith('data:image')) {
      final base64String = imageUrl.split(',').last;
      try {
        return Image.memory(
          base64Decode(base64String),
          height: height,
          width: double.infinity,
          fit: BoxFit.cover,
        );
      } catch (e) {
        return Container(
          height: height,
          color: Colors.white10,
          child: const Icon(LucideIcons.imageOff, color: Colors.white24),
        );
      }
    }
    return Image.network(
      imageUrl,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        height: height,
        color: Colors.white10,
        child: const Icon(LucideIcons.imageOff, color: Colors.white24),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final parsed = DateTime.parse(dateStr);
      return DateFormat('MMM dd, yyyy').format(parsed);
    } catch (e) {
      return dateStr;
    }
  }
}
