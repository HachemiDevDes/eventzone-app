import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'my_network_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddContactScreen extends StatefulWidget {
  const AddContactScreen({super.key});

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _companyController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _linkController = TextEditingController();
  final _jobTitleController = TextEditingController();
  final _addressController = TextEditingController();

  bool _showPhone = false;
  bool _showEmail = false;
  bool _showLink = false;
  bool _showJobTitle = false;
  bool _showAddress = false;

  void _createAndEnrich() {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final company = _companyController.text.trim();

    if (firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("First name is required!"),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final fullName = "$firstName $lastName".trim();
    final jobTitle = _showJobTitle && _jobTitleController.text.trim().isNotEmpty
        ? _jobTitleController.text.trim()
        : "";
    final companyName = company.isNotEmpty ? company : "";

    // Dynamic metadata from the optional fields
    final Map<String, dynamic> extraMetadata = {};
    if (_showPhone && _phoneController.text.trim().isNotEmpty) {
      extraMetadata['phone'] = _phoneController.text.trim();
    }
    if (_showEmail && _emailController.text.trim().isNotEmpty) {
      extraMetadata['email'] = _emailController.text.trim();
    }
    if (_showLink && _linkController.text.trim().isNotEmpty) {
      extraMetadata['link'] = _linkController.text.trim();
    }

    final addressVal = _showAddress ? _addressController.text.trim() : "";

    // Add to MyNetworkScreen's custom connections
    MyNetworkScreen.customConnections.add({
      "name": fullName,
      "title": "$jobTitle at $companyName",
      "avatarUrl": "https://i.pravatar.cc/150?u=m${MyNetworkScreen.customConnections.length}",
      "source": "Manual Entry",
      "isNew": "true",
      "email": _showEmail ? _emailController.text.trim() : "",
      "phone": _showPhone ? _phoneController.text.trim() : "",
      "website": _showLink ? _linkController.text.trim() : "",
      "address": addressVal,
      "company": companyName,
    });

    // Save to Supabase connections table
    _saveToSupabase(fullName, "$jobTitle at $companyName", addressVal);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Created $fullName!"),
        backgroundColor: EventzoneTheme.accentSuccess,
      ),
    );

    // Pop back to network screen
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _saveToSupabase(String name, String title, String address) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserId = currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
      await Supabase.instance.client.from('connections').insert({
        'user_id': currentUserId,
        'name': name,
        'title': title,
        'avatar_url': "https://i.pravatar.cc/150?u=m${name.hashCode}",
        'source': 'Manual Entry',
        'is_new': true,
        'email': _showEmail ? _emailController.text.trim() : "",
        'phone': _showPhone ? _phoneController.text.trim() : "",
        'website': _showLink ? _linkController.text.trim() : "",
        'address': address,
        'company': _companyController.text.trim(),
      });
    } catch (e) {
      print("Error saving manual connection to Supabase: $e");
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: const TextStyle(color: Colors.white38),
          filled: true,
          fillColor: Colors.white.withOpacity(0.02),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white10),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EventzoneTheme.primaryAction, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildDetailChip(String label, bool isShown, VoidCallback onTap) {
    if (isShown) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.plus, size: 14, color: Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EventzoneTheme.backgroundEnd,
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Header Row (Matches design)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(LucideIcons.x, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Text(
                      "New contact",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(LucideIcons.scan, size: 14, color: Colors.white),
                      label: const Text("Scan", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        backgroundColor: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ),

              // Form fields scrollable area
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              controller: _firstNameController,
                              labelText: "First name",
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTextField(
                              controller: _lastNameController,
                              labelText: "Last name",
                            ),
                          ),
                        ],
                      ),

                      // Company field
                      _buildTextField(
                        controller: _companyController,
                        labelText: "Company",
                      ),

                      // Dynamic Fields based on user chips choices
                      if (_showJobTitle)
                        _buildTextField(
                          controller: _jobTitleController,
                          labelText: "Job Title",
                        ),
                      if (_showPhone)
                        _buildTextField(
                          controller: _phoneController,
                          labelText: "Phone",
                          keyboardType: TextInputType.phone,
                        ),
                      if (_showEmail)
                        _buildTextField(
                          controller: _emailController,
                          labelText: "Email",
                          keyboardType: TextInputType.emailAddress,
                        ),
                       if (_showLink)
                        _buildTextField(
                          controller: _linkController,
                          labelText: "Link",
                          keyboardType: TextInputType.url,
                        ),
                      if (_showAddress)
                        _buildTextField(
                          controller: _addressController,
                          labelText: "Address",
                        ),

                      const SizedBox(height: 16),
                      const Text(
                        "Add more details",
                        style: TextStyle(
                          color: Colors.white38,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Chips row (Wrap layout)
                      Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: [
                          _buildDetailChip("Phone", _showPhone, () {
                            setState(() => _showPhone = true);
                          }),
                          _buildDetailChip("Email", _showEmail, () {
                            setState(() => _showEmail = true);
                          }),
                          _buildDetailChip("Link", _showLink, () {
                            setState(() => _showLink = true);
                          }),
                          _buildDetailChip("Job Title", _showJobTitle, () {
                            setState(() => _showJobTitle = true);
                          }),
                          _buildDetailChip("Address", _showAddress, () {
                            setState(() => _showAddress = true);
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Button (Create & Enrich)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _createAndEnrich,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: const Center(
                      child: Text(
                        "Create",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
