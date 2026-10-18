import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../services/supabase_service.dart';
import '../theme/profile_material_finish.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/share_card_sheet.dart';
class MyQRCodeScreen extends StatefulWidget {
  const MyQRCodeScreen({super.key});

  @override
  State<MyQRCodeScreen> createState() => _MyQRCodeScreenState();
}

class _MyQRCodeScreenState extends State<MyQRCodeScreen> {
  final _supabaseService = SupabaseService();
  bool _isLoading = true;
  String _fullName = "Attendee";
  String _jobTitle = "";
  String _companyName = "";
  String _avatarUrl = "";
  int _dailyStreak = 0;
  ProfileMaterialFinish _finish = ProfileMaterialFinish.titaniumCobalt;

  String _userId = "";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _userId = currentUserId;
    });
    final data = await _supabaseService.fetchProfile(currentUserId);
    if (data != null) {
      final streak = await _supabaseService.calculateDailyStreak(currentUserId);
      setState(() {
        _fullName = data['full_name'] ?? 'Attendee';
        _jobTitle = data['job_title'] ?? '';
        _companyName = data['company_name'] ?? '';
        _avatarUrl = data['avatar_url'] ?? "";
        _dailyStreak = streak;
        _finish = ProfileMaterialFinish.fromProfile(data);
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
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
    // Unique data for the user
    final String userData = "https://profile.eventzone.pro/?id=$_userId";
    final subtitle = _companyName.isNotEmpty 
        ? "$_jobTitle @$_companyName"
        : _jobTitle;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("My Event Pass", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: EventzoneTheme.buildPlayfulBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: _isLoading
                ? const CircularProgressIndicator(color: EventzoneTheme.primaryAction)
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: _finish.glowColor,
                              blurRadius: 30,
                              spreadRadius: -10,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: GlassContainer(
                          padding: const EdgeInsets.all(32),
                          borderRadius: 32,
                          borderColor: _finish.cardBorderColor,
                          borderWidth: 1.5,
                          child: Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _finish.primaryColor.withOpacity(0.5),
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 35,
                                  backgroundColor: Colors.white10,
                                  backgroundImage: _avatarUrl.isNotEmpty ? _getAvatarProvider(_avatarUrl) : null,
                                  child: _avatarUrl.isEmpty
                                      ? const Icon(Icons.person, size: 35, color: Colors.white54)
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _fullName,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: const TextStyle(fontSize: 14, color: Colors.white38),
                                ),
                              if (_dailyStreak > 0) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(LucideIcons.flame, color: Colors.amber, size: 14),
                                      const SizedBox(width: 4),
                                      Text(
                                        "$_dailyStreak Day Streak",
                                        style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            const SizedBox(height: 32),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: QrImageView(
                                data: userData,
                                version: QrVersions.auto,
                                size: 200.0,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xFF0B0F19),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xFF0B0F19),
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            Text(
                              "Scan to connect instantly".tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _finish.primaryColor, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      ),
                      const SizedBox(height: 40),
                      OutlinedButton.icon(
                        onPressed: () {
                          ShareCardSheet.show(
                            context,
                            qrData: userData,
                            fullName: _fullName,
                          );
                        },
                        icon: Icon(LucideIcons.share2, size: 18, color: _finish.primaryColor),
                        label: Text("Share Card".tr(), style: TextStyle(color: _finish.primaryColor, fontWeight: FontWeight.bold)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _finish.primaryColor),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
