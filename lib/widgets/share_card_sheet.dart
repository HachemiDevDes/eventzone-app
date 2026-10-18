import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../theme/eventzone_theme.dart';

/// A sleek, glassmorphic bottom sheet that allows users to either copy
/// their digital profile link or download their QR code as a high-quality PNG.
class ShareCardSheet extends StatefulWidget {
  final String qrData;
  final String fullName;

  const ShareCardSheet({
    super.key,
    required this.qrData,
    required this.fullName,
  });

  /// Displays the modal bottom sheet with a glassy backdrop.
  static Future<void> show(
    BuildContext context, {
    required String qrData,
    required String fullName,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => ShareCardSheet(
        qrData: qrData,
        fullName: fullName,
      ),
    );
  }

  @override
  State<ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<ShareCardSheet> {
  bool _isDownloading = false;

  void _copyLink() {
    Clipboard.setData(ClipboardData(text: widget.qrData));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          "Profile link copied to clipboard!".tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: EventzoneTheme.primaryAction,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _downloadQrCode() async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      // 1. Generate ultra-crisp 1024x1024 PNG with pure white background & quiet zone
      const double size = 1024.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // White solid background
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(const Rect.fromLTWH(0, 0, size, size), bgPaint);

      // 8% quiet zone border on all sides for optimal scanner readability
      const padding = size * 0.08;
      const qrSize = size - (padding * 2);

      final painter = QrPainter(
        data: widget.qrData,
        version: QrVersions.auto,
        gapless: true,
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Color(0xFF0B0F19),
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Color(0xFF0B0F19),
        ),
      );

      canvas.save();
      canvas.translate(padding, padding);
      painter.paint(canvas, const Size(qrSize, qrSize));
      canvas.restore();

      final picture = recorder.endRecording();
      final image = await picture.toImage(size.toInt(), size.toInt());
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      // 2. Save PNG to application temporary directory
      final tempDir = await getTemporaryDirectory();
      final sanitizedName = widget.fullName
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final fileName = 'eventzone_qr_${sanitizedName.isEmpty ? "profile" : sanitizedName}.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);

      // 3. On Android, also save a copy directly to public Downloads folder if available
      if (Platform.isAndroid) {
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            final downloadFile = File('${downloadDir.path}/$fileName');
            await downloadFile.writeAsBytes(pngBytes);
          }
        } catch (e) {
          debugPrint('Could not copy directly to /Download: $e');
        }
      }

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "QR code saved! Opening share options...".tr(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: EventzoneTheme.accentSuccess,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );

      // 4. Open native share/save sheet so user can save to photos, device storage, or send
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'My Eventzone Profile QR Code',
        subject: 'Eventzone QR Code - ${widget.fullName}',
      );
    } catch (e) {
      debugPrint('Error generating or downloading QR code: $e');
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to download QR code: $e"),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F1420).withValues(alpha: 0.96),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: EventzoneTheme.glassBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            spreadRadius: 8,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 22),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title & Subtitle
              Text(
                "Share Your Card".tr(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "Choose how you want to share your digital badge.".tr(),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.55),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 24),

              // Option 1: Copy Profile Link
              _buildActionTile(
                icon: LucideIcons.copy,
                iconColor: EventzoneTheme.primaryAction,
                title: "Copy Profile Link".tr(),
                subtitle: widget.qrData.replaceFirst(RegExp(r'^https?:\/\/'), ''),
                onTap: _copyLink,
              ),
              const SizedBox(height: 12),

              // Option 2: Download QR Code (High-Quality PNG)
              _buildActionTile(
                icon: LucideIcons.download,
                iconColor: EventzoneTheme.accentSuccess,
                title: "Download QR Code".tr(),
                subtitle: "High-resolution PNG (1024 × 1024)".tr(),
                isLoading: _isDownloading,
                onTap: _downloadQrCode,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(icon, color: iconColor, size: 20),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                  ),
                )
              else
                Icon(
                  LucideIcons.chevronRight,
                  size: 16,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
