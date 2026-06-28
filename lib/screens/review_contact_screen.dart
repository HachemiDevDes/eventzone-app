import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'my_network_screen.dart';

class ReviewContactScreen extends StatefulWidget {
  final String initialName;
  final String initialTitle;
  final String initialEmail;
  final String initialPhone;
  final String initialWebsite;
  final String initialCompany;
  final String initialDepartment;
  final String initialAddress;
  final String source;

  const ReviewContactScreen({
    super.key,
    required this.initialName,
    required this.initialTitle,
    required this.initialEmail,
    required this.initialPhone,
    required this.initialWebsite,
    required this.initialCompany,
    required this.initialDepartment,
    required this.initialAddress,
    required this.source,
  });

  @override
  State<ReviewContactScreen> createState() => _ReviewContactScreenState();
}

class _ReviewContactScreenState extends State<ReviewContactScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _titleController;
  late TextEditingController _companyController;
  late TextEditingController _departmentController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _websiteController;
  late TextEditingController _addressController;
  late TextEditingController _notesController;

  File? _selectedImage;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _titleController = TextEditingController(text: widget.initialTitle);
    _companyController = TextEditingController(text: widget.initialCompany);
    _departmentController = TextEditingController(text: widget.initialDepartment);
    _emailController = TextEditingController(text: widget.initialEmail);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _websiteController = TextEditingController(text: widget.initialWebsite);
    _addressController = TextEditingController(text: widget.initialAddress);
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _titleController.dispose();
    _companyController.dispose();
    _departmentController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _websiteController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1322),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.camera, color: Colors.white70),
                title: const Text("Take Photo", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
                  if (file != null) {
                    setState(() => _selectedImage = File(file.path));
                  }
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.image, color: Colors.white70),
                title: const Text("Choose from Gallery", style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
                  if (file != null) {
                    setState(() => _selectedImage = File(file.path));
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserId = currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";

      String avatarUrl = "";

      if (_selectedImage != null) {
        try {
          final fileName = "${DateTime.now().millisecondsSinceEpoch}_avatar.jpg";
          await Supabase.instance.client.storage
              .from('avatars')
              .upload(fileName, _selectedImage!);
          avatarUrl = Supabase.instance.client.storage
              .from('avatars')
              .getPublicUrl(fileName);
        } catch (e) {
          avatarUrl = _selectedImage!.path;
        }
      }

      final newConnection = {
        'user_id': currentUserId,
        'name': _nameController.text.trim(),
        'title': _titleController.text.trim(),
        'company': _companyController.text.trim(),
        'department': _departmentController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'website': _websiteController.text.trim(),
        'address': _addressController.text.trim(),
        'notes': _notesController.text.trim(),
        'avatar_url': avatarUrl,
        'source': widget.source,
        'is_new': true,
      };

      await Supabase.instance.client.from('connections').insert(newConnection);

      MyNetworkScreen.customConnections.add({
        "name": _nameController.text.trim(),
        "title": _titleController.text.trim(),
        "avatarUrl": avatarUrl,
        "source": widget.source,
        "isNew": "true",
        "email": _emailController.text.trim(),
        "phone": _phoneController.text.trim(),
        "website": _websiteController.text.trim(),
        "address": _addressController.text.trim(),
        "company": _companyController.text.trim(),
        "department": _departmentController.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Successfully saved ${_nameController.text.trim()}!"),
            backgroundColor: EventzoneTheme.accentSuccess,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving contact: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060913),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060913),
        elevation: 0,
        title: const Text("Review Scanned Contact", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(LucideIcons.x, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                           CircleAvatar(
                            radius: 54,
                            backgroundColor: Colors.white10,
                            backgroundImage: _selectedImage != null
                                ? FileImage(_selectedImage!)
                                : null,
                            child: _selectedImage == null
                                ? const Icon(LucideIcons.user, size: 48, color: Colors.white54)
                                : null,
                          ),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: EventzoneTheme.primaryAction,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(LucideIcons.camera, size: 16, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    _buildSectionHeader("Contact Info"),
                    const SizedBox(height: 8),
                    _buildTextField("Full Name", _nameController, LucideIcons.user, validator: (v) {
                      if (v == null || v.trim().isEmpty) return "Name is required";
                      return null;
                    }),
                    _buildTextField("Job Title", _titleController, LucideIcons.briefcase, validator: (v) {
                      if (v == null || v.trim().isEmpty) return "Job title is required";
                      return null;
                    }),
                    _buildTextField("Company", _companyController, LucideIcons.building2),
                    _buildTextField("Department", _departmentController, LucideIcons.layers),
                    _buildTextField("Email Address", _emailController, LucideIcons.mail, keyboardType: TextInputType.emailAddress),
                    _buildTextField("Phone Number", _phoneController, LucideIcons.phone, keyboardType: TextInputType.phone),
                    _buildTextField("Website", _websiteController, LucideIcons.globe, keyboardType: TextInputType.url),
                    _buildTextField("Address", _addressController, LucideIcons.mapPin),
                    
                    const SizedBox(height: 16),
                    _buildSectionHeader("Notes & Tags"),
                    const SizedBox(height: 8),
                    _buildTextField("Reminder Notes", _notesController, LucideIcons.fileText, maxLines: 3),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Color(0xFF090C16),
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveContact,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EventzoneTheme.primaryAction,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            "Save Contact",
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            icon: Icon(icon, color: Colors.white54, size: 18),
            labelText: label,
            labelStyle: const TextStyle(color: Colors.white30, fontSize: 13),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ),
    );
  }
}
