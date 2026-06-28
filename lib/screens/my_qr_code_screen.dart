import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../services/supabase_service.dart';

class MyQRCodeScreen extends StatefulWidget {
  const MyQRCodeScreen({super.key});

  @override
  State<MyQRCodeScreen> createState() => _MyQRCodeScreenState();
}

class _MyQRCodeScreenState extends State<MyQRCodeScreen> {
  final _supabaseService = SupabaseService();
  static const String _profileId = "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
  bool _isLoading = true;
  String _fullName = "Hachemi Mohamed";
  String _jobTitle = "Product Lead";
  String _companyName = "TechFlow";
  String _avatarUrl = "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&fit=crop";

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final data = await _supabaseService.fetchProfile(_profileId);
    if (data != null) {
      setState(() {
        _fullName = data['full_name'] ?? 'Hachemi Mohamed';
        _jobTitle = data['job_title'] ?? '';
        _companyName = data['company_name'] ?? '';
        _avatarUrl = data['avatar_url'] ?? "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&fit=crop";
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
    final String userData = "eventzone://user/$_profileId";
    final subtitle = _companyName.isNotEmpty 
        ? "$_jobTitle @ $_companyName"
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
                      GlassContainer(
                        padding: const EdgeInsets.all(32),
                        borderRadius: 32,
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 35,
                              backgroundImage: _getAvatarProvider(_avatarUrl),
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
                            const Text(
                              "Scan to connect instantly",
                              style: TextStyle(color: EventzoneTheme.primaryAction, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(LucideIcons.share, size: 18),
                        label: const Text("Share Pass"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white10),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
