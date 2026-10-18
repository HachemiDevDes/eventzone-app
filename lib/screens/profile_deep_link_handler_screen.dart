import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'review_contact_screen.dart';
import '../theme/eventzone_theme.dart';

class ProfileDeepLinkHandlerScreen extends StatefulWidget {
  final String? profileId;

  const ProfileDeepLinkHandlerScreen({super.key, required this.profileId});

  @override
  State<ProfileDeepLinkHandlerScreen> createState() => _ProfileDeepLinkHandlerScreenState();
}

class _ProfileDeepLinkHandlerScreenState extends State<ProfileDeepLinkHandlerScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    if (widget.profileId == null || widget.profileId!.trim().isEmpty) {
      setState(() {
        _error = "Invalid profile link.";
        _isLoading = false;
      });
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.profileId!.trim())
          .maybeSingle();

      if (!mounted) return;

      if (response == null) {
        setState(() {
          _error = "Profile not found.";
          _isLoading = false;
        });
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

      final name = (response['full_name'] as String? ?? '').trim();
      final title = (response['job_title'] as String? ?? '').trim();
      final company = (response['company_name'] as String? ?? '').trim();
      final email = (response['email'] as String? ?? metadata['email'] as String? ?? '').trim();
      final phone = (response['phone'] as String? ?? metadata['phone'] as String? ?? '').trim();
      final website = (response['website'] as String? ?? metadata['website'] as String? ?? '').trim();
      final address = (response['address'] as String? ?? metadata['address'] as String? ?? '').trim();
      final department = (metadata['department'] as String? ?? '').trim();

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ReviewContactScreen(
            initialName: name.isNotEmpty ? name : 'New Contact',
            initialTitle: title,
            initialEmail: email,
            initialPhone: phone,
            initialWebsite: website,
            initialCompany: company,
            initialDepartment: department,
            initialAddress: address,
            source: 'Eventzone Card / Web Profile',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Could not load profile.";
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EventzoneTheme.backgroundEnd,
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: EventzoneTheme.primaryAction)
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error ?? "Unknown error",
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: EventzoneTheme.primaryAction),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text("Go Back", style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
