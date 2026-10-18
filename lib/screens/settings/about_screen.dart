import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../../../theme/eventzone_theme.dart';
import '../../../widgets/glass_container.dart';
import 'package:easy_localization/easy_localization.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
      });
    }
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link'.tr())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: EventzoneTheme.backgroundStart,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(LucideIcons.arrowLeft, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('About Eventzone'.tr(), style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
            child: Column(
              children: [
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: EventzoneTheme.primaryAction.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24),
                Text(
                  'Eventzone'.tr(),
                  style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1),
                ),
                SizedBox(height: 8),
                Text(
                  'Where professionals connect'.tr(),
                  style: TextStyle(color: EventzoneTheme.primaryAction, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 40),
                GlassContainer(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Eventzone is a premium networking app built for professionals who mean business. Whether you're at a conference, a trade show, or an industry meetup — Eventzone turns every room you walk into an opportunity.".tr(),
                        style: TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 32),
                      Divider(color: Colors.white10),
                      SizedBox(height: 16),
                      _buildInfoRow('Version'.tr(), _version.isEmpty ? 'Loading...'.tr() : _version),
                      SizedBox(height: 12),
                      _buildInfoRow('Company'.tr(), 'SPASU Eventzone'),
                      SizedBox(height: 12),
                      _buildInfoRow('Contact'.tr(), 'contact@eventzone.pro'),
                    ],
                  ),
                ),
                SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: FaIcon(FontAwesomeIcons.globe, color: Colors.white54),
                      onPressed: () => _launchUrl('https://eventzone.pro/landing'),
                    ),
                    SizedBox(width: 16),
                    IconButton(
                      icon: FaIcon(FontAwesomeIcons.linkedinIn, color: Colors.white54),
                      onPressed: () => _launchUrl('https://dz.linkedin.com/company/spasu-eventzone'),
                    ),
                    SizedBox(width: 16),
                    IconButton(
                      icon: FaIcon(FontAwesomeIcons.instagram, color: Colors.white54),
                      onPressed: () => _launchUrl('https://www.instagram.com/eventzone.pro/'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.white54, fontSize: 14)),
        Text(value, style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
