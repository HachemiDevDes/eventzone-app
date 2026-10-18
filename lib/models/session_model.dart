class SessionModel {
  final String id;
  final String? eventId;
  final String title;
  final String? description;
  final String? speakerId;
  final DateTime startTime;
  final DateTime endTime;
  final String? location;
  final String? track;
  final String? date;
  final List<SessionSpeaker> speakers;
  final List<String> logos;

  SessionModel({
    required this.id,
    this.eventId,
    required this.title,
    this.description,
    this.speakerId,
    required this.startTime,
    required this.endTime,
    this.location,
    this.track,
    this.date,
    required this.speakers,
    required this.logos,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    // Parse speakers JSON array
    final rawSpeakers = json['speakers'] as List? ?? [];
    final rawModerators = json['moderators'] as List? ?? [];

    final List<SessionSpeaker> parsedSpeakers = [];

    for (final s in rawSpeakers) {
      if (s is Map) {
        parsedSpeakers.add(SessionSpeaker.fromJson(Map<String, dynamic>.from(s)));
      } else if (s is String && s.trim().isNotEmpty) {
        parsedSpeakers.add(SessionSpeaker(
          name: s.trim(),
          title: '',
          company: '',
          avatarUrl: '',
        ));
      }
    }

    for (final m in rawModerators) {
      if (m is Map) {
        final modMap = Map<String, dynamic>.from(m);
        if (modMap['role'] == null || (modMap['role'] as String).isEmpty) {
          modMap['role'] = 'Moderator';
        }
        parsedSpeakers.add(SessionSpeaker.fromJson(modMap));
      } else if (m is String && m.trim().isNotEmpty) {
        parsedSpeakers.add(SessionSpeaker(
          name: m.trim(),
          title: 'Moderator',
          company: '',
          avatarUrl: '',
          role: 'Moderator',
        ));
      }
    }

    // Parse logos JSON array
    final rawLogos = json['logos'] as List? ?? [];
    final parsedLogos = rawLogos.map((l) => l.toString()).toList();

    return SessionModel(
      id: json['id'] as String,
      eventId: json['event_id'] as String?,
      title: json['title'] as String? ?? 'Untitled Session',
      description: json['description'] as String?,
      speakerId: json['speaker_id'] as String?,
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: DateTime.parse(json['end_time'] as String),
      location: json['location'] as String?,
      track: json['track'] as String?,
      date: json['date'] as String?,
      speakers: parsedSpeakers,
      logos: parsedLogos,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'title': title,
      'description': description,
      'speaker_id': speakerId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'location': location,
      'track': track,
      'date': date,
      'speakers': speakers.map((s) => s.toJson()).toList(),
      'logos': logos,
    };
  }

  /// Normalized date key 'YYYY-MM-DD'
  String get dateKey {
    if (date != null && RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(date!.trim())) {
      return date!.trim().substring(0, 10);
    }
    final local = startTime.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return "$y-$m-$d";
  }

  /// Formatted date, e.g. "Sat, Oct 12"
  String get formattedDate {
    final local = startTime.toLocal();
    const weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final weekday = weekdays[local.weekday - 1];
    final month = months[local.month - 1];
    return "$weekday, $month ${local.day}";
  }

  /// Short date, e.g. "Oct 12"
  String get shortDate {
    final local = startTime.toLocal();
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    final month = months[local.month - 1];
    return "$month ${local.day}";
  }

  /// Resolves the Day label (e.g. "Day 1", "Day 2")
  String resolveDayLabel([List<SessionModel>? allSessions]) {
    // If date string explicitly starts with Day (e.g. "Day 1", "Day 2")
    if (date != null && date!.trim().isNotEmpty) {
      final clean = date!.trim();
      if (clean.toLowerCase().startsWith('day')) {
        return clean;
      }
    }

    // If allSessions list is provided, calculate day number based on chronological unique dates
    if (allSessions != null && allSessions.isNotEmpty) {
      final distinctKeys = <String>{};
      for (final s in allSessions) {
        distinctKeys.add(s.dateKey);
      }
      final sortedKeys = distinctKeys.toList()..sort();
      final idx = sortedKeys.indexOf(dateKey);
      if (idx != -1) {
        return 'Day ${idx + 1}';
      }
    }

    return 'Day 1';
  }

  /// Resolves full day label with formatted date (e.g. "Day 1 • Sat, Oct 12")
  String resolveFullDayLabel([List<SessionModel>? allSessions]) {
    final day = resolveDayLabel(allSessions);
    return "$day • $formattedDate";
  }
}

class SessionSpeaker {
  final String? id;
  final String name;
  final String title;
  final String company;
  final String avatarUrl;
  final String? email;
  final String? role;
  final String? bio;

  SessionSpeaker({
    this.id,
    required this.name,
    required this.title,
    required this.company,
    required this.avatarUrl,
    this.email,
    this.role,
    this.bio,
  });

  factory SessionSpeaker.fromJson(Map<String, dynamic> map) {
    // Prioritize actual photos/images over placeholder generators (like ui-avatars.com)
    final candidates = [
      map['image'],
      map['photo'],
      map['avatar'],
      map['avatarUrl'],
      map['avatar_url'],
      map['picture'],
      map['profile_image'],
    ];

    String avatar = '';
    // 1. Pick any non-empty URL that is NOT a ui-avatars placeholder
    for (final c in candidates) {
      final s = c?.toString().trim();
      if (s != null && s.isNotEmpty && !s.contains('ui-avatars.com')) {
        avatar = s;
        break;
      }
    }
    // 2. Fall back to placeholder generator only if no real picture exists
    if (avatar.isEmpty) {
      for (final c in candidates) {
        final s = c?.toString().trim();
        if (s != null && s.isNotEmpty) {
          avatar = s;
          break;
        }
      }
    }

    final name = map['name']?.toString() ??
        map['fullName']?.toString() ??
        map['full_name']?.toString() ??
        'Speaker';

    // Prioritize specific speaker title/position before broad jobTitle
    final title = map['title']?.toString() ??
        map['jobTitle']?.toString() ??
        map['job_title']?.toString() ??
        map['headline']?.toString() ??
        map['position']?.toString() ??
        map['role_title']?.toString() ??
        map['designation']?.toString() ??
        map['ticket_type']?.toString() ??
        '';

    final company = map['company']?.toString() ??
        map['organization']?.toString() ??
        map['company_name']?.toString() ??
        map['companyName']?.toString() ??
        map['org']?.toString() ??
        map['org_name']?.toString() ??
        map['organization_name']?.toString() ??
        '';

    final rawRole = map['role']?.toString();
    final role = (rawRole != null && rawRole.trim().isNotEmpty) ? rawRole.trim() : 'Speaker';

    return SessionSpeaker(
      id: map['id']?.toString(),
      name: name.trim().isNotEmpty ? name.trim() : 'Speaker',
      title: title.trim(),
      company: company.trim(),
      avatarUrl: avatar.trim(),
      email: map['email']?.toString(),
      role: role,
      bio: map['bio']?.toString() ?? map['about']?.toString(),
    );
  }

  SessionSpeaker copyWith({
    String? id,
    String? name,
    String? title,
    String? company,
    String? avatarUrl,
    String? email,
    String? role,
    String? bio,
  }) {
    return SessionSpeaker(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      company: company ?? this.company,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      email: email ?? this.email,
      role: role ?? this.role,
      bio: bio ?? this.bio,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'title': title,
      'company': company,
      'avatar_url': avatarUrl,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
      if (bio != null) 'bio': bio,
    };
  }
}
