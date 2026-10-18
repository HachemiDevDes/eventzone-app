import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:app_links/app_links.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../screens/professional_profile_screen.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _isProcessingPendingContact = false;

  // Callback when a profile ID is detected
  Function(String profileId)? onProfileIdFound;

  void initialize() {
    // 1. Check initial link if app was cold-started by a link
    _checkInitialLink();

    // 2. Listen to incoming links while app is running in background or foreground
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _processUri(uri);
    });

    // 3. Check deferred deep linking via clipboard (for newly installed apps)
    _checkDeferredLinkViaClipboard();
  }

  void _checkInitialLink() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _processUri(initialUri);
      }
    } catch (e) {
      debugPrint("[DeepLinkService] Failed to get initial deep link: $e");
    }
  }

  void _processUri(Uri uri) async {
    // 1. Auth callback handling
    final isAuthCallback = uri.scheme == 'eventzone' && (
      uri.host.contains('callback') ||
      uri.path.contains('callback') ||
      uri.queryParameters.containsKey('code') ||
      uri.fragment.contains('access_token') ||
      uri.fragment.contains('error')
    );

    if (isAuthCallback || uri.path.contains('login-callback') || uri.path.contains('oauth-callback')) {
      try {
        debugPrint("[DeepLinkService] Processing deep link auth callback: $uri");
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
      } catch (e) {
        debugPrint("[DeepLinkService] Error recovering session from URL: $e");
      }
      return;
    }

    // 2. Profile deep link handling (handles both eventzone://profile?id=... and https://profile.eventzone.pro/?id=...)
    final isProfileLink = (uri.host == 'profile' ||
            uri.path.contains('profile') ||
            uri.path == '/profile') &&
        uri.queryParameters.containsKey('id');

    if (isProfileLink) {
      final profileId = uri.queryParameters['id'];
      if (profileId != null && profileId.isNotEmpty) {
        debugPrint("[DeepLinkService] Profile deep link detected: $profileId");
        await _savePendingContactId(profileId);
        onProfileIdFound?.call(profileId);
      }
    }
  }

  Future<void> _checkDeferredLinkViaClipboard([BuildContext? context]) async {
    try {
      final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
      if (data != null && data.text != null) {
        final text = data.text!.trim();
        if (text.startsWith('eventzone_profile_')) {
          final profileId = text.replaceFirst('eventzone_profile_', '').trim();
          if (profileId.isNotEmpty) {
            debugPrint("[DeepLinkService] Found deferred profile token in clipboard: $profileId");
            await _savePendingContactId(profileId);
            // Clear clipboard to avoid repeatedly triggering
            await Clipboard.setData(const ClipboardData(text: ''));

            if (context != null && context.mounted) {
              await processPendingContact(context);
            } else {
              onProfileIdFound?.call(profileId);
            }
          }
        }
      }
    } catch (e) {
      debugPrint("[DeepLinkService] Failed to check clipboard for deferred deep link: $e");
    }
  }

  Future<void> _savePendingContactId(String profileId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('pending_contact_id', profileId);
      debugPrint("[DeepLinkService] Saved pending_contact_id to SharedPreferences: $profileId");
    } catch (e) {
      debugPrint("[DeepLinkService] Error saving pending_contact_id: $e");
    }
  }

  /// Called when the app resumes from the background to detect deferred links
  Future<void> checkDeferredLinkOnResume(BuildContext context) async {
    await _checkDeferredLinkViaClipboard(context);
    if (context.mounted) {
      await processPendingContact(context);
    }
  }

  /// Automatically retrieves and saves the pending contact into user's connections
  Future<void> processPendingContact(BuildContext context) async {
    if (_isProcessingPendingContact) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingId = prefs.getString('pending_contact_id');
      if (pendingId == null || pendingId.trim().isEmpty) return;

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) {
        debugPrint("[DeepLinkService] User not authenticated yet; keeping pending_contact_id: $pendingId");
        return;
      }

      if (currentUser.id == pendingId) {
        debugPrint("[DeepLinkService] Pending contact is own profile; clearing.");
        await prefs.remove('pending_contact_id');
        return;
      }

      _isProcessingPendingContact = true;
      debugPrint("[DeepLinkService] Processing pending contact ID: $pendingId for user: ${currentUser.id}");

      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', pendingId)
          .maybeSingle();

      if (response == null) {
        debugPrint("[DeepLinkService] Target profile $pendingId not found.");
        await prefs.remove('pending_contact_id');
        _isProcessingPendingContact = false;
        return;
      }

      final rawMeta = response['metadata'];
      Map<String, dynamic> metadata = {};
      if (rawMeta is Map<String, dynamic>) {
        metadata = rawMeta;
      } else if (rawMeta is String && rawMeta.isNotEmpty) {
        try {
          metadata = jsonDecode(rawMeta);
        } catch (_) {}
      }

      final name = (response['full_name'] as String? ?? '').trim().isNotEmpty
          ? (response['full_name'] as String).trim()
          : 'Saved Contact';
      final title = (response['job_title'] as String? ?? '').trim();
      final company = (response['company_name'] as String? ?? '').trim();
      final email = (response['email'] as String? ?? metadata['email'] as String? ?? '').trim();
      final phone = (response['phone'] as String? ?? metadata['phone'] as String? ?? '').trim();
      final website = (response['website'] as String? ?? metadata['website'] as String? ?? '').trim();
      final address = (response['address'] as String? ?? metadata['address'] as String? ?? '').trim();
      final department = (metadata['department'] as String? ?? '').trim();
      final avatarUrl = (response['avatar_url'] as String? ?? '').trim();

      // Check if contact already exists in connections for this user
      final existing = await Supabase.instance.client
          .from('connections')
          .select('id')
          .eq('user_id', currentUser.id)
          .ilike('name', name)
          .maybeSingle();

      if (existing == null) {
        await Supabase.instance.client.from('connections').insert({
          'user_id': currentUser.id,
          'name': name,
          'title': title,
          'company': company,
          'department': department,
          'email': email,
          'phone': phone,
          'website': website,
          'address': address,
          'avatar_url': avatarUrl,
          'source': 'Eventzone Card',
          'is_new': true,
        });
        debugPrint("[DeepLinkService] Successfully auto-saved $name into connections!");
      } else {
        debugPrint("[DeepLinkService] Contact $name already in connections.");
      }

      // Clear the pending key so it only auto-saves once
      await prefs.remove('pending_contact_id');

      // Show celebratory confirmation sheet
      if (context.mounted) {
        _showContactAddedDialog(
          context,
          name: name,
          title: title,
          company: company,
          avatarUrl: avatarUrl,
          email: email,
          phone: phone,
          website: website,
          department: department,
          address: address,
        );
      }
    } catch (e) {
      debugPrint("[DeepLinkService] Exception processing pending contact: $e");
    } finally {
      _isProcessingPendingContact = false;
    }
  }

  void _showContactAddedDialog(
    BuildContext context, {
    required String name,
    required String title,
    required String company,
    required String avatarUrl,
    required String email,
    required String phone,
    required String website,
    required String department,
    required String address,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F121E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(color: Colors.white12, width: 1),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: EventzoneTheme.accentSuccess.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: EventzoneTheme.accentSuccess.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  LucideIcons.userCheck,
                  color: EventzoneTheme.accentSuccess,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Contact Added! 🎉",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "$name has been automatically saved to your Eventzone network from the card you scanned.",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: EventzoneTheme.primaryAction.withValues(alpha: 0.2),
                      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                      child: avatarUrl.isEmpty
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
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
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (title.isNotEmpty || company.isNotEmpty)
                            Text(
                              [title, company].where((s) => s.isNotEmpty).join(' • '),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text("Done", style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: EventzoneTheme.primaryAction,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ProfessionalProfileScreen(
                              name: name,
                              title: title,
                              company: company,
                              avatarUrl: avatarUrl,
                              email: email,
                              phone: phone,
                              website: website,
                              department: department,
                              address: address,
                              source: 'Eventzone Card',
                              isNew: 'true',
                            ),
                          ),
                        );
                      },
                      child: const Text("View Contact", style: TextStyle(fontWeight: FontWeight.w700)),
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

  void dispose() {
    _linkSubscription?.cancel();
  }
}
