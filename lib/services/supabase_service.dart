import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';
import '../models/meeting_model.dart';
import '../models/session_model.dart';
import '../models/ticket_model.dart';
import '../models/form_model.dart';
import '../models/sponsor_model.dart';
import '../models/exhibitor_model.dart';
import '../models/floor_plan_model.dart';
import '../models/connection_request_model.dart';

enum RegistrationStatus { registered, pending, failed }

class RegistrationResult {
  final RegistrationStatus status;
  final String? errorMessage;
  final String? ticketName;

  RegistrationResult({
    required this.status,
    this.errorMessage,
    this.ticketName,
  });

  bool get isSuccess => status != RegistrationStatus.failed;
  bool get isPending => status == RegistrationStatus.pending;
  bool get isRegistered => status == RegistrationStatus.registered;
}

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // 🔔 Send push notification via Supabase Edge Function 'send-notification'
  Future<void> sendPushNotification({
    required String targetUserId,
    required String title,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      if (targetUserId.trim().isEmpty) return;
      final body = <String, dynamic>{
        'target': targetUserId.trim(),
        'title': title.trim(),
        'message': message.trim(),
      };
      if (data != null && data.isNotEmpty) {
        body['data'] = data;
      }
      final res = await _supabase.functions.invoke(
        'send-notification',
        body: body,
      );
      debugPrint('Push notification dispatched to $targetUserId: ${res.data}');
    } catch (e) {
      debugPrint('Failed to send push notification to $targetUserId: $e');
    }
  }

  // 📅 Fetch all events from the 'events' table
  Future<List<EventModel>> fetchEvents() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final currentUserEmail = _supabase.auth.currentUser?.email;
      
      final Set<String> registeredEventIds = {};
      final Set<String> pendingEventIds = {};

      try {
        final registrationsResponse = await _supabase
            .from('event_registrations')
            .select('event_id')
            .eq('profile_id', currentUserId);
        
        for (final reg in (registrationsResponse as List)) {
          if (reg['event_id'] != null) {
            registeredEventIds.add(reg['event_id'].toString());
          }
        }
      } catch (e) {
        debugPrint('event_registrations query error: $e');
      }

      if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
        try {
          final participantsRes = await _supabase
              .from('participants')
              .select('event_id, status_participation')
              .ilike('email', currentUserEmail)
              .neq('status_participation', 'archived');
          for (final part in (participantsRes as List)) {
            final eid = part['event_id']?.toString();
            if (eid != null) {
              registeredEventIds.add(eid);
            }
          }
        } catch (_) {}

        try {
          final pendingRes = await _supabase
              .from('pending_registrations')
              .select('event_id')
              .ilike('email', currentUserEmail);
          for (final pend in (pendingRes as List)) {
            final eid = pend['event_id']?.toString();
            if (eid != null && !registeredEventIds.contains(eid)) {
              pendingEventIds.add(eid);
            }
          }
        } catch (_) {}
      }

      final response = await _supabase
          .from('events')
          .select()
          .neq('status', 'suspended')
          .neq('status', 'archived')
          .order('created_at', ascending: false);
      
      final events = (response as List)
          .where((data) {
            final status = (data['status'] ?? '').toString().toLowerCase().trim();
            // Events that are suspended in admin panel or archived must NOT show in mobile app
            if (status == 'suspended' || status == 'archived' || status == 'cancelled') {
              return false;
            }
            return true;
          })
          .map((data) {
            final id = data['id'] as String;
            final isRegistered = registeredEventIds.contains(id);
            final isPending = !isRegistered && pendingEventIds.contains(id);
            final regStatus = isRegistered ? 'registered' : (isPending ? 'pending' : 'none');

            return EventModel(
              id: id,
              title: data['name'] ?? 'Untitled Event',
              date: data['start_date'] ?? data['date'] ?? 'TBA',
              location: data['location'] ?? 'Online',
              category: data['type'] ?? 'EVENT',
              imageUrl: data['banner'] ?? data['cover_url'] ?? 'https://images.unsplash.com/photo-1540575861501-7cf05a4b125a?w=800&q=80',
              description: data['description'] ?? '',
              stats: data['capacity'] != null ? '${data['capacity']} Capacity' : null,
              startDate: data['start_date'] ?? 'TBA',
              endDate: data['end_date'] ?? data['start_date'] ?? 'TBA',
              isJoined: isRegistered,
              registrationStatus: regStatus,
              isLive: data['is_live'] == true || data['status'] == 'live' || _isEventLiveNow(data['start_date'] ?? data['date'], data['end_date']),
            );
          }).toList();

      // Sort events: upcoming closest first, then past events, then TBA
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      events.sort((a, b) {
        final aDate = DateTime.tryParse(a.startDate);
        final bDate = DateTime.tryParse(b.startDate);

        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;

        final aIsPast = aDate.isBefore(today);
        final bIsPast = bDate.isBefore(today);

        if (aIsPast && !bIsPast) return 1;
        if (!aIsPast && bIsPast) return -1;

        // Both are upcoming or both are past.
        // If both are upcoming, closest first.
        // If both are past, closest first (meaning most recent first? Wait. If both are past, most recent past means largest date. We will just sort ascending for upcoming, descending for past).
        if (aIsPast && bIsPast) {
          return bDate.compareTo(aDate); // descending for past
        }
        
        return aDate.compareTo(bDate); // ascending for upcoming
      });

      return events;
    } catch (e) {
      debugPrint('Error fetching events: $e');
      return [];
    }
  }

  bool _isEventLiveNow(String? startDateStr, String? endDateStr) {
    if (startDateStr == null || startDateStr == 'TBA' || startDateStr.isEmpty) return false;
    try {
      final now = DateTime.now();
      
      // Try to parse ISO dates
      final start = DateTime.tryParse(startDateStr);
      if (start != null) {
        final today = DateTime(now.year, now.month, now.day);
        final startDate = DateTime(start.year, start.month, start.day);
        
        DateTime endDate = startDate;
        if (endDateStr != null && endDateStr.isNotEmpty) {
          final end = DateTime.tryParse(endDateStr);
          if (end != null) {
            endDate = DateTime(end.year, end.month, end.day);
          }
        }
        
        // Check if today is within the start and end dates (inclusive)
        if (today.isAfter(startDate.subtract(const Duration(days: 1))) && 
            today.isBefore(endDate.add(const Duration(days: 1)))) {
          return true;
        }
      }

      // Fallback to original string check for hardcoded legacy data
      final todayStr1 = "${_monthAbbr(now.month)} ${now.day.toString().padLeft(2, '0')}, ${now.year}";
      final todayStr2 = "${_monthAbbr(now.month)} ${now.day}, ${now.year}";
      return startDateStr.contains(todayStr1) || startDateStr.contains(todayStr2);
    } catch (_) {
      return false;
    }
  }

  String _monthAbbr(int month) {
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    return months[month - 1];
  }

  // 🔍 Check if an event is suspended or inactive
  Future<bool> isEventSuspended(String eventId) async {
    try {
      final res = await _supabase
          .from('events')
          .select('status')
          .eq('id', eventId)
          .maybeSingle();
      if (res == null) return false;
      final status = (res['status'] ?? '').toString().toLowerCase().trim();
      return status == 'suspended' || status == 'archived' || status == 'cancelled';
    } catch (e) {
      debugPrint('Error checking event suspended status: $e');
      return false;
    }
  }

  // 📝 Register for an event (legacy fallback)
  Future<bool> registerForEvent(String eventId, String profileId) async {
    try {
      if (await isEventSuspended(eventId)) {
        debugPrint('Cannot register: event is suspended or inactive');
        return false;
      }

      await _supabase.from('event_registrations').insert({
        'event_id': eventId,
        'profile_id': profileId,
      });
      return true;
    } catch (e) {
      debugPrint('Error registering: $e');
      return false;
    }
  }

  // 🎟️ Fetch available tickets for an event
  Future<List<TicketModel>> fetchTickets(String eventId) async {
    try {
      final response = await _supabase
          .from('tickets')
          .select()
          .eq('event_id', eventId)
          .neq('status', 'archived')
          .order('price', ascending: true);
      
      final list = (response as List)
          .map((data) => TicketModel.fromJson(Map<String, dynamic>.from(data)))
          .where((t) => t.isActive && t.status != 'archived')
          .toList();
      return list;
    } catch (e) {
      debugPrint('Error fetching tickets: $e');
      return [];
    }
  }

  // 📋 Fetch registration form for an event or ticket
  Future<FormModel?> fetchEventForm(String eventId, {String? formId, String? ticketId}) async {
    try {
      if (formId != null && formId.isNotEmpty) {
        final res = await _supabase
            .from('forms')
            .select()
            .eq('id', formId)
            .maybeSingle();
        if (res != null) {
          return FormModel.fromJson(Map<String, dynamic>.from(res));
        }
      }

      final response = await _supabase
          .from('forms')
          .select()
          .eq('event_id', eventId)
          .neq('status', 'archived');
      
      final forms = (response as List)
          .map((data) => FormModel.fromJson(Map<String, dynamic>.from(data)))
          .toList();

      if (forms.isEmpty) return null;

      if (ticketId != null) {
        final matching = forms.firstWhere(
          (f) => f.ticketId == ticketId,
          orElse: () => forms.firstWhere(
            (f) => f.ticketId == 'all' || f.ticketId == null,
            orElse: () => forms.first,
          ),
        );
        return matching;
      }

      return forms.first;
    } catch (e) {
      debugPrint('Error fetching event form: $e');
      return null;
    }
  }

  // Helper: Extract company name from form submissions answers or custom fields
  String _extractCompanyFromMap(Map<dynamic, dynamic>? answers) {
    if (answers == null || answers.isEmpty) return '';
    final direct = answers['company'] ??
        answers['f_company'] ??
        answers['organization'] ??
        answers['f_organization'] ??
        answers['preset_company'] ??
        answers['org'] ??
        answers['org_name'] ??
        answers['company_name'] ??
        answers['companyName'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    for (final entry in answers.entries) {
      final k = entry.key.toString().toLowerCase();
      final v = entry.value;
      if (v is String && v.trim().isNotEmpty) {
        if (k.contains('company') || k.contains('societe') || k.contains('entreprise') || k.contains('org')) {
          return v.trim();
        }
      }
    }
    return '';
  }

  // Helper: Extract job title from form submissions answers or custom fields
  String _extractJobTitleFromMap(Map<dynamic, dynamic>? answers) {
    if (answers == null || answers.isEmpty) return '';
    final direct = answers['jobTitle'] ??
        answers['job_title'] ??
        answers['f_job_title'] ??
        answers['headline'] ??
        answers['function'] ??
        answers['profession'] ??
        answers['title'] ??
        answers['poste'] ??
        answers['role'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }
    for (final entry in answers.entries) {
      final k = entry.key.toString().toLowerCase();
      final v = entry.value;
      if (v is String && v.trim().isNotEmpty) {
        if (k.contains('job') ||
            k.contains('title') ||
            k.contains('function') ||
            k.contains('profession') ||
            k.contains('poste') ||
            k.contains('role') ||
            k.contains('fonction')) {
          return v.trim();
        }
      }
    }
    return '';
  }

  // Helper: Build a comprehensive lookup table of participants and their form submission answers
  Future<Map<String, Map<String, dynamic>>> _fetchParticipantLookup(String eventId) async {
    final Map<String, Map<String, dynamic>> participantLookup = {};
    try {
      final participantsFuture = _supabase
          .from('participants')
          .select('id, first_name, last_name, email, phone, ticket_type, is_speaker, image, custom_fields, status_participation')
          .eq('event_id', eventId);

      final formSubmissionsFuture = _supabase
          .from('form_submissions')
          .select('id, respondent_email, answers')
          .eq('event_id', eventId);

      final results = await Future.wait([
        participantsFuture.catchError((_) => []),
        formSubmissionsFuture.catchError((_) => []),
      ]);

      final participantsList = results[0] as List? ?? [];
      final formSubsList = results[1] as List? ?? [];

      for (final p in participantsList) {
        if (p is! Map) continue;
        final pMap = Map<String, dynamic>.from(p);
        if (pMap['status_participation']?.toString().toLowerCase() == 'archived') continue;
        final pId = pMap['id']?.toString() ?? '';
        final firstName = pMap['first_name']?.toString() ?? '';
        final lastName = pMap['last_name']?.toString() ?? '';
        final fullName = "$firstName $lastName".trim();
        final email = (pMap['email']?.toString() ?? '').toLowerCase().trim();

        // Match form submission for this participant by ID or respondent_email
        Map<dynamic, dynamic>? subAnswers;
        for (final sub in formSubsList) {
          if (sub is! Map) continue;
          final sId = sub['id']?.toString();
          final sEmail = (sub['respondent_email']?.toString() ?? '').toLowerCase().trim();
          if ((pId.isNotEmpty && sId == pId) || (email.isNotEmpty && sEmail == email)) {
            if (sub['answers'] is Map) {
              subAnswers = sub['answers'] as Map;
              break;
            }
          }
        }

        final customFields = pMap['custom_fields'] is Map ? pMap['custom_fields'] as Map : null;

        var comp = _extractCompanyFromMap(subAnswers);
        if (comp.isEmpty) comp = _extractCompanyFromMap(customFields);

        var job = _extractJobTitleFromMap(subAnswers);
        if (job.isEmpty) job = _extractJobTitleFromMap(customFields);
        if (job.isEmpty && pMap['ticket_type'] != null) {
          job = pMap['ticket_type'].toString().trim();
        }

        final avatar = (pMap['image']?.toString() ??
            pMap['avatar_url']?.toString() ??
            pMap['avatar']?.toString() ??
            pMap['photo']?.toString() ??
            '').trim();

        final enriched = {
          'id': pId,
          'name': fullName,
          'email': email,
          'company': comp,
          'title': job,
          'avatar': avatar,
          'is_speaker': pMap['is_speaker'] == true ||
              (pMap['ticket_type']?.toString().toLowerCase().contains('speaker') ?? false),
        };

        if (fullName.isNotEmpty) {
          participantLookup['name:${fullName.toLowerCase()}'] = enriched;
        }
        if (email.isNotEmpty) {
          participantLookup['email:$email'] = enriched;
        }
        if (pId.isNotEmpty) {
          participantLookup['id:$pId'] = enriched;
        }
      }
    } catch (e) {
      debugPrint('Error building participant lookup: $e');
    }
    return participantLookup;
  }

  Map<String, dynamic>? _matchSpeaker(SessionSpeaker spk, Map<String, Map<String, dynamic>> participantLookup) {
    if (spk.id != null && participantLookup.containsKey('id:${spk.id}')) {
      return participantLookup['id:${spk.id}'];
    }
    if (spk.email != null && spk.email!.trim().isNotEmpty && participantLookup.containsKey('email:${spk.email!.trim().toLowerCase()}')) {
      return participantLookup['email:${spk.email!.trim().toLowerCase()}'];
    }
    final nameKey = 'name:${spk.name.trim().toLowerCase()}';
    if (participantLookup.containsKey(nameKey)) {
      return participantLookup[nameKey];
    }
    return null;
  }

  // ⏱️ Fetch conference agenda / sessions
  Future<List<SessionModel>> fetchEventSessions(String eventId) async {
    try {
      final response = await _supabase
          .from('sessions')
          .select()
          .eq('event_id', eventId)
          .order('start_time', ascending: true);
      
      final sessions = (response as List)
          .map((data) => SessionModel.fromJson(Map<String, dynamic>.from(data)))
          .toList();

      // If any session speaker is missing company or title, attempt enrichment
      final hasIncompleteSpeakers = sessions.any((s) => s.speakers.any((spk) => spk.company.isEmpty || spk.title.isEmpty));
      if (hasIncompleteSpeakers) {
        try {
          final pLookup = await _fetchParticipantLookup(eventId);
          if (pLookup.isNotEmpty) {
            return sessions.map((sess) {
              final enrichedSpeakers = sess.speakers.map((spk) {
                if (spk.company.isNotEmpty && spk.title.isNotEmpty && spk.avatarUrl.isNotEmpty && !spk.avatarUrl.contains('ui-avatars.com')) return spk;
                final match = _matchSpeaker(spk, pLookup);
                if (match != null) {
                  final matchAvatar = match['avatar']?.toString().trim() ?? '';
                  final hasRealSpk = spk.avatarUrl.isNotEmpty && !spk.avatarUrl.contains('ui-avatars.com');
                  final hasRealMatch = matchAvatar.isNotEmpty && !matchAvatar.contains('ui-avatars.com');
                  final bestAvatar = hasRealSpk
                      ? spk.avatarUrl
                      : (hasRealMatch ? matchAvatar : (spk.avatarUrl.isNotEmpty ? spk.avatarUrl : matchAvatar));

                  return spk.copyWith(
                    company: spk.company.isNotEmpty ? spk.company : (match['company']?.toString() ?? ''),
                    title: spk.title.isNotEmpty ? spk.title : (match['title']?.toString() ?? ''),
                    avatarUrl: bestAvatar,
                  );
                }
                return spk;
              }).toList();
              return SessionModel(
                id: sess.id,
                eventId: sess.eventId,
                title: sess.title,
                description: sess.description,
                speakerId: sess.speakerId,
                startTime: sess.startTime,
                endTime: sess.endTime,
                location: sess.location,
                track: sess.track,
                date: sess.date,
                speakers: enrichedSpeakers,
                logos: sess.logos,
              );
            }).toList();
          }
        } catch (_) {}
      }

      return sessions;
    } catch (e) {
      debugPrint('Error fetching event sessions: $e');
      return [];
    }
  }

  // 🎙️ Fetch unified event speakers (merging sessions, participants, form submissions, and moderators)
  Future<List<SessionSpeaker>> fetchEventSpeakers(String eventId) async {
    try {
      final futures = await Future.wait([
        fetchEventSessions(eventId),
        _fetchParticipantLookup(eventId),
      ]);

      final sessions = futures[0] as List<SessionModel>;
      final participantLookup = futures[1] as Map<String, Map<String, dynamic>>;

      final Map<String, SessionSpeaker> speakersMap = {};

      // 1. Process speakers from sessions
      for (final sess in sessions) {
        for (final spk in sess.speakers) {
          if (spk.name.trim().isEmpty) continue;

          final nameKey = 'name:${spk.name.trim().toLowerCase()}';
          final emailKey = spk.email != null && spk.email!.trim().isNotEmpty
              ? 'email:${spk.email!.trim().toLowerCase()}'
              : '';

          final uniqueKey = emailKey.isNotEmpty ? emailKey : nameKey;
          if (!speakersMap.containsKey(uniqueKey)) {
            speakersMap[uniqueKey] = spk;
          } else {
            final existing = speakersMap[uniqueKey]!;
            final hasRealExisting = existing.avatarUrl.isNotEmpty && !existing.avatarUrl.contains('ui-avatars.com');
            final hasRealNew = spk.avatarUrl.isNotEmpty && !spk.avatarUrl.contains('ui-avatars.com');
            final bestAvatar = hasRealExisting
                ? existing.avatarUrl
                : (hasRealNew ? spk.avatarUrl : (existing.avatarUrl.isNotEmpty ? existing.avatarUrl : spk.avatarUrl));

            final bestRole = (existing.role != null && existing.role!.isNotEmpty && existing.role != 'Speaker')
                ? existing.role
                : ((spk.role != null && spk.role!.isNotEmpty) ? spk.role : existing.role);

            speakersMap[uniqueKey] = existing.copyWith(
              company: existing.company.isNotEmpty ? existing.company : spk.company,
              title: existing.title.isNotEmpty ? existing.title : spk.title,
              avatarUrl: bestAvatar,
              role: bestRole,
              bio: (existing.bio != null && existing.bio!.isNotEmpty) ? existing.bio : spk.bio,
            );
          }
        }
      }

      // 2. Add marked speakers from participants (even if not yet in a session)
      for (final p in participantLookup.values) {
        if (p['is_speaker'] == true) {
          final pName = p['name']?.toString() ?? '';
          final pEmail = p['email']?.toString() ?? '';
          if (pName.trim().isEmpty) continue;

          final nameKey = 'name:${pName.trim().toLowerCase()}';
          final emailKey = pEmail.isNotEmpty ? 'email:${pEmail.toLowerCase()}' : '';
          final uniqueKey = emailKey.isNotEmpty ? emailKey : nameKey;
          final pAvatar = (p['avatar']?.toString() ?? '').trim();

          if (!speakersMap.containsKey(uniqueKey)) {
            speakersMap[uniqueKey] = SessionSpeaker(
              id: p['id']?.toString(),
              name: pName,
              title: p['title']?.toString() ?? '',
              company: p['company']?.toString() ?? '',
              avatarUrl: pAvatar,
              email: pEmail.isNotEmpty ? pEmail : null,
              role: 'Speaker',
            );
          } else {
            final existing = speakersMap[uniqueKey]!;
            final hasRealExisting = existing.avatarUrl.isNotEmpty && !existing.avatarUrl.contains('ui-avatars.com');
            final hasRealP = pAvatar.isNotEmpty && !pAvatar.contains('ui-avatars.com');
            final bestAvatar = hasRealExisting
                ? existing.avatarUrl
                : (hasRealP ? pAvatar : (existing.avatarUrl.isNotEmpty ? existing.avatarUrl : pAvatar));

            speakersMap[uniqueKey] = existing.copyWith(
              company: existing.company.isNotEmpty ? existing.company : (p['company']?.toString() ?? ''),
              title: existing.title.isNotEmpty ? existing.title : (p['title']?.toString() ?? ''),
              avatarUrl: bestAvatar,
              role: (existing.role != null && existing.role!.isNotEmpty) ? existing.role : 'Speaker',
            );
          }
        }
      }

      return speakersMap.values.toList();
    } catch (e) {
      debugPrint('Error fetching event speakers: $e');
      return [];
    }
  }

  // 🤝 Fetch event sponsors
  Future<List<SponsorModel>> fetchEventSponsors(String eventId) async {
    try {
      final response = await _supabase
          .from('sponsors')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: true);
      
      final list = (response as List);
      return list
          .where((data) => (data['status']?.toString().toLowerCase() != 'archived'))
          .map((data) => SponsorModel.fromJson(Map<String, dynamic>.from(data)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching event sponsors: $e');
      return [];
    }
  }

  // 🏢 Fetch event exhibitors
  Future<List<ExhibitorModel>> fetchEventExhibitors(String eventId) async {
    try {
      final response = await _supabase
          .from('exhibitors')
          .select()
          .eq('event_id', eventId)
          .order('created_at', ascending: true);
      
      final list = (response as List);
      return list
          .where((data) => (data['status']?.toString().toLowerCase() != 'archived'))
          .map((data) => ExhibitorModel.fromJson(Map<String, dynamic>.from(data)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching event exhibitors: $e');
      return [];
    }
  }

  // 🗺️ Fetch floor plans for an event
  Future<List<FloorPlanModel>> fetchEventFloorPlans(String eventId) async {
    try {
      final response = await _supabase
          .from('floor_plans')
          .select()
          .eq('event_id', eventId)
          .neq('status', 'archived')
          .order('created_at', ascending: true);

      return (response as List)
          .map((data) => FloorPlanModel.fromJson(Map<String, dynamic>.from(data)))
          .toList();
    } catch (e) {
      debugPrint('Error fetching event floor plans: $e');
      return [];
    }
  }

  // 🔍 Check event registration status for current user ('registered', 'pending', 'none')
  Future<String> checkEventRegistrationStatus(String eventId, String profileId, String? email) async {
    try {
      // 1. Direct registration table check
      final regRes = await _supabase
          .from('event_registrations')
          .select('id')
          .eq('event_id', eventId)
          .eq('profile_id', profileId)
          .maybeSingle();
      if (regRes != null) return 'registered';

      if (email != null && email.isNotEmpty) {
        final cleanEmail = email.trim().toLowerCase();

        // 2. Participants check
        final partRes = await _supabase
            .from('participants')
            .select('id, status_participation')
            .eq('event_id', eventId)
            .ilike('email', cleanEmail)
            .neq('status_participation', 'archived')
            .maybeSingle();
        if (partRes != null) return 'registered';

        // 3. Pending registrations check
        final pendRes = await _supabase
            .from('pending_registrations')
            .select('id')
            .eq('event_id', eventId)
            .ilike('email', cleanEmail)
            .maybeSingle();
        if (pendRes != null) return 'pending';
      }

      return 'none';
    } catch (e) {
      debugPrint('Error checking registration status: $e');
      return 'none';
    }
  }

  // 🎟️ Register with ticket tier (Instant or Approval mode)
  Future<RegistrationResult> registerWithTicket({
    required String eventId,
    required TicketModel ticket,
    required String profileId,
    required String fullName,
    required String email,
    String? phone,
    String? company,
    String? jobTitle,
    Map<String, dynamic>? customAnswers,
  }) async {
    try {
      if (await isEventSuspended(eventId)) {
        return RegistrationResult(
          status: RegistrationStatus.failed,
          errorMessage: 'Cannot register: Event is inactive or suspended.',
        );
      }

      final cleanEmail = email.trim().toLowerCase();
      final cleanPhone = phone?.trim() ?? '';
      final cleanName = fullName.trim();
      final nameParts = cleanName.split(' ');
      final firstName = nameParts.first;
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : 'Attendee';

      final existingStatus = await checkEventRegistrationStatus(eventId, profileId, cleanEmail);
      if (existingStatus == 'registered') {
        return RegistrationResult(
          status: RegistrationStatus.registered,
          errorMessage: 'You are already registered for this event.',
          ticketName: ticket.name,
        );
      } else if (existingStatus == 'pending') {
        return RegistrationResult(
          status: RegistrationStatus.pending,
          errorMessage: 'Your registration application is already pending organizer review.',
          ticketName: ticket.name,
        );
      }

      final dateStr = DateTime.now().toIso8601String().split('T').first;

      // ── IF APPROVAL REQUIRED ──
      if (ticket.requiresApproval) {
        final notePayload = jsonEncode({
          'ticketType': ticket.name,
          'note': 'Applied for ${ticket.name} (Pending Approval)',
          'company': company ?? '',
          'jobTitle': jobTitle ?? '',
          'phone': cleanPhone,
          'answers': customAnswers ?? {},
        });

        await _supabase.from('pending_registrations').insert({
          'event_id': eventId,
          'name': cleanName,
          'email': cleanEmail,
          'note': notePayload,
          'date': dateStr,
        });

        if (customAnswers != null && customAnswers.isNotEmpty) {
          try {
            await _supabase.from('form_submissions').insert({
              'event_id': eventId,
              'respondent_name': cleanName,
              'respondent_email': cleanEmail,
              'ticket_tier': ticket.name,
              'answers': customAnswers,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }

        return RegistrationResult(
          status: RegistrationStatus.pending,
          ticketName: ticket.name,
        );
      }

      // ── IF DIRECT ACCEPTANCE ──
      try {
        await _supabase.from('participants').insert({
          'event_id': eventId,
          'first_name': firstName,
          'last_name': lastName,
          'email': cleanEmail,
          'phone': cleanPhone,
          'ticket_type': ticket.name,
          'status_participation': 'registered',
          'registered_at': DateTime.now().toIso8601String(),
          'custom_fields': customAnswers ?? {},
        });
      } catch (e) {
        debugPrint('Participant insert note: $e');
      }

      await _supabase.from('event_registrations').insert({
        'event_id': eventId,
        'profile_id': profileId,
      });

      if (customAnswers != null && customAnswers.isNotEmpty) {
        try {
          await _supabase.from('form_submissions').insert({
            'event_id': eventId,
            'respondent_name': cleanName,
            'respondent_email': cleanEmail,
            'ticket_tier': ticket.name,
            'answers': customAnswers,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }

      return RegistrationResult(
        status: RegistrationStatus.registered,
        ticketName: ticket.name,
      );
    } catch (e) {
      debugPrint('Error registering with ticket: $e');
      return RegistrationResult(
        status: RegistrationStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  // 🤝 Connect with another attendee via QR
  Future<void> connectWithUser(String currentUserId, String targetUserId) async {
    try {
      await _supabase.from('connections').upsert({
        'user_id': currentUserId,
        'connected_user_id': targetUserId,
        'status': 'connected',
      });
    } catch (e) {
      debugPrint('Error connecting: $e');
    }
  }

  // 👤 Fetch a user profile
  Future<Map<String, dynamic>?> fetchProfile(String profileId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', profileId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      rethrow; // Rethrow to let providers handle the error state
    }
  }

  // 👤 Update a user profile
  Future<String?> updateProfile(
    String profileId, {
    required String fullName,
    required String jobTitle,
    required String companyName,
    String? avatarUrl,
    String? phone,
    String? bio,
    String? whatImLookingFor,
    List<String>? industries,
    List<String>? interests,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // Build metadata including top-level socials shortcuts
      final Map<String, dynamic> finalMetadata = Map<String, dynamic>.from(metadata ?? {});

      if (finalMetadata['socials'] != null) {
        final socials = finalMetadata['socials'] as List;
        for (var item in socials) {
          if (item is Map<String, dynamic> || item is Map) {
            final platform = (item['platform'] as String?)?.toLowerCase().replaceAll(' ', '_');
            final value = (item['value'] as String?)?.trim() ?? '';
            if (platform != null && value.isNotEmpty) {
              // Populate metadata shortcuts for quick access
              if (platform == 'email') {
                finalMetadata['email'] = value;
              } else if (platform == 'phone' || platform == 'phone_number') {
                finalMetadata['phone'] = value;
              } else if (platform == 'website' || platform == 'company_website') {
                finalMetadata['website'] = value;
              }
            }
          }
        }
      }

      final updates = <String, dynamic>{
        'full_name': fullName,
        'job_title': jobTitle,
        'company_name': companyName,
        'avatar_url': avatarUrl,
        'phone': phone,
        'metadata': finalMetadata,
      };

      if (bio != null) updates['bio'] = bio;
      if (whatImLookingFor != null) updates['what_im_looking_for'] = whatImLookingFor;
      if (industries != null) updates['industries'] = industries;
      if (interests != null) updates['interests'] = interests;

      await _supabase.from('profiles').update(updates).eq('id', profileId);

      return null;
    } on PostgrestException catch (e) {
      debugPrint('Profile save error: ${e.message} | code: ${e.code}');
      return 'Failed to save profile. Please try again.';
    } catch (e) {
      debugPrint('Generic profile save error: $e');
      return 'Failed to save profile. Please try again.';
    }
  }

  // 🤝 Fetch connections/leads (active contacts only)
  Future<List<Map<String, dynamic>>> fetchConnections(String userId) async {
    try {
      final response = await _supabase
          .from('connections')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(response);
      return list.where((item) => item['status'] != 'pending').toList();
    } catch (e) {
      debugPrint('Error fetching connections: $e');
      return [];
    }
  }

  // 🔥 Calculate daily connection streak
  Future<int> calculateDailyStreak(String userId) async {
    try {
      final response = await _supabase
          .from('connections')
          .select('created_at, status')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final List rawData = response as List;
      final data = rawData.where((item) => item['status'] != 'pending').toList();
      if (data.isEmpty) return 0;

      // Extract unique dates (ignoring time)
      final Set<String> uniqueDatesStr = {};
      for (var row in data) {
        if (row['created_at'] != null) {
          final date = DateTime.parse(row['created_at']).toLocal();
          uniqueDatesStr.add("${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}");
        }
      }

      if (uniqueDatesStr.isEmpty) return 0;

      final List<DateTime> sortedDates = uniqueDatesStr.map((e) => DateTime.parse(e)).toList();
      sortedDates.sort((a, b) => b.compareTo(a));

      final today = DateTime.now();
      final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
      final todayDate = DateTime.parse(todayStr);

      final yesterdayDate = todayDate.subtract(Duration(days: 1));

      // If the most recent date is not today or yesterday, the streak is 0.
      if (sortedDates.first.isBefore(yesterdayDate)) {
        return 0;
      }

      int streak = 0;
      DateTime currentDateToCheck = sortedDates.first == todayDate ? todayDate : yesterdayDate;

      for (var date in sortedDates) {
        if (date.isAtSameMomentAs(currentDateToCheck)) {
          streak++;
          currentDateToCheck = currentDateToCheck.subtract(Duration(days: 1));
        } else if (date.isBefore(currentDateToCheck)) {
          // A gap in the streak was found
          break;
        }
      }

      return streak;
    } catch (e) {
      debugPrint('Error calculating streak: $e');
      return 0;
    }
  }

  // 💳 Check if the user has an active subscription
  Future<bool> hasActiveSubscription(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('subscription_end_date, created_at')
          .eq('id', userId)
          .single();
      
      final now = DateTime.now();

      // Check Subscription
      final endDateStr = response['subscription_end_date'] as String?;
      if (endDateStr != null) {
        final endDate = DateTime.parse(endDateStr);
        if (endDate.isAfter(now)) return true;
      }

      // Check Trial (15 days from created_at)
      final createdAtStr = response['created_at'] as String?;
      if (createdAtStr != null) {
        final createdAt = DateTime.parse(createdAtStr);
        final trialEndDate = createdAt.add(const Duration(days: 15));
        if (trialEndDate.isAfter(now)) return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error checking subscription: $e');
      return false;
    }
  }

  // 💾 Save connection/lead
  Future<bool> saveConnection(Map<String, dynamic> connectionData) async {
    try {
      await _supabase.from('connections').insert(connectionData);
      return true;
    } catch (e) {
      debugPrint('Error saving connection: $e');
      return false;
    }
  }

  // ❌ Delete connection/lead
  Future<bool> deleteConnection(String connectionId) async {
    try {
      await _supabase.from('connections').delete().eq('id', connectionId);
      return true;
    } catch (e) {
      debugPrint('Error deleting connection: $e');
      return false;
    }
  }

  // 🤝 Connect directly (bypasses requests / accepts mutual connection)
  Future<bool> connectDirectly(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null || currentUserId == targetUserId) return false;

      // Check active subscription first!
      final hasSub = await hasActiveSubscription(currentUserId);
      if (!hasSub) {
        return false;
      }

      // 1. Fetch sender profile
      final senderProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', currentUserId)
          .maybeSingle();

      // 2. Fetch receiver profile
      final receiverProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', targetUserId)
          .maybeSingle();

      if (senderProfile != null && receiverProfile != null) {
        final senderMeta = senderProfile['metadata'] as Map<String, dynamic>? ?? {};
        final receiverMeta = receiverProfile['metadata'] as Map<String, dynamic>? ?? {};

        // Upsert/Insert receiver into sender's connections
        final existingSenderConn = await _supabase
            .from('connections')
            .select('id')
            .eq('user_id', currentUserId)
            .or('connected_user_id.eq.$targetUserId,linked_profile_id.eq.$targetUserId')
            .maybeSingle();

        if (existingSenderConn != null) {
          await _supabase.from('connections').update({
            'name': receiverProfile['full_name'] ?? 'Attendee',
            'title': receiverProfile['job_title'] ?? '',
            'avatar_url': receiverProfile['avatar_url'] ?? '',
            'company': receiverProfile['company_name'] ?? '',
            'email': receiverProfile['email'] ?? receiverMeta['email'] ?? '',
            'phone': receiverProfile['phone'] ?? receiverMeta['phone'] ?? '',
            'website': receiverProfile['website'] ?? receiverMeta['website'] ?? '',
            'address': receiverProfile['address'] ?? receiverMeta['address'] ?? '',
            'tags': receiverProfile['interests'] ?? [],
            'source': 'B2B Connection',
            'status': 'connected',
            'pipeline_stage': 'lead',
            'is_new': true,
          }).eq('id', existingSenderConn['id']);
        } else {
          await _supabase.from('connections').insert({
            'user_id': currentUserId,
            'connected_user_id': targetUserId,
            'linked_profile_id': targetUserId,
            'name': receiverProfile['full_name'] ?? 'Attendee',
            'title': receiverProfile['job_title'] ?? '',
            'avatar_url': receiverProfile['avatar_url'] ?? '',
            'company': receiverProfile['company_name'] ?? '',
            'email': receiverProfile['email'] ?? receiverMeta['email'] ?? '',
            'phone': receiverProfile['phone'] ?? receiverMeta['phone'] ?? '',
            'website': receiverProfile['website'] ?? receiverMeta['website'] ?? '',
            'address': receiverProfile['address'] ?? receiverMeta['address'] ?? '',
            'tags': receiverProfile['interests'] ?? [],
            'source': 'B2B Connection',
            'status': 'connected',
            'pipeline_stage': 'lead',
            'is_new': true,
          });
        }

        // Upsert/Insert sender into receiver's connections
        final existingReceiverConn = await _supabase
            .from('connections')
            .select('id')
            .eq('user_id', targetUserId)
            .or('connected_user_id.eq.$currentUserId,linked_profile_id.eq.$currentUserId')
            .maybeSingle();

        if (existingReceiverConn != null) {
          await _supabase.from('connections').update({
            'name': senderProfile['full_name'] ?? 'Attendee',
            'title': senderProfile['job_title'] ?? '',
            'avatar_url': senderProfile['avatar_url'] ?? '',
            'company': senderProfile['company_name'] ?? '',
            'email': senderProfile['email'] ?? senderMeta['email'] ?? '',
            'phone': senderProfile['phone'] ?? senderMeta['phone'] ?? '',
            'website': senderProfile['website'] ?? senderMeta['website'] ?? '',
            'address': senderProfile['address'] ?? senderMeta['address'] ?? '',
            'tags': senderProfile['interests'] ?? [],
            'source': 'B2B Connection',
            'status': 'connected',
            'pipeline_stage': 'lead',
            'is_new': true,
          }).eq('id', existingReceiverConn['id']);
        } else {
          await _supabase.from('connections').insert({
            'user_id': targetUserId,
            'connected_user_id': currentUserId,
            'linked_profile_id': currentUserId,
            'name': senderProfile['full_name'] ?? 'Attendee',
            'title': senderProfile['job_title'] ?? '',
            'avatar_url': senderProfile['avatar_url'] ?? '',
            'company': senderProfile['company_name'] ?? '',
            'email': senderProfile['email'] ?? senderMeta['email'] ?? '',
            'phone': senderProfile['phone'] ?? senderMeta['phone'] ?? '',
            'website': senderProfile['website'] ?? senderMeta['website'] ?? '',
            'address': senderProfile['address'] ?? senderMeta['address'] ?? '',
            'tags': senderProfile['interests'] ?? [],
            'source': 'B2B Connection',
            'status': 'connected',
            'pipeline_stage': 'lead',
            'is_new': true,
          });
        }
      }
      return true;
    } catch (e) {
      debugPrint('Error connecting directly: $e');
      return false;
    }
  }

  // 🤝 Send connection request
  Future<bool> sendConnectionRequest(
    String targetUserId, {
    String? message,
    String? eventId,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null || currentUserId == targetUserId) return false;

      // Check current connection status
      final currentStatus = await fetchConnectionStatus(targetUserId);
      if (currentStatus == 'accepted') {
        return true; // Already connected
      }

      // If target user already sent a pending request to us, auto-accept it!
      if (currentStatus == 'pending_received') {
        final incoming = await _supabase
            .from('connections')
            .select('id')
            .eq('user_id', targetUserId)
            .or('connected_user_id.eq.$currentUserId,linked_profile_id.eq.$currentUserId')
            .eq('status', 'pending')
            .maybeSingle();

        if (incoming != null) {
          return await acceptConnectionRequest(incoming['id'] as String, targetUserId);
        }
      }

      // If already sent pending request, return true
      if (currentStatus == 'pending_sent') {
        return true;
      }

      // Fetch sender and receiver profiles
      final senderProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', currentUserId)
          .maybeSingle();

      final receiverProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', targetUserId)
          .maybeSingle();

      final senderMeta = senderProfile != null ? (senderProfile['metadata'] as Map<String, dynamic>? ?? {}) : {};
      final receiverMeta = receiverProfile != null ? (receiverProfile['metadata'] as Map<String, dynamic>? ?? {}) : {};

      final now = DateTime.now().toUtc().toIso8601String();
      final notesMap = {
        'event_id': eventId,
        'sender_id': currentUserId,
        'sender_email': senderProfile?['email'] ?? senderMeta['email'] ?? '',
        'sender_name': senderProfile?['full_name'] ?? 'Attendee',
        'sender_avatar': senderProfile?['avatar_url'] ?? '',
        'sender_company': senderProfile?['company_name'] ?? '',
        'sender_title': senderProfile?['job_title'] ?? '',
        'recipient_id': targetUserId,
        'recipient_email': receiverProfile?['email'] ?? receiverMeta['email'] ?? '',
        'recipient_name': receiverProfile?['full_name'] ?? 'Attendee',
        'recipient_avatar': receiverProfile?['avatar_url'] ?? '',
        'recipient_company': receiverProfile?['company_name'] ?? '',
        'recipient_title': receiverProfile?['job_title'] ?? '',
        'status': 'pending',
        'message': message ?? '',
        'created_at': now,
        'updated_at': now,
      };

      // Check if an existing row already exists from current user
      final existingSent = await _supabase
          .from('connections')
          .select('id')
          .eq('user_id', currentUserId)
          .or('connected_user_id.eq.$targetUserId,linked_profile_id.eq.$targetUserId')
          .maybeSingle();

      if (existingSent != null) {
        await _supabase.from('connections').update({
          'connected_user_id': targetUserId,
          'linked_profile_id': targetUserId,
          'event_id': eventId,
          'name': receiverProfile?['full_name'] ?? 'Attendee',
          'title': receiverProfile?['job_title'] ?? '',
          'avatar_url': receiverProfile?['avatar_url'] ?? '',
          'company': receiverProfile?['company_name'] ?? '',
          'email': receiverProfile?['email'] ?? receiverMeta['email'] ?? '',
          'phone': receiverProfile?['phone'] ?? receiverMeta['phone'] ?? '',
          'website': receiverProfile?['website'] ?? receiverMeta['website'] ?? '',
          'address': receiverProfile?['address'] ?? receiverMeta['address'] ?? '',
          'tags': receiverProfile?['interests'] ?? [],
          'source': 'In-App Request',
          'is_new': true,
          'status': 'pending',
          'notes': jsonEncode(notesMap),
        }).eq('id', existingSent['id']);
      } else {
        await _supabase.from('connections').insert({
          'user_id': currentUserId,
          'connected_user_id': targetUserId,
          'linked_profile_id': targetUserId,
          'event_id': eventId,
          'name': receiverProfile?['full_name'] ?? 'Attendee',
          'title': receiverProfile?['job_title'] ?? '',
          'avatar_url': receiverProfile?['avatar_url'] ?? '',
          'company': receiverProfile?['company_name'] ?? '',
          'email': receiverProfile?['email'] ?? receiverMeta['email'] ?? '',
          'phone': receiverProfile?['phone'] ?? receiverMeta['phone'] ?? '',
          'website': receiverProfile?['website'] ?? receiverMeta['website'] ?? '',
          'address': receiverProfile?['address'] ?? receiverMeta['address'] ?? '',
          'tags': receiverProfile?['interests'] ?? [],
          'source': 'In-App Request',
          'is_new': true,
          'status': 'pending',
          'notes': jsonEncode(notesMap),
        });
      }

      // Send push notification to target user
      final senderName = senderProfile?['full_name'] ?? 'Someone';
      await sendPushNotification(
        targetUserId: targetUserId,
        title: 'New Connection Request',
        message: '$senderName sent you a connection request.',
        data: {
          'type': 'connection_request',
          'sender_id': currentUserId,
          'target_id': targetUserId,
          'event_id': eventId ?? '',
        },
      );

      return true;
    } catch (e) {
      debugPrint('Error sending connection request: $e');
      return false;
    }
  }

  // 📥 Fetch incoming connection requests for current user
  Future<List<ConnectionRequestModel>> fetchIncomingConnectionRequests() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('connections')
          .select()
          .or('connected_user_id.eq.$currentUserId,linked_profile_id.eq.$currentUserId')
          .neq('user_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final rawList = List<Map<String, dynamic>>.from(response);
      if (rawList.isEmpty) return [];

      // Fetch latest profile details for senders
      final senderIds = rawList
          .map((r) => r['user_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (senderIds.isNotEmpty) {
        try {
          final profilesRes = await _supabase
              .from('profiles')
              .select()
              .inFilter('id', senderIds);
          for (var p in profilesRes) {
            profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
          }
        } catch (e) {
          debugPrint('Error fetching sender profiles: $e');
        }
      }

      return rawList.map((item) {
        final senderId = item['user_id']?.toString();
        final map = Map<String, dynamic>.from(item);
        if (senderId != null && profilesMap.containsKey(senderId)) {
          map['sender_profile'] = profilesMap[senderId];
        }
        return ConnectionRequestModel.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching incoming connection requests: $e');
      return [];
    }
  }

  // 📤 Fetch outgoing / sent connection requests from current user
  Future<List<ConnectionRequestModel>> fetchSentConnectionRequests() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];

      final response = await _supabase
          .from('connections')
          .select()
          .eq('user_id', currentUserId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final rawList = List<Map<String, dynamic>>.from(response);
      if (rawList.isEmpty) return [];

      // Fetch recipient profiles
      final recipientIds = rawList
          .map((r) => (r['connected_user_id'] ?? r['linked_profile_id'])?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profilesMap = {};
      if (recipientIds.isNotEmpty) {
        try {
          final profilesRes = await _supabase
              .from('profiles')
              .select()
              .inFilter('id', recipientIds);
          for (var p in profilesRes) {
            profilesMap[p['id'].toString()] = Map<String, dynamic>.from(p);
          }
        } catch (e) {
          debugPrint('Error fetching recipient profiles: $e');
        }
      }

      return rawList.map((item) {
        final recipientId = (item['connected_user_id'] ?? item['linked_profile_id'])?.toString();
        final map = Map<String, dynamic>.from(item);
        if (recipientId != null && profilesMap.containsKey(recipientId)) {
          map['receiver_profile'] = profilesMap[recipientId];
        }
        return ConnectionRequestModel.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('Error fetching sent connection requests: $e');
      return [];
    }
  }

  // ✅ Accept connection request and mutually add to both users' contacts lists
  Future<bool> acceptConnectionRequest(String requestId, String senderId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;

      // 1. Fetch both profiles to populate all fields accurately
      final senderProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', senderId)
          .maybeSingle();

      final currentProfile = await _supabase
          .from('profiles')
          .select()
          .eq('id', currentUserId)
          .maybeSingle();

      final senderMeta = senderProfile != null ? (senderProfile['metadata'] as Map<String, dynamic>? ?? {}) : {};
      final currentMeta = currentProfile != null ? (currentProfile['metadata'] as Map<String, dynamic>? ?? {}) : {};

      // 2. Update the original request row to 'connected' with fresh receiver details
      await _supabase.from('connections').update({
        'status': 'connected',
        'pipeline_stage': 'lead',
        'is_new': true,
        'name': currentProfile?['full_name'] ?? 'Attendee',
        'title': currentProfile?['job_title'] ?? '',
        'avatar_url': currentProfile?['avatar_url'] ?? '',
        'company': currentProfile?['company_name'] ?? '',
        'email': currentProfile?['email'] ?? currentMeta['email'] ?? '',
        'phone': currentProfile?['phone'] ?? currentMeta['phone'] ?? '',
        'website': currentProfile?['website'] ?? currentMeta['website'] ?? '',
        'address': currentProfile?['address'] ?? currentMeta['address'] ?? '',
        'tags': currentProfile?['interests'] ?? [],
        'source': 'B2B Connection',
      }).eq('id', requestId);

      // 3. Ensure reciprocal row exists for current user (currentUserId -> senderId)
      final existingReciprocal = await _supabase
          .from('connections')
          .select('id')
          .eq('user_id', currentUserId)
          .or('connected_user_id.eq.$senderId,linked_profile_id.eq.$senderId')
          .maybeSingle();

      if (existingReciprocal != null) {
        await _supabase.from('connections').update({
          'status': 'connected',
          'pipeline_stage': 'lead',
          'connected_user_id': senderId,
          'linked_profile_id': senderId,
          'name': senderProfile?['full_name'] ?? 'Attendee',
          'title': senderProfile?['job_title'] ?? '',
          'avatar_url': senderProfile?['avatar_url'] ?? '',
          'company': senderProfile?['company_name'] ?? '',
          'email': senderProfile?['email'] ?? senderMeta['email'] ?? '',
          'phone': senderProfile?['phone'] ?? senderMeta['phone'] ?? '',
          'website': senderProfile?['website'] ?? senderMeta['website'] ?? '',
          'address': senderProfile?['address'] ?? senderMeta['address'] ?? '',
          'tags': senderProfile?['interests'] ?? [],
          'source': 'B2B Connection',
          'is_new': true,
        }).eq('id', existingReciprocal['id']);
      } else {
        await _supabase.from('connections').insert({
          'user_id': currentUserId,
          'connected_user_id': senderId,
          'linked_profile_id': senderId,
          'name': senderProfile?['full_name'] ?? 'Attendee',
          'title': senderProfile?['job_title'] ?? '',
          'avatar_url': senderProfile?['avatar_url'] ?? '',
          'company': senderProfile?['company_name'] ?? '',
          'email': senderProfile?['email'] ?? senderMeta['email'] ?? '',
          'phone': senderProfile?['phone'] ?? senderMeta['phone'] ?? '',
          'website': senderProfile?['website'] ?? senderMeta['website'] ?? '',
          'address': senderProfile?['address'] ?? senderMeta['address'] ?? '',
          'tags': senderProfile?['interests'] ?? [],
          'source': 'B2B Connection',
          'status': 'connected',
          'pipeline_stage': 'lead',
          'is_new': true,
        });
      }

      // Send push notification to the sender that request was accepted
      final acceptorName = currentProfile?['full_name'] ?? 'Attendee';
      await sendPushNotification(
        targetUserId: senderId,
        title: 'Connection Request Accepted',
        message: '$acceptorName accepted your connection request.',
        data: {
          'type': 'connection_accepted',
          'user_id': currentUserId,
        },
      );

      return true;
    } catch (e) {
      debugPrint('Error accepting connection request: $e');
      return false;
    }
  }

  // ❌ Decline connection request
  Future<bool> declineConnectionRequest(String requestId) async {
    try {
      await _supabase.from('connections').delete().eq('id', requestId);
      return true;
    } catch (e) {
      debugPrint('Error declining connection request: $e');
      return false;
    }
  }

  // 🚫 Cancel sent connection request
  Future<bool> cancelSentConnectionRequest(String requestId) async {
    try {
      await _supabase.from('connections').delete().eq('id', requestId);
      return true;
    } catch (e) {
      debugPrint('Error cancelling sent connection request: $e');
      return false;
    }
  }

  // 🤝 Fetch accepted B2B connections registered for a specific event
  Future<List<Map<String, dynamic>>> fetchAcceptedConnectionsForEvent(String eventId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      
      // 1. Fetch all active connections for current user
      final connections = await _supabase
          .from('connections')
          .select('linked_profile_id, connected_user_id, status')
          .eq('user_id', currentUserId);
          
      final activeConnections = (connections as List)
          .where((c) => c['status'] != 'pending')
          .toList();

      final connectionIds = activeConnections
          .map((c) => (c['linked_profile_id'] ?? c['connected_user_id']) as String?)
          .whereType<String>()
          .toSet()
          .toList();

      if (connectionIds.isEmpty) return [];
      
      // 2. Fetch profiles registered for this event that are in the user's connections
      final registrations = await _supabase
          .from('event_registrations')
          .select('profile_id, profiles!event_registrations_profile_id_fkey(*)')
          .eq('event_id', eventId)
          .inFilter('profile_id', connectionIds);
      
      final list = <Map<String, dynamic>>[];
      for (var reg in (registrations as List)) {
        final profile = reg['profiles'];
        if (profile != null) {
          list.add(Map<String, dynamic>.from(profile));
        }
      }
      
      list.sort((a, b) => (a['full_name'] ?? '').compareTo(b['full_name'] ?? ''));
      return list;
    } catch (e) {
      debugPrint('Error fetching event connections: $e');
      return [];
    }
  }

  // 🤝 Fetch connection status between current user and target user
  // Returns: 'accepted' | 'pending_sent' | 'pending_received' | 'none'
  Future<String> fetchConnectionStatus(String targetUserId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 'none';
      if (currentUserId == targetUserId) return 'accepted'; // Self is always accepted/fully visible

      // 1. Check current user's connection row with target user
      final myConn = await _supabase
          .from('connections')
          .select('id, status')
          .eq('user_id', currentUserId)
          .or('connected_user_id.eq.$targetUserId,linked_profile_id.eq.$targetUserId')
          .maybeSingle();

      if (myConn != null) {
        final status = myConn['status'] as String?;
        if (status == 'connected' || status == 'accepted' || status == null) {
          return 'accepted';
        } else if (status == 'pending') {
          return 'pending_sent';
        }
      }

      // 2. Check reciprocal connection row (from target user to current user)
      final targetConn = await _supabase
          .from('connections')
          .select('id, status')
          .eq('user_id', targetUserId)
          .or('connected_user_id.eq.$currentUserId,linked_profile_id.eq.$currentUserId')
          .maybeSingle();

      if (targetConn != null) {
        final status = targetConn['status'] as String?;
        if (status == 'connected' || status == 'accepted' || status == null) {
          return 'accepted';
        } else if (status == 'pending') {
          return 'pending_received';
        }
      }

      return 'none';
    } catch (e) {
      debugPrint('Error fetching connection status: $e');
      return 'none';
    }
  }

  // 🎟️ Fetch upcoming and live events that a specific user is registered in and attending
  Future<List<EventModel>> fetchAttendingEventsForUser(String userId) async {
    try {
      final Set<String> registeredEventIds = {};

      // 1. Check event_registrations by profile_id
      try {
        final regRes = await _supabase
            .from('event_registrations')
            .select('event_id')
            .eq('profile_id', userId);
        for (final row in (regRes as List)) {
          if (row['event_id'] != null) {
            registeredEventIds.add(row['event_id'].toString());
          }
        }
      } catch (e) {
        debugPrint('Error fetching event_registrations for user: $e');
      }

      // 2. Also check participants by user email from profile
      try {
        final profileRes = await _supabase
            .from('profiles')
            .select('email, metadata')
            .eq('id', userId)
            .maybeSingle();

        if (profileRes != null) {
          final meta = profileRes['metadata'] as Map<String, dynamic>? ?? {};
          final email = (profileRes['email'] ?? meta['email'])?.toString().trim();
          if (email != null && email.isNotEmpty) {
            final partRes = await _supabase
                .from('participants')
                .select('event_id, status_participation')
                .ilike('email', email)
                .neq('status_participation', 'archived');
            for (final row in (partRes as List)) {
              if (row['event_id'] != null) {
                registeredEventIds.add(row['event_id'].toString());
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Error fetching participants for user: $e');
      }

      if (registeredEventIds.isEmpty) return [];

      // 3. Fetch the event records
      final eventsRes = await _supabase
          .from('events')
          .select()
          .inFilter('id', registeredEventIds.toList())
          .neq('status', 'suspended')
          .neq('status', 'archived')
          .neq('status', 'cancelled');

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Check current user's registrations to know if current user is also attending
      final currentUserId = _supabase.auth.currentUser?.id;
      final currentUserEmail = _supabase.auth.currentUser?.email;
      final Set<String> myEventIds = {};
      if (currentUserId != null) {
        try {
          final myRegs = await _supabase
              .from('event_registrations')
              .select('event_id')
              .eq('profile_id', currentUserId);
          for (var r in (myRegs as List)) {
            if (r['event_id'] != null) myEventIds.add(r['event_id'].toString());
          }
          if (currentUserEmail != null && currentUserEmail.isNotEmpty) {
            final myParts = await _supabase
                .from('participants')
                .select('event_id')
                .ilike('email', currentUserEmail)
                .neq('status_participation', 'archived');
            for (var r in (myParts as List)) {
              if (r['event_id'] != null) myEventIds.add(r['event_id'].toString());
            }
          }
        } catch (_) {}
      }

      final events = (eventsRes as List)
          .where((data) {
            final status = (data['status'] ?? '').toString().toLowerCase().trim();
            if (status == 'suspended' || status == 'archived' || status == 'cancelled') {
              return false;
            }
            return true;
          })
          .map((data) {
            final id = data['id'] as String;
            final isLive = data['is_live'] == true ||
                data['status'] == 'live' ||
                _isEventLiveNow(data['start_date'] ?? data['date'], data['end_date']);

            final isViewerAlsoAttending = myEventIds.contains(id);

            return EventModel(
              id: id,
              title: data['name'] ?? 'Untitled Event',
              date: data['start_date'] ?? data['date'] ?? 'TBA',
              location: data['location'] ?? 'Online',
              category: data['type'] ?? 'EVENT',
              imageUrl: data['banner'] ?? data['cover_url'] ?? 'https://images.unsplash.com/photo-1540575861501-7cf05a4b125a?w=800&q=80',
              description: data['description'] ?? '',
              stats: data['capacity'] != null ? '${data['capacity']} Capacity' : null,
              startDate: data['start_date'] ?? 'TBA',
              endDate: data['end_date'] ?? data['start_date'] ?? 'TBA',
              isJoined: isViewerAlsoAttending,
              registrationStatus: isViewerAlsoAttending ? 'registered' : 'none',
              isLive: isLive,
            );
          })
          .where((event) {
            if (event.isLive) return true;
            final endDate = DateTime.tryParse(event.endDate) ?? DateTime.tryParse(event.startDate);
            if (endDate == null) return true;
            final endDay = DateTime(endDate.year, endDate.month, endDate.day);
            return !endDay.isBefore(today);
          })
          .toList();

      // Sort: closest upcoming first
      events.sort((a, b) {
        final aDate = DateTime.tryParse(a.startDate);
        final bDate = DateTime.tryParse(b.startDate);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

      return events;
    } catch (e) {
      debugPrint('Error fetching attending events for user: $e');
      return [];
    }
  }

  // 👤 Fetch all profiles (for directory) excluding self
  Future<List<Map<String, dynamic>>> fetchProfiles() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final response = await _supabase
          .from('profiles')
          .select()
          .neq('id', currentUserId)
          .order('full_name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching profiles: $e');
      return [];
    }
  }

  // 👤 Fetch profiles registered for a specific event excluding self
  Future<List<Map<String, dynamic>>> fetchProfilesForEvent(String eventId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final response = await _supabase
          .from('event_registrations')
          .select('profiles(*)')
          .eq('event_id', eventId)
          .neq('profile_id', currentUserId);
      
      final list = <Map<String, dynamic>>[];
      for (var item in (response as List)) {
        if (item['profiles'] != null) {
          list.add(Map<String, dynamic>.from(item['profiles']));
        }
      }
      
      list.sort((a, b) => (a['full_name'] ?? '').compareTo(b['full_name'] ?? ''));
      return list;
    } catch (e) {
      debugPrint('Error fetching profiles for event: $e');
      return fetchProfiles(); // Fallback to all profiles
    }
  }

  // 📅 Fetch all meetings with joined profiles for a user
  Future<List<MeetingModel>> fetchMeetings(String userId, {String? eventId}) async {
    try {
      var query = _supabase
          .from('meetings')
          .select('*, organizer_profile:profiles!organizer_id(*), attendee_profile:profiles!attendee_id(*)')
          .or('organizer_id.eq.$userId,attendee_id.eq.$userId');
      
      if (eventId != null && eventId.isNotEmpty) {
        query = query.eq('event_id', eventId);
      }
      
      final response = await query
          .order('date', ascending: true)
          .order('start_time', ascending: true);
      
      return (response as List).map((json) => MeetingModel.fromJson(json, userId)).toList();
    } catch (e) {
      debugPrint('Error fetching meetings: $e');
      return [];
    }
  }

  // 📅 Stream meetings with joined profiles in real-time
  Stream<List<MeetingModel>> streamMeetings(String userId, {String? eventId}) {
    final controller = StreamController<List<MeetingModel>>();
    
    // Initial fetch
    fetchMeetings(userId, eventId: eventId).then((meetings) {
      if (!controller.isClosed) {
        controller.add(meetings);
      }
    });
    
    // Subscribe to real-time changes on meetings table
    final channel = _supabase
        .channel('public:meetings:${userId}_${eventId ?? "all"}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'meetings',
          callback: (payload) async {
            final updatedMeetings = await fetchMeetings(userId, eventId: eventId);
            if (!controller.isClosed) {
              controller.add(updatedMeetings);
            }
          },
        )
        .subscribe();
        
    controller.onCancel = () {
      channel.unsubscribe();
      controller.close();
    };
    
    return controller.stream;
  }

  // 📅 Create a new meeting request
  Future<bool> createMeeting(MeetingModel meeting) async {
    try {
      await _supabase.from('meetings').insert(meeting.toJson());

      // Fetch organizer name to notify attendee
      final currentUserId = _supabase.auth.currentUser?.id;
      final organizerId = meeting.organizerId.isNotEmpty ? meeting.organizerId : (currentUserId ?? '');

      String organizerName = 'Someone';
      if (organizerId.isNotEmpty) {
        try {
          final profile = await _supabase
              .from('profiles')
              .select('full_name')
              .eq('id', organizerId)
              .maybeSingle();
          if (profile != null && profile['full_name'] != null && profile['full_name'].toString().trim().isNotEmpty) {
            organizerName = profile['full_name'].toString().trim();
          }
        } catch (e) {
          debugPrint('Error fetching organizer profile for push: $e');
        }
      }

      final dateStr = meeting.date.isNotEmpty ? ' on ${meeting.date}' : '';
      final timeStr = meeting.startTime.isNotEmpty ? ' at ${meeting.startTime}' : '';
      final titleStr = meeting.title.isNotEmpty ? ': "${meeting.title}"' : '';

      await sendPushNotification(
        targetUserId: meeting.attendeeId,
        title: 'New Meeting Request',
        message: '$organizerName requested a meeting$titleStr$dateStr$timeStr.',
        data: {
          'type': 'meeting_request',
          'meeting_id': meeting.id,
          'organizer_id': meeting.organizerId,
          'date': meeting.date,
          'time': meeting.startTime,
        },
      );

      return true;
    } catch (e) {
      debugPrint('Error creating meeting: $e');
      return false;
    }
  }

  // 📅 Update meeting status (accepted, declined, cancelled)
  Future<bool> updateMeetingStatus(String meetingId, String status) async {
    try {
      final meetingData = await _supabase
          .from('meetings')
          .select('organizer_id, attendee_id, title')
          .eq('id', meetingId)
          .maybeSingle();

      await _supabase
          .from('meetings')
          .update({'status': status})
          .eq('id', meetingId);

      if (meetingData != null) {
        final currentUserId = _supabase.auth.currentUser?.id;
        final organizerId = meetingData['organizer_id']?.toString();
        final attendeeId = meetingData['attendee_id']?.toString();
        final title = meetingData['title']?.toString() ?? 'Meeting';

        String actorName = 'Someone';
        if (currentUserId != null) {
          try {
            final profile = await _supabase
                .from('profiles')
                .select('full_name')
                .eq('id', currentUserId)
                .maybeSingle();
            if (profile != null && profile['full_name'] != null && profile['full_name'].toString().trim().isNotEmpty) {
              actorName = profile['full_name'].toString().trim();
            }
          } catch (_) {}
        }

        if (currentUserId == attendeeId && organizerId != null) {
          if (status == 'accepted') {
            await sendPushNotification(
              targetUserId: organizerId,
              title: 'Meeting Accepted',
              message: '$actorName accepted your meeting request: "$title".',
              data: {'type': 'meeting_status', 'meeting_id': meetingId, 'status': 'accepted'},
            );
          } else if (status == 'declined') {
            await sendPushNotification(
              targetUserId: organizerId,
              title: 'Meeting Declined',
              message: '$actorName declined your meeting request: "$title".',
              data: {'type': 'meeting_status', 'meeting_id': meetingId, 'status': 'declined'},
            );
          }
        } else if (currentUserId == organizerId && attendeeId != null) {
          if (status == 'cancelled') {
            await sendPushNotification(
              targetUserId: attendeeId,
              title: 'Meeting Cancelled',
              message: '$actorName cancelled the meeting: "$title".',
              data: {'type': 'meeting_status', 'meeting_id': meetingId, 'status': 'cancelled'},
            );
          }
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error updating meeting status: $e');
      return false;
    }
  }

  // 📅 Fetch booked slots (accepted meetings) for a user on a specific date
  Future<List<Map<String, String>>> fetchBookedSlots(String userId, String date) async {
    try {
      final response = await _supabase
          .from('meetings')
          .select('start_time, end_time')
          .eq('date', date)
          .eq('status', 'accepted')
          .or('organizer_id.eq.$userId,attendee_id.eq.$userId');
      
      return (response as List).map((item) {
        return {
          'start_time': item['start_time'].toString().substring(0, 5),
          'end_time': item['end_time'].toString().substring(0, 5),
        };
      }).toList();
    } catch (e) {
      debugPrint('Error fetching booked slots: $e');
      return [];
    }
  }

  // Helper method to parse time string "HH:MM" to double
  double _parseTimeToDouble(String timeStr) {
    final parts = timeStr.split(':');
    final hour = double.parse(parts[0]);
    final minute = double.parse(parts[1]);
    return hour + (minute / 60.0);
  }

  // Helper method to check overlap
  bool isSlotOverlapping(String proposedStartStr, String proposedEndStr, List<Map<String, String>> bookedSlots) {
    final propStart = _parseTimeToDouble(proposedStartStr);
    final propEnd = _parseTimeToDouble(proposedEndStr);
    
    for (var slot in bookedSlots) {
      final slotStart = _parseTimeToDouble(slot['start_time']!);
      final slotEnd = _parseTimeToDouble(slot['end_time']!);
      
      if (propStart < slotEnd && propEnd > slotStart) {
        return true; // Overlap detected
      }
    }
    return false;
  }

  // 📅 Check if either user has an overlapping accepted meeting before submission
  Future<bool> hasMeetingConflict(String organizerId, String attendeeId, String date, String startTime, String endTime) async {
    try {
      // Fetch all accepted meetings for either user on that date
      final response = await _supabase
          .from('meetings')
          .select('start_time, end_time')
          .eq('date', date)
          .eq('status', 'accepted')
          .or('organizer_id.eq.$organizerId,attendee_id.eq.$organizerId,organizer_id.eq.$attendeeId,attendee_id.eq.$attendeeId');
      
      final booked = (response as List).map((item) {
        return {
          'start_time': item['start_time'].toString().substring(0, 5),
          'end_time': item['end_time'].toString().substring(0, 5),
        };
      }).toList();

      return isSlotOverlapping(startTime, endTime, booked);
    } catch (e) {
      debugPrint('Error checking meeting conflict: $e');
      return false; // Fail safe
    }
  }

  // 📅 Stream a single meeting's status updates in real-time
  Stream<String> streamMeetingStatus(String meetingId) {
    return _supabase
        .from('meetings')
        .stream(primaryKey: ['id'])
        .eq('id', meetingId)
        .map((maps) {
          if (maps.isNotEmpty) {
            return maps.first['status'] as String;
          }
          return 'pending';
        });
  }

  // 📚 Fetch all sessions for a specific event
  Future<List<SessionModel>> fetchSessionsForEvent(String eventId) async {
    try {
      final response = await _supabase
          .from('sessions')
          .select()
          .eq('event_id', eventId)
          .order('start_time', ascending: true);
      
      return (response as List).map((data) => SessionModel.fromJson(data)).toList();
    } catch (e) {
      debugPrint('Error fetching sessions: $e');
      return [];
    }
  }

  // ⭐ Fetch favorited sessions for the current/mock user
  Future<List<String>> fetchSessionFavorites() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return [];
      final response = await _supabase
          .from('session_favorites')
          .select('session_id')
          .eq('user_id', currentUserId);
      
      return (response as List).map((data) => data['session_id'].toString()).toList();
    } catch (e) {
      debugPrint('Error fetching favorites: $e');
      return [];
    }
  }

  // ⭐ Toggle session favorite (add/remove from agenda)
  Future<bool> toggleSessionFavorite(String sessionId, bool isFavorite) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return false;
      if (isFavorite) {
        await _supabase.from('session_favorites').insert({
          'user_id': currentUserId,
          'session_id': sessionId,
        });
      } else {
        await _supabase
            .from('session_favorites')
            .delete()
            .eq('user_id', currentUserId)
            .eq('session_id', sessionId);
      }
      return true;
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      return false;
    }
  }

  // 🤝 Fetch total accepted connections count for the current/mock user
  Future<int> fetchConnectionsCount() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return 0;
      final response = await _supabase
          .from('connections')
          .select('id, status')
          .eq('user_id', currentUserId);
      
      final list = (response as List).where((item) => item['status'] != 'pending').toList();
      return list.length;
    } catch (e) {
      debugPrint('Error fetching connections count: $e');
      return 0;
    }
  }

  // 📅 Fetch the next upcoming accepted meeting for the current/mock user
  Future<MeetingModel?> fetchNextMeeting() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) return null;
      final response = await _supabase
          .from('meetings')
          .select('*, organizer_profile:profiles!organizer_id(*), attendee_profile:profiles!attendee_id(*)')
          .eq('status', 'accepted')
          .or('organizer_id.eq.$currentUserId,attendee_id.eq.$currentUserId')
          .order('date', ascending: true)
          .order('start_time', ascending: true);
      
      final list = response as List;
      if (list.isEmpty) return null;
      
      final now = DateTime.now();
      for (var item in list) {
        final meeting = MeetingModel.fromJson(item, currentUserId);
        try {
          final dateParts = meeting.date.split('-');
          final timeParts = meeting.startTime.split(':');
          final meetingDateTime = DateTime(
            int.parse(dateParts[0]),
            int.parse(dateParts[1]),
            int.parse(dateParts[2]),
            int.parse(timeParts[0]),
            int.parse(timeParts[1]),
          );
          if (meetingDateTime.isAfter(now)) {
            return meeting;
          }
        } catch (_) {
          return meeting;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching next meeting: $e');
      return null;
    }
  }
}
