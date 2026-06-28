import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'dart:io';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_detail_screen.dart';

class ProfessionalProfileScreen extends StatefulWidget {
  final String name;
  final String title;
  final String avatarUrl;
  final String? source;
  final String? isNew;
  final String? email;
  final String? phone;
  final String? website;
  final String? company;
  final String? department;
  final String? notes;
  final String? address;
  final List<String>? tags;
  final String? connectionId;

  const ProfessionalProfileScreen({
    super.key,
    required this.name,
    required this.title,
    required this.avatarUrl,
    this.source,
    this.isNew,
    this.email,
    this.phone,
    this.website,
    this.company,
    this.department,
    this.notes,
    this.address,
    this.tags,
    this.connectionId,
  });

  @override
  State<ProfessionalProfileScreen> createState() => _ProfessionalProfileScreenState();
}

class _ProfessionalProfileScreenState extends State<ProfessionalProfileScreen> {
  late String _notes;
  late List<String> _tags;
  late String _email;
  late String _phone;
  late String _website;
  late String _company;
  late String _department;
  late String _address;
  late String _name;
  late String _title;

  @override
  void initState() {
    super.initState();
    _notes = widget.notes ?? "";
    _tags = widget.tags ?? [];
    _email = widget.email ?? "";
    _phone = widget.phone ?? "";
    _website = widget.website ?? "";
    _company = widget.company ?? "";
    _department = widget.department ?? "";
    _address = widget.address ?? "";
    _name = widget.name;
    _title = widget.title;
  }

  Future<void> _updateFieldInSupabase(String column, dynamic value) async {
    if (widget.connectionId == null) return;
    try {
      await Supabase.instance.client
          .from('connections')
          .update({column: value})
          .eq('id', widget.connectionId!);
    } catch (e) {
      print("Error updating $column: $e");
    }
  }

  void _showAddTagDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F1322),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text("Add Tag", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: textController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Enter tag name",
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                final tag = textController.text.trim();
                if (tag.isNotEmpty) {
                  setState(() {
                    _tags.add(tag);
                  });
                  _updateFieldInSupabase('tags', _tags);
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: EventzoneTheme.primaryAction,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Add", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showAddNoteDialog() {
    final textController = TextEditingController(text: _notes);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0F1322),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text("Connection Note", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: TextField(
            controller: textController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Write down a memorable reminder...",
              hintStyle: const TextStyle(color: Colors.white24),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                final note = textController.text.trim();
                setState(() {
                  _notes = note;
                });
                _updateFieldInSupabase('notes', note);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: EventzoneTheme.primaryAction,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Save", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showEditProfileDialog() {
    final nameCtrl = TextEditingController(text: _name);
    final titleCtrl = TextEditingController(text: _title);
    final companyCtrl = TextEditingController(text: _company);
    final deptCtrl = TextEditingController(text: _department);
    final emailCtrl = TextEditingController(text: _email);
    final phoneCtrl = TextEditingController(text: _phone);
    final webCtrl = TextEditingController(text: _website);
    final addressCtrl = TextEditingController(text: _address);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C0F1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Edit Connection Details", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildField("Name", nameCtrl),
                _buildField("Job Title", titleCtrl),
                _buildField("Company", companyCtrl),
                _buildField("Department", deptCtrl),
                _buildField("Email", emailCtrl),
                _buildField("Phone", phoneCtrl),
                _buildField("Website", webCtrl),
                _buildField("Address", addressCtrl),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _name = nameCtrl.text.trim();
                        _title = titleCtrl.text.trim();
                        _company = companyCtrl.text.trim();
                        _department = deptCtrl.text.trim();
                        _email = emailCtrl.text.trim();
                        _phone = phoneCtrl.text.trim();
                        _website = webCtrl.text.trim();
                        _address = addressCtrl.text.trim();
                      });
                      if (widget.connectionId != null) {
                        Supabase.instance.client.from('connections').update({
                          'name': _name,
                          'title': _title,
                          'company': _company,
                          'department': _department,
                          'email': _email,
                          'phone': _phone,
                          'website': _website,
                          'address': _address,
                        }).eq('id', widget.connectionId!).then((_) {});
                      }
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EventzoneTheme.primaryAction,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("Save Changes", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white10,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F1322),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.trash2, color: Colors.redAccent),
                title: const Text("Delete Connection", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteConnection();
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.share2, color: Colors.white),
                title: const Text("Share Connection", style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Connection details copied to clipboard!")),
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _confirmDeleteConnection() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF0B0F19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white10),
          ),
          title: const Text("Delete Contact", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text(
            "Are you sure you want to delete $_name from your contacts?",
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel", style: TextStyle(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  if (widget.connectionId != null) {
                    await Supabase.instance.client
                        .from('connections')
                        .delete()
                        .eq('id', widget.connectionId!);
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Deleted $_name!"),
                      backgroundColor: Colors.redAccent,
                    ),
                  );
                  Navigator.pop(context); // Go back to Network list
                } catch (e) {
                  print("Error deleting: $e");
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Delete", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060913),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Large Profile Image Header
                  Stack(
                    children: [
                      Container(
                        height: 320,
                        width: double.infinity,
                        color: const Color(0xFF0F1322),
                        child: widget.avatarUrl.isEmpty
                            ? const Center(
                                child: Icon(
                                  LucideIcons.user,
                                  size: 100,
                                  color: Colors.white24,
                                ),
                              )
                            : Image(
                                image: widget.avatarUrl.startsWith('http')
                                    ? NetworkImage(widget.avatarUrl)
                                    : FileImage(File(widget.avatarUrl)) as ImageProvider,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Container(
                        height: 320,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black54,
                              Colors.transparent,
                              Color(0xFF060913),
                            ],
                          ),
                        ),
                      ),
                      // Top Buttons Overlays
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.black45,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(color: Colors.white10),
                                  ),
                                  child: const Icon(LucideIcons.chevronLeft, color: Colors.white, size: 20),
                                ),
                              ),
                               Row(
                                children: [
                                  GestureDetector(
                                    onTap: _showEditProfileDialog,
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: const Icon(LucideIcons.edit3, color: Colors.white, size: 18),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _confirmDeleteConnection,
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: Colors.white10),
                                      ),
                                      child: const Icon(LucideIcons.trash2, color: Colors.redAccent, size: 18),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // 2. Name and Job details section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _name,
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                            ),
                            if (widget.isNew == 'true') ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: EventzoneTheme.primaryAction.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: EventzoneTheme.primaryAction.withOpacity(0.4)),
                                ),
                                child: const Text(
                                  "NEW",
                                  style: TextStyle(color: EventzoneTheme.primaryAction, fontSize: 8, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _title,
                          style: const TextStyle(fontSize: 15, color: Colors.white70, fontWeight: FontWeight.w500),
                        ),
                        if (_department.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _department,
                            style: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w400),
                          ),
                        ],
                        if (_company.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            _company,
                            style: const TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w400),
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ChatDetailScreen(
                                        contactName: _name,
                                        avatarUrl: widget.avatarUrl,
                                        recipientEmail: _email,
                                        recipientId: widget.connectionId,
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(LucideIcons.messageSquare, size: 16),
                                label: const Text("Message", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: EventzoneTheme.primaryAction,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        // Tags Wrap
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._tags.map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(tag, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                            )),
                            GestureDetector(
                              onTap: _showAddTagDialog,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: EventzoneTheme.primaryAction.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: EventzoneTheme.primaryAction.withOpacity(0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.plus, color: EventzoneTheme.primaryAction, size: 12),
                                    SizedBox(width: 4),
                                    Text("Add tag", style: TextStyle(color: EventzoneTheme.primaryAction, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 24),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 16),

                        // 3. Connection Details
                        const Text("Connection details", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(LucideIcons.calendar, color: Colors.white38, size: 16),
                            const SizedBox(width: 10),
                            const Text("08 February 2026 4:53 PM", style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF0D0F19),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: const BorderSide(color: Colors.white10),
                                ),
                                title: Text("$_name's Card", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GlassContainer(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                          Text(_title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                          if (_company.isNotEmpty) Text(_company, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                                          const SizedBox(height: 16),
                                          if (_email.isNotEmpty) Text("Email: $_email", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                          if (_phone.isNotEmpty) Text("Phone: $_phone", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                          if (_website.isNotEmpty) Text("Web: $_website", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                          if (_address.isNotEmpty) Text("Address: $_address", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                          child: const Text("View card", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                        
                        const SizedBox(height: 24),
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 16),

                        // 4. Contact Info List Rows
                        if (_email.isNotEmpty) ...[
                          _buildContactRow(LucideIcons.mail, _email, "Work"),
                          const SizedBox(height: 12),
                        ],
                        if (_phone.isNotEmpty) ...[
                          _buildContactRow(LucideIcons.phone, _phone, "Cell"),
                          const SizedBox(height: 12),
                        ],
                        if (_website.isNotEmpty) ...[
                          _buildContactRow(LucideIcons.globe, _website, "Website"),
                          const SizedBox(height: 12),
                        ],
                        if (_address.isNotEmpty) ...[
                          _buildContactRow(LucideIcons.mapPin, _address, "Address"),
                          const SizedBox(height: 24),
                        ],
                        
                        const Divider(color: Colors.white10),
                        const SizedBox(height: 16),

                        // 5. Notes Section
                        const Text("Notes", style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        const SizedBox(height: 12),
                        if (_notes.isEmpty) ...[
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16.0),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Icon(LucideIcons.fileText, color: Colors.white30, size: 24),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "Write down a memorable reminder about\nyour contact",
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          GlassContainer(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _notes,
                              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                            ),
                          ),
                        ],
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // 6. Bottom Sticky Actions Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF090C16),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton(
                      onPressed: _showMoreMenu,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("More...", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: _showAddTagDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF131726),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Add tag", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      onPressed: _showAddNoteDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF131726),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.white10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("Add note", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactRow(IconData icon, String value, String type) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white70, size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  type,
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
