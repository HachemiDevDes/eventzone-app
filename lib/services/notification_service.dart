import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../utils/nav_key.dart';
import '../widgets/connection_success_dialog.dart';
import '../screens/professional_profile_screen.dart';
import '../screens/chat_detail_screen.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final Set<String> _recentlyScannedUserIds = {};
  String? activeChatRecipientId;

  void markRecentlyScanned(String targetUserId) {
    _recentlyScannedUserIds.add(targetUserId);
    Future.delayed(const Duration(seconds: 15), () {
      _recentlyScannedUserIds.remove(targetUserId);
    });
  }

  bool isRecentlyScanned(String userId) {
    return _recentlyScannedUserIds.contains(userId);
  }

  void _handleNotificationPayload(Map<String, dynamic> data) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (data['type'] == 'message') {
      Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            contactName: data['sender_name'] ?? 'Attendee',
            avatarUrl: data['sender_avatar'] ?? '',
            recipientId: data['sender_id'],
          ),
        ),
      );
    } else if (data['type'] == 'connection') {
      Navigator.of(ctx).push(
        MaterialPageRoute(
          builder: (context) => ProfessionalProfileScreen(
            name: data['name'] ?? 'Attendee',
            title: data['title'] ?? '',
            avatarUrl: data['avatarUrl'] ?? '',
            targetUserId: data['userId'],
            connectionId: data['connectionId'],
            email: data['email'],
            phone: data['phone'],
            website: data['website'],
            company: data['company'],
            department: data['department'],
            address: data['address'],
            source: 'Notification',
            isNew: 'true',
            createdAt: DateTime.now().toIso8601String(),
          ),
        ),
      );
    }
  }

  Future<void> initialize() async {
    // 1. Initialize Firebase (if configured)
    try {
      if (Firebase.apps.isEmpty) {
        // TODO: The user must add google-services.json for Android. 
        // This will initialize using the default options from that file.
        await Firebase.initializeApp();
      }
    } catch (e) {
      debugPrint("Firebase not yet configured. Skipping FCM initialization: $e");
    }

    // 2. Initialize Local Notifications & Timezone
    tz.initializeTimeZones();
    AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    
    // For iOS if needed later
    DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _localNotificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint("Notification clicked: ${response.payload}");
        final payloadStr = response.payload;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final data = jsonDecode(payloadStr);
            if (data is Map<String, dynamic>) {
              _handleNotificationPayload(data);
            }
          } catch (e) {
            debugPrint("Error handling notification click response: $e");
          }
        }
      },
    );

    // 3. Request permissions for Firebase Messaging
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted push notification permission');
        
        // 4. Fetch FCM Token and save to Supabase
        String? token = await messaging.getToken();
        if (token != null) {
          await _saveTokenToSupabase(token);
        }

        // Listen for token refreshes
        messaging.onTokenRefresh.listen(_saveTokenToSupabase);

        // 5. Handle foreground FCM messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('Got a message whilst in the foreground: ${message.data}');
          final data = message.data;
          final senderId = data['sender_id'];
          if (senderId != null && senderId == activeChatRecipientId) {
            // Already viewing this active chat
            return;
          }
          if (message.notification != null) {
            showLocalNotification(
              title: message.notification!.title ?? 'New Message',
              body: message.notification!.body ?? '',
              payload: jsonEncode(data),
            );
          }
        });

        // 6. Handle notification click when app is opened from background
        FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
          debugPrint('App opened from push notification: ${message.data}');
          if (message.data.isNotEmpty) {
            _handleNotificationPayload(message.data);
          }
        });

        // 7. Check if app was opened from terminated state by a notification
        messaging.getInitialMessage().then((RemoteMessage? message) {
          if (message != null && message.data.isNotEmpty) {
            debugPrint('App launched from terminated state via notification: ${message.data}');
            _handleNotificationPayload(message.data);
          }
        });
      }
    } catch (e) {
      debugPrint("FCM Permission request failed. Ensure Firebase is configured: $e");
    }
    
    // 6. Listen to Auth state changes to set up or tear down realtime channels
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _setupSupabaseRealtimeListeners();
      } else {
        _teardownRealtimeListeners();
      }
    });
  }

  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _connectionsChannel;
  RealtimeChannel? _meetingsChannel;

  void _teardownRealtimeListeners() {
    _messagesChannel?.unsubscribe();
    _connectionsChannel?.unsubscribe();
    _meetingsChannel?.unsubscribe();
    _messagesChannel = null;
    _connectionsChannel = null;
    _meetingsChannel = null;
  }

  void _setupSupabaseRealtimeListeners() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Prevent duplicate subscriptions
    _teardownRealtimeListeners();

    // 1. Listen for new messages
    _messagesChannel = Supabase.instance.client
        .channel('public:messages:recipient_id=eq.${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: user.id,
          ),
          callback: (payload) async {
            final newMsg = payload.newRecord;
            final senderId = newMsg['sender_id']?.toString();
            
            // If the user is currently on ChatDetailScreen with THIS exact sender, do not show duplicate notification
            if (senderId != null && senderId == activeChatRecipientId) {
              return;
            }

            // Fetch sender profile for name and avatar
            final senderRes = await Supabase.instance.client
                .from('profiles')
                .select('full_name, avatar_url')
                .eq('id', senderId ?? '')
                .maybeSingle();
                
            final senderName = senderRes?['full_name'] ?? 'Someone';
            final senderAvatar = senderRes?['avatar_url'] ?? '';
            final content = newMsg['content']?.toString() ?? '';
            
            showLocalNotification(
              title: senderName,
              body: content,
              payload: jsonEncode({
                'type': 'message',
                'sender_id': senderId,
                'sender_name': senderName,
                'sender_avatar': senderAvatar,
                'content': content,
              }),
            );
          },
        )
        .subscribe();
        
    // 2. Listen for connection requests & connections
    _connectionsChannel = Supabase.instance.client
        .channel('public:connections:linked_profile_id=eq.${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'connections',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'linked_profile_id',
            value: user.id,
          ),
          callback: (payload) async {
            final newConn = payload.newRecord;
            final status = newConn['status']?.toString();
            final source = newConn['source']?.toString();
            final senderId = newConn['user_id']?.toString();

            // Ignore if self-created
            if (senderId == user.id) return;

            // Ignore if this connection was just created by scanning on THIS device
            if (senderId != null && isRecentlyScanned(senderId)) {
              debugPrint("Skipping notification for $senderId: recently scanned on this device.");
              return;
            }

            // Extract sender full profile from database
            Map<String, dynamic>? senderProfile;
            if (senderId != null) {
              try {
                senderProfile = await Supabase.instance.client
                    .from('profiles')
                    .select()
                    .eq('id', senderId)
                    .maybeSingle();
              } catch (e) {
                debugPrint("Error fetching sender profile: $e");
              }
            }

            // Extract sender name
            String partnerName = senderProfile?['full_name']?.toString().trim() ?? '';
            if (partnerName.isEmpty && newConn['notes'] != null && newConn['notes'].toString().isNotEmpty) {
              try {
                final notes = jsonDecode(newConn['notes'].toString());
                if (notes is Map && notes['sender_name'] != null && notes['sender_name'].toString().trim().isNotEmpty) {
                  partnerName = notes['sender_name'].toString().trim();
                }
              } catch (_) {}
            }
            if (partnerName.isEmpty) {
              partnerName = 'Someone';
            }

            final String job = senderProfile?['job_title']?.toString().trim() ?? '';
            final String comp = senderProfile?['company_name']?.toString().trim() ?? '';
            final String partnerTitle = job.isNotEmpty
                ? (comp.isNotEmpty ? "$job at $comp" : job)
                : (comp.isNotEmpty ? "Professional at $comp" : "Eventzone Attendee");
            final String partnerAvatar = senderProfile?['avatar_url']?.toString().trim() ?? '';

            if (status == 'pending') {
              showLocalNotification(
                title: 'New Connection Request',
                body: '$partnerName sent you a connection request.',
              );
            } else if (source == 'In-App Request' && status == 'connected') {
              showLocalNotification(
                title: 'Connection Accepted',
                body: '$partnerName accepted your connection request.',
              );
            } else {
              // Retrieve mutual connection ID on recipient side if it exists
              String? connectionId;
              if (senderId != null) {
                try {
                  final connRes = await Supabase.instance.client
                      .from('connections')
                      .select('id')
                      .eq('user_id', user.id)
                      .eq('linked_profile_id', senderId)
                      .maybeSingle();
                  connectionId = connRes?['id']?.toString();
                } catch (_) {}
              }

              // 1. Trigger System Notification (Tray / Background)
              showLocalNotification(
                title: 'New Connection! 🎉',
                body: '$partnerName connected with you.',
                payload: jsonEncode({
                  'type': 'connection',
                  'userId': senderId,
                  'connectionId': connectionId,
                  'name': partnerName,
                  'title': partnerTitle,
                  'avatarUrl': partnerAvatar,
                  'company': comp,
                  'jobTitle': job,
                  'email': senderProfile?['email'],
                  'phone': senderProfile?['phone'],
                  'website': senderProfile?['website'],
                  'department': senderProfile?['department'],
                  'address': senderProfile?['address'],
                }),
              );

              // 2. Trigger In-App Pop-up Celebration Dialog (Foreground)
              final navContext = rootNavigatorKey.currentContext;
              if (navContext != null && navContext.mounted) {
                ConnectionSuccessDialog.show(
                  navContext,
                  name: partnerName,
                  isScanner: false,
                  title: "New Connection! 🎉",
                  jobTitle: job.isNotEmpty ? job : null,
                  company: comp.isNotEmpty ? comp : null,
                  avatarUrl: partnerAvatar,
                  targetUserId: senderId,
                  connectionId: connectionId,
                  email: senderProfile?['email'],
                  phone: senderProfile?['phone'],
                  website: senderProfile?['website'],
                  department: senderProfile?['department'],
                  address: senderProfile?['address'],
                  tags: (senderProfile?['interests'] as List?)?.map((e) => e.toString()).toList(),
                  socialLinks: senderProfile?['metadata']?['socials'],
                );
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'connections',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: user.id,
          ),
          callback: (payload) {
            final updatedConn = payload.newRecord;
            final oldConn = payload.oldRecord;
            if (oldConn['status'] == 'pending' && updatedConn['status'] == 'connected') {
              final contactName = updatedConn['name'] ?? 'Attendee';
              showLocalNotification(
                title: 'Connection Request Accepted',
                body: '$contactName accepted your connection request.',
              );
            }
          },
        )
        .subscribe();

    // 3. Listen for meeting requests & responses
    _meetingsChannel = Supabase.instance.client
        .channel('public:meetings:user:${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meetings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'attendee_id',
            value: user.id,
          ),
          callback: (payload) async {
            final meeting = payload.newRecord;
            if (meeting['status'] == 'pending') {
              String organizerName = 'Someone';
              final organizerId = meeting['organizer_id']?.toString();
              if (organizerId != null && organizerId.isNotEmpty) {
                try {
                  final profile = await Supabase.instance.client
                      .from('profiles')
                      .select('full_name')
                      .eq('id', organizerId)
                      .maybeSingle();
                  if (profile != null && profile['full_name'] != null && profile['full_name'].toString().trim().isNotEmpty) {
                    organizerName = profile['full_name'].toString().trim();
                  }
                } catch (_) {}
              }

              final title = meeting['title'] ?? 'Meeting';
              final date = meeting['date'] ?? '';
              final time = (meeting['start_time'] ?? '').toString();
              final formattedTime = time.length >= 5 ? time.substring(0, 5) : time;
              final dateStr = date.isNotEmpty ? ' on $date' : '';
              final timeStr = formattedTime.isNotEmpty ? ' at $formattedTime' : '';

              showLocalNotification(
                title: 'New Meeting Request',
                body: '$organizerName requested a meeting: "$title"$dateStr$timeStr.',
              );
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'meetings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'organizer_id',
            value: user.id,
          ),
          callback: (payload) async {
            final meeting = payload.newRecord;
            final oldMeeting = payload.oldRecord;
            if (oldMeeting['status'] != meeting['status']) {
              String attendeeName = 'Attendee';
              final attendeeId = meeting['attendee_id']?.toString();
              if (attendeeId != null && attendeeId.isNotEmpty) {
                try {
                  final profile = await Supabase.instance.client
                      .from('profiles')
                      .select('full_name')
                      .eq('id', attendeeId)
                      .maybeSingle();
                  if (profile != null && profile['full_name'] != null && profile['full_name'].toString().trim().isNotEmpty) {
                    attendeeName = profile['full_name'].toString().trim();
                  }
                } catch (_) {}
              }

              final title = meeting['title'] ?? 'Meeting';
              if (meeting['status'] == 'accepted') {
                showLocalNotification(
                  title: 'Meeting Accepted',
                  body: '$attendeeName accepted your meeting request: "$title".',
                );
              } else if (meeting['status'] == 'declined') {
                showLocalNotification(
                  title: 'Meeting Declined',
                  body: '$attendeeName declined your meeting request: "$title".',
                );
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _saveTokenToSupabase(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      // Upsert the token to the user_fcm_tokens table
      await Supabase.instance.client.from('user_fcm_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
      debugPrint("FCM token saved to Supabase.");
    } catch (e) {
      debugPrint("Error saving FCM token to Supabase: $e");
    }
  }

  final List<String> _recentNotifications = [];

  Future<void> showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final dedupeKey = '$title:$body';
    if (_recentNotifications.contains(dedupeKey)) {
      return;
    }
    _recentNotifications.add(dedupeKey);
    Future.delayed(const Duration(seconds: 5), () {
      _recentNotifications.remove(dedupeKey);
    });

    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'high_importance_channel', // id
      'High Importance Notifications', // name
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
    );
    
    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
        
    await _localNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch % 100000, // random id
      title: title,
      body: body,
      notificationDetails: platformChannelSpecifics,
      payload: payload,
    );
  }

  Future<void> scheduleDailyStreakNotifications() async {
    await _localNotificationsPlugin.cancel(id: 909);
    await _localNotificationsPlugin.cancel(id: 911);

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    
    // 9 PM Notification
    tz.TZDateTime scheduledDate9PM =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 21);
    if (scheduledDate9PM.isBefore(now)) {
      scheduledDate9PM = scheduledDate9PM.add(Duration(days: 1));
    }

    // 11 AM Notification
    tz.TZDateTime scheduledDate11AM =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, 11);
    if (scheduledDate11AM.isBefore(now)) {
      scheduledDate11AM = scheduledDate11AM.add(Duration(days: 1));
    }

    AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'daily_streak_channel',
      'Daily Streak Reminder',
      channelDescription: 'Reminds you to keep your networking streak alive',
      importance: Importance.max,
      priority: Priority.high,
    );

    NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    // Schedule 9 PM
    await _localNotificationsPlugin.zonedSchedule(
      id: 909,
      title: 'Keep your streak alive! 🔥',
      body: 'Remember to add at least one contact today to keep your daily streak going.',
      scheduledDate: scheduledDate9PM,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // Schedule 11 AM
    await _localNotificationsPlugin.zonedSchedule(
      id: 911,
      title: 'Don\'t lose your streak! 🔥',
      body: 'Connect with someone new today to keep your streak going strong.',
      scheduledDate: scheduledDate11AM,
      notificationDetails: platformChannelSpecifics,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}


// Background FCM handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}
