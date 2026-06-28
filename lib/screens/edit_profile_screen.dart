import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../services/supabase_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController(text: "Hachemi Mohamed");
  final _jobController = TextEditingController(text: "Product Lead");
  final _companyController = TextEditingController(text: "TechFlow");
  final _addressController = TextEditingController();

  final _supabaseService = SupabaseService();
  static const String _profileId = "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
  bool _isLoading = false;
  String _avatarUrl = "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&fit=crop";

  List<Map<String, dynamic>> _socialLinks = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    final data = await _supabaseService.fetchProfile(_profileId);
    if (data != null) {
      setState(() {
        _nameController.text = data['full_name'] ?? '';
        _jobController.text = data['job_title'] ?? '';
        _companyController.text = data['company_name'] ?? '';
        _addressController.text = data['address'] ?? '';
        _avatarUrl = data['avatar_url'] ?? "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&h=150&crop";
        
        final metadata = data['metadata'] as Map<String, dynamic>?;
        if (metadata != null && metadata['socials'] != null) {
          _socialLinks = List<Map<String, dynamic>>.from(
            (metadata['socials'] as List).map((e) => Map<String, dynamic>.from(e))
          );
        } else {
          _socialLinks = [
            {"platform": "Email", "value": "contact@eventzone.pro", "label": "Work"},
            {"platform": "LinkedIn", "value": "linkedin.com/in/hachemimohamed", "label": "LinkedIn"}
          ];
        }
      });
    }
    setState(() => _isLoading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    final success = await _supabaseService.updateProfile(
      _profileId,
      fullName: _nameController.text,
      jobTitle: _jobController.text,
      companyName: _companyController.text,
      avatarUrl: _avatarUrl,
      address: _addressController.text,
      metadata: {
        "socials": _socialLinks,
      },
    );
    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved successfully!')),
        );
        if (Navigator.canPop(context)) {
          Navigator.pop(context, true);
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save profile')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 300,
        maxHeight: 300,
        imageQuality: 70,
      );

      if (pickedFile != null) {
        final bytes = await File(pickedFile.path).readAsBytes();
        final base64String = base64Encode(bytes);
        setState(() {
          _avatarUrl = "data:image/jpeg;base64,$base64String";
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  ImageProvider _getAvatarProvider(String url) {
    if (url.startsWith("data:image")) {
      try {
        final base64Content = url.split(",")[1];
        return MemoryImage(base64Decode(base64Content));
      } catch (_) {
        // Fallback to placeholder if base64 decoding fails
      }
    }
    return NetworkImage(url);
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform.toLowerCase()) {
      case 'phone':
      case 'phone number':
        return FontAwesomeIcons.phone;
      case 'email':
        return FontAwesomeIcons.envelope;
      case 'link':
        return FontAwesomeIcons.link;
      case 'linkedin':
        return FontAwesomeIcons.linkedinIn;
      case 'instagram':
        return FontAwesomeIcons.instagram;
      case 'x':
      case 'twitter':
        return FontAwesomeIcons.xTwitter;
      case 'facebook':
        return FontAwesomeIcons.facebookF;
      case 'website':
      case 'company website':
        return FontAwesomeIcons.globe;
      case 'whatsapp':
        return FontAwesomeIcons.whatsapp;
      case 'threads':
        return FontAwesomeIcons.threads;
      case 'youtube':
        return FontAwesomeIcons.youtube;
      case 'snapchat':
        return FontAwesomeIcons.snapchat;
      case 'tiktok':
        return FontAwesomeIcons.tiktok;
      case 'github':
        return FontAwesomeIcons.github;
      case 'yelp':
        return FontAwesomeIcons.yelp;
      case 'venmo':
        return FontAwesomeIcons.moneyBill;
      case 'address':
        return FontAwesomeIcons.locationDot;
      case 'calendly':
        return FontAwesomeIcons.calendarCheck;
      default:
        return FontAwesomeIcons.link;
    }
  }

  void _showAddEditSocialDialog({Map<String, dynamic>? existingLink, int? index, String? platformName}) {
    final isEditing = existingLink != null;
    final platform = isEditing ? existingLink['platform'] as String : (platformName ?? 'LinkedIn');
    final valueController = TextEditingController(text: isEditing ? existingLink['value'] as String : '');
    final labelController = TextEditingController(text: isEditing ? existingLink['label'] as String : (platform == 'Email' ? 'Work' : platform == 'Phone' ? 'Mobile' : platform));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141927),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(
          isEditing ? "Edit $platform Link" : "Add $platform Link",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Value / URL", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: TextField(
                controller: valueController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: platform == 'Email' ? 'example@email.com' : platform == 'Phone' ? '+123456789' : 'https://...',
                  hintStyle: const TextStyle(color: Colors.white24),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text("Label", style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: TextField(
                controller: labelController,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: const InputDecoration(
                  hintText: 'e.g. Work, Personal, Mobile',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          Row(
            children: [
              if (isEditing)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _socialLinks.removeAt(index!);
                    });
                    Navigator.pop(context);
                  },
                  child: const Text("Delete", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (valueController.text.isNotEmpty) {
                    setState(() {
                      if (isEditing) {
                        _socialLinks[index!] = {
                          "platform": platform,
                          "value": valueController.text,
                          "label": labelController.text,
                        };
                      } else {
                        _socialLinks.add({
                          "platform": platform,
                          "value": valueController.text,
                          "label": labelController.text,
                        });
                      }
                    });
                  }
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: EventzoneTheme.primaryAction,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  isEditing ? "Save" : "Add",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: EventzoneTheme.backgroundStart,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
              )
            : null,
        title: const Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: EventzoneTheme.primaryAction),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _saveProfile,
                  child: const Text("Save", style: TextStyle(color: EventzoneTheme.primaryAction, fontWeight: FontWeight.bold)),
                ),
        ],
      ),
      body: EventzoneTheme.buildPlayfulBackground(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: EventzoneTheme.primaryAction.withOpacity(0.5),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Image(
                            image: _getAvatarProvider(_avatarUrl),
                            fit: BoxFit.cover,
                            width: 100,
                            height: 100,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: EventzoneTheme.primaryAction,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(LucideIcons.pencil, size: 16, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 40),
              _buildSectionTitle("Personal Details"),
              _buildTextField("Full Name", _nameController),
              _buildTextField("Job Title", _jobController),
              _buildTextField("Company", _companyController),
              _buildTextField("Address", _addressController),
              
              const SizedBox(height: 32),
              _buildSectionTitle("Social Links"),
              

              
              const SizedBox(height: 24),
              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Builder(
                  builder: (context) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final itemWidth = (screenWidth - 88 - 40) / 3;
                    return Wrap(
                      spacing: 20,
                      runSpacing: 24,
                      alignment: WrapAlignment.center,
                      children: [
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.phone, "Phone Number")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.envelope, "Email")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.link, "Link")),
                        
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.locationDot, "Address")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.globe, "Company Website")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.linkedinIn, "LinkedIn")),
                        
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.instagram, "Instagram")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.xTwitter, "X")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.calendarCheck, "Calendly")),
                        
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.facebookF, "Facebook")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.threads, "Threads")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.youtube, "YouTube")),
                        
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.whatsapp, "WhatsApp")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.snapchat, "Snapchat")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.tiktok, "TikTok")),
                        
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.github, "GitHub")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.yelp, "Yelp")),
                        SizedBox(width: itemWidth, child: _buildSocialAddButton(FontAwesomeIcons.moneyBill, "Venmo")),
                      ],
                    );
                  },
                ),
              ),
              
              const SizedBox(height: 32),
              _buildSectionTitle("Active Links"),
              

              const SizedBox(height: 16),
              
              if (_socialLinks.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      "No social links added yet.",
                      style: TextStyle(color: Colors.white24, fontSize: 13),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _socialLinks.length,
                  itemBuilder: (context, index) {
                    return _buildActiveLink(_socialLinks[index], index);
                  },
                ),
              
              const SizedBox(height: 200),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold)),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white10)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: EventzoneTheme.primaryAction)),
              contentPadding: EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialAddButton(IconData icon, String platform) {
    return GestureDetector(
      onTap: () => _showAddEditSocialDialog(platformName: platform),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: EventzoneTheme.primaryAction,
              shape: BoxShape.circle,
            ),
            child: FaIcon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            platform,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveLink(Map<String, dynamic> link, int index) {
    final platform = link['platform'] as String;
    final value = link['value'] as String;
    final label = link['label'] as String;
    final icon = _getPlatformIcon(platform);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _showAddEditSocialDialog(existingLink: link, index: index),
        child: GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: EventzoneTheme.primaryAction.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FaIcon(icon, color: EventzoneTheme.primaryAction, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      label,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(LucideIcons.gripVertical, color: Colors.white10, size: 18),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _socialLinks.removeAt(index);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: const Icon(LucideIcons.x, color: Colors.white24, size: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
