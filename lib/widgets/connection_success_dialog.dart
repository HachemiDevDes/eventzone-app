import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../utils/avatar_helper.dart';
import '../screens/professional_profile_screen.dart';
import '../utils/nav_key.dart';

class ConnectionSuccessDialog extends StatelessWidget {
  final String name;
  final bool isScanner;
  final String? title;
  final String? jobTitle;
  final String? company;
  final String? avatarUrl;
  final String? targetUserId;
  final String? connectionId;
  final String? email;
  final String? phone;
  final String? website;
  final String? department;
  final String? address;
  final List<String>? tags;
  final dynamic socialLinks;
  final VoidCallback? onViewProfile;
  final VoidCallback? onDismiss;

  const ConnectionSuccessDialog({
    super.key,
    required this.name,
    required this.isScanner,
    this.title,
    this.jobTitle,
    this.company,
    this.avatarUrl,
    this.targetUserId,
    this.connectionId,
    this.email,
    this.phone,
    this.website,
    this.department,
    this.address,
    this.tags,
    this.socialLinks,
    this.onViewProfile,
    this.onDismiss,
  });

  static bool _isShowing = false;

  static Future<void> show(
    BuildContext context, {
    required String name,
    required bool isScanner,
    String? title,
    String? jobTitle,
    String? company,
    String? avatarUrl,
    String? targetUserId,
    String? connectionId,
    String? email,
    String? phone,
    String? website,
    String? department,
    String? address,
    List<String>? tags,
    dynamic socialLinks,
    VoidCallback? onViewProfile,
    VoidCallback? onDismiss,
  }) async {
    if (_isShowing) return;
    _isShowing = true;

    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}

    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss Connection',
        barrierColor: Colors.black.withValues(alpha: 0.75),
        transitionDuration: const Duration(milliseconds: 320),
        transitionBuilder: (context, anim1, anim2, child) {
          final curved = CurvedAnimation(parent: anim1, curve: Curves.easeOutBack);
          return ScaleTransition(
            scale: curved,
            child: FadeTransition(opacity: anim1, child: child),
          );
        },
        pageBuilder: (context, anim1, anim2) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: ConnectionSuccessDialog(
                name: name,
                isScanner: isScanner,
                title: title,
                jobTitle: jobTitle,
                company: company,
                avatarUrl: avatarUrl,
                targetUserId: targetUserId,
                connectionId: connectionId,
                email: email,
                phone: phone,
                website: website,
                department: department,
                address: address,
                tags: tags,
                socialLinks: socialLinks,
                onViewProfile: onViewProfile,
                onDismiss: onDismiss,
              ),
            ),
          );
        },
      );
    } finally {
      _isShowing = false;
    }
  }

  void _handleViewProfile(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();

    if (onViewProfile != null) {
      onViewProfile!();
      return;
    }

    final targetContext = rootNavigatorKey.currentContext ?? context;
    final String professionalTitle = (jobTitle != null && jobTitle!.isNotEmpty)
        ? ((company != null && company!.isNotEmpty) ? "$jobTitle at $company" : jobTitle!)
        : ((company != null && company!.isNotEmpty) ? "Professional at $company" : "Attendee");

    Navigator.of(targetContext).push(
      MaterialPageRoute(
        builder: (ctx) => ProfessionalProfileScreen(
          name: name,
          title: professionalTitle,
          avatarUrl: avatarUrl ?? '',
          targetUserId: targetUserId,
          connectionId: connectionId,
          source: isScanner ? "QR Code Scan" : "QR Code",
          isNew: "true",
          email: email,
          phone: phone,
          website: website,
          company: company,
          department: department,
          address: address,
          tags: tags,
          socialLinks: socialLinks,
          createdAt: DateTime.now().toIso8601String(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = getAvatarProvider(avatarUrl);
    final String dialogTitle = title ?? (isScanner ? "Connected! 🎉" : "New Connection! 🎉");
    final String companyText = (company != null && company!.trim().isNotEmpty) ? company!.trim() : "";
    final String roleText = (jobTitle != null && jobTitle!.trim().isNotEmpty) ? jobTitle!.trim() : "";
    final String subtitleBadge = roleText.isNotEmpty
        ? (companyText.isNotEmpty ? "$roleText @$companyText" : roleText)
        : (companyText.isNotEmpty ? companyText : "");

    return Container(
      width: 340,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.2),
            blurRadius: 36,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 25,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Celebration Badge
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      LucideIcons.userCheck,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Dialog Title
                Text(
                  dialogTitle,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Avatar with glowing ring
                Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: const Color(0xFF1E293B),
                    backgroundImage: imageProvider,
                    child: imageProvider == null
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 16),

                // Personalized Connected Message
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      height: 1.35,
                    ),
                    children: isScanner
                        ? [
                            const TextSpan(text: "You are now connected with\n"),
                            TextSpan(
                              text: name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                          ]
                        : [
                            TextSpan(
                              text: name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                              ),
                            ),
                            const TextSpan(text: "\nhas connected with you!"),
                          ],
                  ),
                ),

                // Subtitle / Company Badge
                if (subtitleBadge.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(LucideIcons.briefcase, color: Colors.white54, size: 13),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            subtitleBadge,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Primary CTA: View Profile
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _handleViewProfile(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.user, color: Colors.white, size: 18),
                            SizedBox(width: 8),
                            Text(
                              "View Profile",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Secondary CTA: Done / Dismiss
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context, rootNavigator: true).pop();
                      if (onDismiss != null) onDismiss!();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isScanner ? "Done" : "Awesome!",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
