import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'add_contact_screen.dart';
import '../widgets/subscription_expired_bottom_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:google_mlkit_language_id/google_mlkit_language_id.dart';
import 'package:image_picker/image_picker.dart';
import 'review_contact_screen.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:camerawesome/pigeon.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'professional_profile_screen.dart';
import '../services/business_card_scanner_service.dart';
import '../services/notification_service.dart';
import '../widgets/connection_success_dialog.dart';
import 'package:permission_handler/permission_handler.dart';


// Top-level function for Isolate to prevent UI freezing during heavy image manipulation
Future<Map<String, dynamic>> _processImageInIsolate(Map<String, dynamic> args) async {
  final String path = args['path'];
  final bool isCameraCapture = args['isCameraCapture'];
  final double screenWidth = args['screenWidth'];
  final double screenHeight = args['screenHeight'];
  final double frameW = args['frameW'];
  final double frameH = args['frameH'];

  final Uint8List imageBytes = await File(path).readAsBytes();
  img.Image? fullImage = img.decodeImage(imageBytes);
  if (fullImage == null) throw Exception("Failed to decode image");
  
  String ocrImagePath = path;
  int imageWidth = fullImage.width;
  int imageHeight = fullImage.height;
  int cropWidth = imageWidth;
  int cropHeight = imageHeight;

  if (!isCameraCapture) {
    if (fullImage.width > 1200) {
      fullImage = img.copyResize(fullImage, width: 1200);
    }
    img.grayscale(fullImage);
    img.adjustColor(fullImage, contrast: 1.2);
    
    final String enhancedPath = '${path}_enhanced.jpg';
    await File(enhancedPath).writeAsBytes(img.encodeJpg(fullImage, quality: 95));
    ocrImagePath = enhancedPath;
  } else {
    final double frameLeft = (screenWidth - frameW) / 2;
    final double frameTop = (screenHeight - frameH) / 2 - 50;

    final double scale = math.max(
      screenWidth / imageWidth,
      screenHeight / imageHeight,
    );
    final double dx = (screenWidth - imageWidth * scale) / 2;
    final double dy = (screenHeight - imageHeight * scale) / 2;

    final double rawLeft = (frameLeft - dx) / scale;
    final double rawTop = (frameTop - dy) / scale;
    final double rawRight = (frameLeft + frameW - dx) / scale;
    final double rawBottom = (frameTop + frameH - dy) / scale;
    final double padX = (rawRight - rawLeft) * 0.15;
    final double padY = (rawBottom - rawTop) * 0.15;

    final int cropX = (rawLeft - padX).clamp(0, imageWidth - 1).toInt();
    final int cropY = (rawTop - padY).clamp(0, imageHeight - 1).toInt();
    cropWidth = ((rawRight - rawLeft) + padX * 2).clamp(1, imageWidth - cropX).toInt();
    cropHeight = ((rawBottom - rawTop) + padY * 2).clamp(1, imageHeight - cropY).toInt();

    final img.Image cropped = img.copyCrop(
      fullImage,
      x: cropX,
      y: cropY,
      width: cropWidth,
      height: cropHeight,
    );

    final String croppedPath = '${path}_cropped.jpg';
    final img.Image gray = img.grayscale(cropped);
    img.adjustColor(gray, contrast: 1.4, brightness: 1.05);
    await File(croppedPath).writeAsBytes(img.encodeJpg(gray, quality: 100));
    ocrImagePath = croppedPath;
  }

  return {
    'ocrImagePath': ocrImagePath,
    'cropWidth': cropWidth,
    'cropHeight': cropHeight,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
  };
}

/// Isolate function to cleanly crop the business card to the viewfinder frame
Future<String> _cropCardImageInIsolate(Map<String, dynamic> args) async {
  final String path = args['path'];
  final double screenWidth = args['screenWidth'];
  final double screenHeight = args['screenHeight'];
  final double frameW = args['frameW'];
  final double frameH = args['frameH'];

  final Uint8List imageBytes = await File(path).readAsBytes();
  img.Image? fullImage = img.decodeImage(imageBytes);
  if (fullImage == null) return path;

  // Orient image properly to match device screen preview
  fullImage = img.bakeOrientation(fullImage);

  // If device is in portrait (screenWidth < screenHeight) but image decoded in landscape, rotate 90° CW
  if (screenWidth < screenHeight && fullImage.width > fullImage.height) {
    fullImage = img.copyRotate(fullImage, angle: 90);
  }

  final double imgW = fullImage.width.toDouble();
  final double imgH = fullImage.height.toDouble();

  // Screen-to-image scale with BoxFit.cover
  final double scale = math.max(
    screenWidth / imgW,
    screenHeight / imgH,
  );
  final double dx = (screenWidth - imgW * scale) / 2;
  final double dy = (screenHeight - imgH * scale) / 2;

  // Viewfinder position on screen (matching build method)
  final double frameLeft = (screenWidth - frameW) / 2;
  final double frameTop = (screenHeight - frameH) / 2 - 50;

  // Convert screen viewfinder box into image coordinates
  final double rawLeft = (frameLeft - dx) / scale;
  final double rawTop = (frameTop - dy) / scale;
  final double rawW = frameW / scale;
  final double rawH = frameH / scale;

  // Generous 25% safety padding on each side to ensure 100% of card borders, edge text,
  // emails, phone numbers, and URLs are never clipped even if held slightly off-center
  final double padX = rawW * 0.25;
  final double padY = rawH * 0.25;

  final int cropX = (rawLeft - padX).clamp(0, imgW - 1).toInt();
  final int cropY = (rawTop - padY).clamp(0, imgH - 1).toInt();
  final int cropW = (rawW + padX * 2).clamp(1, imgW - cropX).toInt();
  final int cropH = (rawH + padY * 2).clamp(1, imgH - cropY).toInt();

  final img.Image cropped = img.copyCrop(
    fullImage,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  final tempDir = Directory.systemTemp;
  final String croppedPath = '${tempDir.path}/card_cropped_${DateTime.now().millisecondsSinceEpoch}.jpg';
  await File(croppedPath).writeAsBytes(img.encodeJpg(cropped, quality: 95));

  // Remove the uncropped raw camera photo
  try {
    await File(path).delete();
  } catch (_) {}

  return croppedPath;
}

class ScanQRScreen extends StatefulWidget {
  final Map<String, dynamic>? previousScanData;

  const ScanQRScreen({
    super.key,
    this.previousScanData,
  });

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  bool _isConnecting = false;
  late String _scanType; // "QR Code", "Business Card", "Event Badge"
  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  bool _isProcessingBarcode = false;
  bool _isFlashOn = false;
  
  late AnimationController _laserController;
  String _ocrStatus = "";
  double _ocrProgress = 0.0;
  DateTime? _lastErrorTime;
  Rect? _lastTargetRect;

  CameraState? _cameraAwesomeState;
  Timer? _aiStatusTimer;

  // ── Camera Reliability & Lifecycle Management ──
  Key _cameraKey = UniqueKey();
  bool? _hasCameraPermission; // null = checking, true = granted, false = denied
  bool _isPermanentlyDenied = false;
  bool _isReadyToBuildCamera = false;
  bool _isCameraReady = false;
  bool _cameraInitFailed = false;
  int _retryCount = 0;
  Timer? _cameraWatchdogTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanType = widget.previousScanData != null ? "Business Card" : "QR Code";
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initScreen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_isFlashOn && _cameraAwesomeState != null) {
      try {
        _cameraAwesomeState!.sensorConfig.setFlashMode(FlashMode.none);
        _isFlashOn = false;
      } catch (_) {}
    }
    _cameraWatchdogTimer?.cancel();
    _aiStatusTimer?.cancel();
    _barcodeScanner.close();
    _laserController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isFlashOn && _cameraAwesomeState != null) {
        try {
          _cameraAwesomeState!.sensorConfig.setFlashMode(FlashMode.none);
          _isFlashOn = false;
        } catch (_) {}
      }
    } else if (state == AppLifecycleState.resumed) {
      // Re-verify permission and reboot camera if native Android released the hardware in background
      if (mounted && _hasCameraPermission == true && !_isConnecting) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && !_isConnecting) {
            _recoverCamera();
          }
        });
      }
    }
  }

  Future<void> _initScreen() async {
    // 1. Check and request camera permission proactively before mounting CameraAwesome
    await _checkAndRequestCameraPermission(requestIfNeeded: true);

    // 2. Allow a short 150ms settling window for Android route transition and any previous camera unbind
    await Future.delayed(const Duration(milliseconds: 150));

    if (mounted) {
      setState(() {
        _isReadyToBuildCamera = true;
      });
      if (_hasCameraPermission == true) {
        _startCameraWatchdog();
      }
    }
  }

  Future<void> _checkAndRequestCameraPermission({bool requestIfNeeded = true}) async {
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted && requestIfNeeded) {
        status = await Permission.camera.request();
      }
      if (mounted) {
        setState(() {
          _hasCameraPermission = status.isGranted;
          _isPermanentlyDenied = status.isPermanentlyDenied;
        });
      }
    } catch (e) {
      debugPrint("Error checking camera permission: $e");
      if (mounted) {
        setState(() {
          _hasCameraPermission = true;
        });
      }
    }
  }

  void _startCameraWatchdog() {
    _cameraWatchdogTimer?.cancel();
    _cameraWatchdogTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      if (!_isCameraReady) {
        debugPrint("Camera watchdog: camera did not initialize within 3.5s. Attempting recovery...");
        if (_retryCount < 2) {
          _retryCount++;
          _recoverCamera();
        } else {
          setState(() {
            _cameraInitFailed = true;
          });
        }
      }
    });
  }

  void _recoverCamera() {
    _cameraWatchdogTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _isCameraReady = false;
      _cameraInitFailed = false;
      _cameraAwesomeState = null;
      _cameraKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
    });
    _startCameraWatchdog();
  }

  Future<void> _restartCameraManual() async {
    _cameraWatchdogTimer?.cancel();
    setState(() {
      _retryCount = 0;
      _cameraInitFailed = false;
      _isCameraReady = false;
      _cameraAwesomeState = null;
    });
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) {
      await _checkAndRequestCameraPermission(requestIfNeeded: true);
      if (_hasCameraPermission == true) {
        setState(() {
          _cameraKey = ValueKey(DateTime.now().millisecondsSinceEpoch);
        });
        _startCameraWatchdog();
      }
    }
  }

  void _onCameraStateReceived(CameraState cameraState) {
    _cameraAwesomeState = cameraState;
    if (cameraState is! PreparingCameraState) {
      if (!_isCameraReady) {
        _cameraWatchdogTimer?.cancel();
        try {
          CamerawesomePlugin.startAutoFocus();
        } catch (_) {}
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isCameraReady = true;
              _cameraInitFailed = false;
              _retryCount = 0;
            });
          }
        });
      }
    }
  }



  String? _extractUuid(String data) {
    final RegExp uuidRegExp = RegExp(
      r'[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}',
    );
    final match = uuidRegExp.firstMatch(data);
    return match?.group(0);
  }

  void _handleQRData(String rawValue) {
    if (_isConnecting) return;
    if (_scanType != "QR Code") return;

    if (_scanType == "QR Code") {
      // Validate if it is a valid Eventzone QR profile (must contain a UUID)
      final uuid = _extractUuid(rawValue);
      
      if (uuid == null) {
        final now = DateTime.now();
        if (_lastErrorTime == null || now.difference(_lastErrorTime!) > const Duration(seconds: 3)) {
          _lastErrorTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("scan_qr_error_invalid_code".tr()),
              backgroundColor: Colors.redAccent,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }
    }
    
    _processScanData(rawValue);
  }

  Future<void> _processAnalysisImage(AnalysisImage image) async {
    if (_scanType != "QR Code" || _isConnecting || _isProcessingBarcode) return;
    _isProcessingBarcode = true;
    
    try {
      final Size size = image.size;
      
      InputImageRotation imageRotation = InputImageRotation.rotation0deg;
      switch (image.rotation) {
        case InputAnalysisImageRotation.rotation90deg:
          imageRotation = InputImageRotation.rotation90deg;
          break;
        case InputAnalysisImageRotation.rotation180deg:
          imageRotation = InputImageRotation.rotation180deg;
          break;
        case InputAnalysisImageRotation.rotation270deg:
          imageRotation = InputImageRotation.rotation270deg;
          break;
        default:
          imageRotation = InputImageRotation.rotation0deg;
          break;
      }
      
      InputImage? inputImage;

      image.when(
        nv21: (Nv21Image nv21) {
          final metadata = InputImageMetadata(
            size: size,
            rotation: imageRotation,
            format: InputImageFormat.nv21,
            bytesPerRow: nv21.planes.first.bytesPerRow,
          );
          inputImage = InputImage.fromBytes(bytes: nv21.bytes, metadata: metadata);
          return null;
        },
        bgra8888: (Bgra8888Image bgra) {
          final metadata = InputImageMetadata(
            size: size,
            rotation: imageRotation,
            format: InputImageFormat.bgra8888,
            bytesPerRow: bgra.planes.first.bytesPerRow,
          );
          inputImage = InputImage.fromBytes(bytes: bgra.bytes, metadata: metadata);
          return null;
        },
        yuv420: (Yuv420Image yuv) => null,
        jpeg: (JpegImage jpeg) => null,
      );
      
      if (inputImage == null) {
        _isProcessingBarcode = false;
        return;
      }
      
      final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage!);
      if (barcodes.isNotEmpty) {
        final rawValue = barcodes.first.rawValue;
        if (rawValue != null && rawValue.isNotEmpty) {
           _handleQRData(rawValue);
        }
      }
    } catch (e) {
      debugPrint('Barcode scanning error: $e');
    } finally {
      if (mounted) _isProcessingBarcode = false;
    }
  }

  Future<void> _processScanData(String data) async {
    if (_isConnecting) return;
    
    setState(() {
      _isConnecting = true;
      _ocrStatus = "scan_qr_detecting_alignment".tr();
      _ocrProgress = 0.1;
    });
    
    _laserController.repeat(reverse: true);

    String name = "";
    String title = "";
    String avatarUrl = "";
    String? email;
    String? phone;
    String? website;
    String? company;
    String? department;
    Map<String, dynamic>? scannedProfile;
    
    final uuid = _extractUuid(data);
    
    // Check if it is a UUID (Eventzone Profile)
    if (uuid != null) {
      setState(() {
        _ocrStatus = "scan_qr_fetching_profile".tr();
        _ocrProgress = 0.4;
      });
      
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', uuid)
            .maybeSingle();
            
        if (profile != null) {
          scannedProfile = profile;
          final currentUserId = Supabase.instance.client.auth.currentUser?.id;
          
          if (currentUserId == uuid) {
            _laserController.stop();
            setState(() => _isConnecting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("scan_qr_error_connect_self".tr()),
                backgroundColor: Colors.redAccent,
              ),
            );
            return;
          }
          
          if (currentUserId != null) {
            final existingConn = await Supabase.instance.client
                .from('connections')
                .select('id')
                .eq('user_id', currentUserId)
                .eq('linked_profile_id', uuid)
                .maybeSingle();
                
            if (existingConn != null) {
              _laserController.stop();
              setState(() => _isConnecting = false);
              final String existingName = profile["full_name"] ?? "this user";
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("scan_qr_error_already_connected".tr(args: [existingName])),
                  backgroundColor: const Color(0xFFEAB308), // Yellow warning
                ),
              );
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfessionalProfileScreen(
                    name: profile["full_name"] ?? "scan_qr_eventzone_user".tr(),
                    title: profile["job_title"] ?? "",
                    avatarUrl: profile["avatar_url"] ?? "",
                    source: "QR Code",
                    isNew: "false",
                    email: profile["email"],
                    phone: profile["phone"],
                    website: profile["website"],
                    company: profile["company_name"],
                    department: profile["department"],
                    address: profile["address"],
                    targetUserId: uuid,
                    connectionId: existingConn['id'] as String?,
                    socialLinks: profile['metadata']?['socials'],
                  ),
                ),
              );
              return;
            }
          }

          name = profile["full_name"] ?? "scan_qr_eventzone_user".tr();
          final String job = profile["job_title"] ?? "";
          final String comp = profile["company_name"] ?? "";
          title = job.isNotEmpty 
              ? (comp.isNotEmpty ? "scan_qr_job_at_comp".tr(args: [job, comp]) : job)
              : (comp.isNotEmpty ? "scan_qr_professional_at_comp".tr(args: [comp]) : "scan_qr_attendee".tr());
          avatarUrl = profile["avatar_url"] ?? "";
          email = profile["email"];
          phone = profile["phone"];
          website = profile["website"];
          company = comp;
          department = profile["department"];
        } else {
          _laserController.stop();
          setState(() => _isConnecting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("scan_qr_error_profile_not_found".tr()),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      } catch (e) {
        debugPrint("Error fetching profile: $e");
        _laserController.stop();
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("scan_qr_error_db".tr()),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    } else {
      // Not a UUID: Parse structured details (for Business Card / Event Badge QR codes or input text)
      setState(() {
        _ocrStatus = "scan_qr_extracting_fields".tr();
        _ocrProgress = 0.5;
      });
      
      final parsed = _parseContactData(data);
      name = parsed["name"]!;
      title = parsed["title"]!;
      avatarUrl = parsed["avatarUrl"]!;
    }

    // Dynamic scanning progress steps for visual feedback
    // Step 2: 600ms - Parsing metadata
    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _ocrStatus = "scan_qr_structuring_info".tr();
        _ocrProgress = 0.8;
      });
      
      // Step 3: 600ms - Final verification
      Future.delayed(const Duration(milliseconds: 600), () async {
        if (!mounted) return;
        setState(() {
          _ocrStatus = "scan_qr_verification_success".tr();
          _ocrProgress = 1.0;
        });
        


        // Insert into Supabase connections table (and deduct point)
        try {
          final connectionId = await _saveToSupabase(
            name, 
            title, 
            avatarUrl,
            email: email,
            phone: phone,
            website: website,
            company: company,
            department: department,
            targetUserId: uuid,
          );
          
          if (mounted) {
            _laserController.stop();
            setState(() => _isConnecting = false);

            if (uuid != null) {
              NotificationService().markRecentlyScanned(uuid);
            }

            final String? jobTitleForDialog = scannedProfile?["job_title"] ??
                ((company != null && company.isNotEmpty) ? null : title);

            await ConnectionSuccessDialog.show(
              context,
              name: name,
              isScanner: true,
              title: "Connected! 🎉",
              jobTitle: jobTitleForDialog,
              company: company,
              avatarUrl: avatarUrl,
              targetUserId: uuid,
              connectionId: connectionId,
              email: email,
              phone: phone,
              website: website,
              department: department,
              address: scannedProfile?["address"],
              tags: (scannedProfile?['interests'] as List?)?.map((e) => e.toString()).toList(),
              socialLinks: scannedProfile?['metadata']?['socials'],
              onViewProfile: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfessionalProfileScreen(
                      name: name,
                      title: title,
                      avatarUrl: avatarUrl,
                      source: _scanType,
                      isNew: "true",
                      email: email,
                      phone: phone,
                      website: website,
                      company: company,
                      department: department,
                      address: scannedProfile?["address"],
                      targetUserId: uuid,
                      connectionId: connectionId,
                      socialLinks: scannedProfile?['metadata']?['socials'],
                      createdAt: DateTime.now().toIso8601String(),
                    ),
                  ),
                );
              },
            );
          }
        } catch (e) {
          if (mounted) {
            _laserController.stop();
            setState(() => _isConnecting = false);
            final errStr = e.toString();
            if (errStr.contains("expired") || errStr.contains("subscription") || errStr.contains("trial")) {
              SubscriptionExpiredBottomSheet.show(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(errStr.replaceAll('Exception: ', '')),
                  backgroundColor: Colors.redAccent,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      });
    });
  }

  Map<String, String> _parseContactData(String data) {
    String name = "";
    String title = "";
    String avatarUrl = "";

    final trimmed = data.trim();

    // 1. Check if it's vCard
    if (trimmed.toUpperCase().startsWith("BEGIN:VCARD")) {
      final lines = trimmed.split("\n");
      String fn = "";
      String org = "";
      String job = "";
      for (var line in lines) {
        final upperLine = line.toUpperCase();
        if (upperLine.startsWith("FN:")) {
          fn = line.substring(3).trim();
        } else if (upperLine.startsWith("ORG:")) {
          org = line.substring(4).trim();
        } else if (upperLine.startsWith("TITLE:")) {
          job = line.substring(6).trim();
        }
      }
      name = fn.isNotEmpty ? fn : "Scanned Contact";
      title = job.isNotEmpty 
          ? (org.isNotEmpty ? "$job at $org" : job)
          : (org.isNotEmpty ? "Professional at $org" : "Scanned Contact");
    } 
    // 2. Check if it's JSON
    else if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
      try {
        final Map<String, dynamic> parsed = jsonDecode(trimmed);
        name = parsed["name"] ?? parsed["full_name"] ?? "Scanned Profile";
        final parsedTitle = parsed["title"] ?? parsed["job_title"] ?? "";
        final parsedCompany = parsed["company"] ?? parsed["company_name"] ?? "";
        title = parsedTitle.isNotEmpty 
            ? (parsedCompany.isNotEmpty ? "$parsedTitle at $parsedCompany" : parsedTitle)
            : (parsedCompany.isNotEmpty ? "Professional at $parsedCompany" : "Connection");
        if (parsed["avatarUrl"] != null || parsed["avatar_url"] != null) {
          avatarUrl = parsed["avatarUrl"] ?? parsed["avatar_url"];
        }
      } catch (_) {}
    }
    // 3. Check if it's a comma/semi-colon separated value
    else if (trimmed.contains(",") || trimmed.contains(";")) {
      final parts = trimmed.contains(",") ? trimmed.split(",") : trimmed.split(";");
      if (parts.isNotEmpty) {
        name = parts[0].trim();
        if (parts.length > 1) {
          title = parts[1].trim();
          if (parts.length > 2) {
            title = "$title at ${parts[2].trim()}";
          }
        } else {
          title = "Scanned via $_scanType";
        }
      }
    }
    // 4. Default raw string
    else {
      name = trimmed == "manual_scan" 
          ? (_scanType == "Business Card" ? "Avery Sterling" : "Jamie Vance")
          : trimmed;
      title = name == "Avery Sterling"
          ? "DevOps Manager at CloudFlux Solutions"
          : (name == "Jamie Vance" ? "Marketing Lead at AlphaGrowth" : "Connection via $_scanType");
    }

    return {
      "name": name,
      "title": title,
      "avatarUrl": avatarUrl,
    };
  }

  Future<void> _captureAndExtractText() async {
    if (_isConnecting) return;
    if (_scanType == "QR Code") return;
    
    if (_cameraAwesomeState == null || !_isCameraReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Camera is still starting. Please wait a moment...".tr()),
          backgroundColor: Colors.orangeAccent,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isConnecting = true;
        _ocrStatus = "Capturing image...";
        _ocrProgress = 0.05;
      });
      
      _cameraAwesomeState!.when(
        onPhotoMode: (pm) async {
          try {
            final request = await pm.takePhoto();

            // Immediately turn off flash/torch after capturing photo
            if (_isFlashOn && _cameraAwesomeState != null) {
              try {
                await _cameraAwesomeState!.sensorConfig.setFlashMode(FlashMode.none);
                _isFlashOn = false;
                if (mounted) setState(() {});
              } catch (_) {}
            }

            if (request.path != null) {
              // Ensure the captured file is completely written to disk
              final capturedFile = File(request.path!);
              int retries = 0;
              int lastLength = -1;
              while (retries < 25) {
                if (await capturedFile.exists()) {
                  final curLength = await capturedFile.length();
                  if (curLength > 1000 && curLength == lastLength) {
                    break;
                  }
                  lastLength = curLength;
                }
                await Future.delayed(const Duration(milliseconds: 30));
                retries++;
              }
              await _processImageFile(request.path!, isCameraCapture: true);
            } else {
              if (mounted) {
                setState(() => _isConnecting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Capture failed: Path is null"), backgroundColor: Colors.redAccent),
                );
              }
            }
          } catch (e) {
            debugPrint("Photo capture callback error: $e");
            if (mounted) {
              setState(() => _isConnecting = false);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Capture failed: $e"), backgroundColor: Colors.redAccent),
              );
            }
          }
        },
      );
    } catch (e) {
      debugPrint("Capture error: $e");
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Capture failed: $e"), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _pickAndProcessFromGallery() async {
    if (_isConnecting) return;
    
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image == null) return;
    
    await _processImageFile(image.path, isCameraCapture: false);
  }

  Future<void> _processImageFile(String path, {bool isCameraCapture = false}) async {
    _laserController.repeat(reverse: true);

    // ── Ultra-Fast AI Track for Business Cards & Badges ──
    if (_scanType == "Business Card" || _scanType == "Event Badge") {
      setState(() {
        _isConnecting = true;
        _ocrStatus = "scan_qr_ai_optimizing".tr();
        _ocrProgress = 0.20;
      });

      String activePath = path;
      if (isCameraCapture) {
        try {
          final size = MediaQuery.of(context).size;
          final double frameW = _scanType == "Business Card" ? 340 : 280;
          final double frameH = _scanType == "Business Card" ? 200 : 420;
          activePath = await compute(_cropCardImageInIsolate, {
            'path': path,
            'screenWidth': size.width,
            'screenHeight': size.height,
            'frameW': frameW,
            'frameH': frameH,
          });
        } catch (e) {
          debugPrint("[ScanQR] Error cropping card in isolate: $e");
          activePath = path;
        }
      }

      int aiStep = 0;
      _aiStatusTimer?.cancel();
      _aiStatusTimer = Timer.periodic(const Duration(milliseconds: 450), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        aiStep++;
        if (aiStep == 1) {
          setState(() {
            _ocrStatus = "scan_qr_ai_reading".tr();
            _ocrProgress = 0.45;
          });
        } else if (aiStep == 2) {
          setState(() {
            _ocrStatus = "scan_qr_ai_extracting".tr();
            _ocrProgress = 0.70;
          });
        } else if (aiStep == 3) {
          setState(() {
            _ocrStatus = "scan_qr_ai_almost_done".tr();
            _ocrProgress = 0.88;
          });
        } else if (aiStep >= 4) {
          // Dynamic pulsing progress up to 96% while waiting for network/AI completion
          setState(() {
            final nextProgress = 0.88 + math.min(0.08, (aiStep - 3) * 0.015);
            _ocrProgress = nextProgress;
          });
          if (aiStep > 35) {
            timer.cancel();
          }
        }
      });

      try {
        final aiResult = await BusinessCardScannerService()
            .scanCardImage(File(activePath))
            .timeout(
              const Duration(seconds: 30),
              onTimeout: () => BusinessCardScannerResult.failure(
                "Scanning timed out. Please check your internet connection.",
              ),
            );
        _aiStatusTimer?.cancel();

        if (aiResult.isNotBusinessCard) {
          _laserController.stop();
          if (mounted) {
            setState(() => _isConnecting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(aiResult.errorMessage ?? "No business card detected."),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          if (isCameraCapture) {
            try {
              await File(activePath).delete();
            } catch (_) {}
          }
          return;
        }

        if (aiResult.isSuccess && aiResult.card != null && !aiResult.card!.isEmpty) {
          final card = aiResult.card!;
          if (mounted) {
            setState(() {
              _ocrStatus = "scan_qr_ai_ready".tr();
              _ocrProgress = 1.0;
            });
            await Future.delayed(const Duration(milliseconds: 250));
          }

          if (mounted) {
            _laserController.stop();
            setState(() => _isConnecting = false);

            File? cardImageFile;
            try {
              final tempDir = Directory.systemTemp;
              final targetPath = '${tempDir.path}/card_contact_${DateTime.now().millisecondsSinceEpoch}.jpg';
              final compressed = await FlutterImageCompress.compressAndGetFile(
                activePath,
                targetPath,
                minWidth: 800,
                minHeight: 800,
                quality: 75,
                autoCorrectionAngle: true,
                format: CompressFormat.jpeg,
              );
              if (compressed != null) {
                cardImageFile = File(compressed.path);
              } else {
                cardImageFile = File(activePath);
              }
            } catch (e) {
              debugPrint('[ScanQR] Error creating low-size card image: $e');
              cardImageFile = File(activePath);
            }

            if (isCameraCapture && cardImageFile.path != activePath) {
              try {
                File(activePath).deleteSync();
              } catch (_) {}
            }

            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ReviewContactScreen(
                  initialName: card.name,
                  initialTitle: card.title,
                  initialEmail: card.email,
                  initialPhone: card.phone,
                  initialWebsite: card.website,
                  initialCompany: card.company,
                  initialDepartment: card.department,
                  initialAddress: card.address,
                  initialNotes: (card.notes != null && card.notes!.isNotEmpty) ? card.notes : null,
                  initialImage: cardImageFile,
                  source: _scanType,
                ),
              ),
            );
            return;
          }
        } else {
          _laserController.stop();
          if (mounted) {
            setState(() => _isConnecting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(aiResult.errorMessage ?? "Could not extract card details. Please try with clearer lighting."),
                backgroundColor: Colors.orangeAccent,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          if (isCameraCapture) {
            try {
              await File(path).delete();
            } catch (_) {}
          }
          return;
        }
      } catch (aiErr) {
        _aiStatusTimer?.cancel();
        _laserController.stop();
        if (mounted) {
          setState(() => _isConnecting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Scan error: $aiErr"),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        if (isCameraCapture) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
        return;
      }
    }

    // ── Offline / Fallback ML Kit OCR Engine ──
    _aiStatusTimer?.cancel();
    setState(() {
      _isConnecting = true;
      _ocrStatus = isCameraCapture 
          ? "Image captured! You can move your phone.".tr() 
          : "Analyzing image...".tr();
      _ocrProgress = 0.35;
    });

    if (!mounted) return;

    try {
      // Setup args for the isolate to prevent UI freezing
      final double screenWidth = MediaQuery.of(context).size.width;
      final double screenHeight = MediaQuery.of(context).size.height;
      double frameW = 280;
      double frameH = 280;
      if (_scanType == "Business Card") {
        frameW = 340;
        frameH = 200;
      } else if (_scanType == "Event Badge") {
        frameW = 280;
        frameH = 420;
      }

      final isolateArgs = {
        'path': path,
        'isCameraCapture': isCameraCapture,
        'screenWidth': screenWidth,
        'screenHeight': screenHeight,
        'frameW': frameW,
        'frameH': frameH,
      };

      // Run heavy image decoding and cropping in background isolate
      final isolateResult = await compute(_processImageInIsolate, isolateArgs);
      
      String ocrImagePath = isolateResult['ocrImagePath'];
      int cropHeight = isolateResult['cropHeight'] ?? 1;
      int imageHeight = isolateResult['imageHeight'] ?? 1;

      if (isCameraCapture && mounted) {
        try {
          final resultBytes = await FlutterImageCompress.compressWithFile(
            ocrImagePath,
            quality: 85,
          );
          if (resultBytes != null) {
             await File(ocrImagePath).writeAsBytes(resultBytes);
          }
        } catch (_) {}

        setState(() {
          _ocrStatus = "Processing text recognition...";
          _ocrProgress = 0.50;
        });
      }

      // ── Step 2: Primary OCR pass on the cropped/focused image ──
      final inputImage = InputImage.fromFilePath(ocrImagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      
      final recognizedText = await textRecognizer.processImage(inputImage);

      // Collect all lines with bounding-box metadata
      List<Map<String, dynamic>> rawLinesWithMeta = [];
      List<String> allDetectedLines = [];
      final int refHeight = isCameraCapture ? cropHeight : imageHeight;

      // Helper to process blocks and avoid exact duplicates
      void processBlocks(RecognizedText result) {
        for (TextBlock block in result.blocks) {
          for (TextLine line in block.lines) {
            final String text = line.text.trim();
            if (text.isEmpty) continue;
            // Prevent exact duplicate lines from both models
            if (!allDetectedLines.contains(text)) {
              allDetectedLines.add(text);
              rawLinesWithMeta.add({
                'text': text,
                'height': line.boundingBox.height.toDouble(),
                'normalizedTop': line.boundingBox.top / refHeight,
              });
            }
          }
        }
      }

      processBlocks(recognizedText);

      // ── Step 3: Fallback second pass on full image if cropped pass found very little ──
      if (isCameraCapture && rawLinesWithMeta.length < 3) {
        setState(() {
          _ocrStatus = "Running enhanced secondary scan...";
          _ocrProgress = 0.45;
        });
        final fullInput = InputImage.fromFilePath(path);
        final fullResult = await textRecognizer.processImage(fullInput);
        
        void processFullBlocks(RecognizedText result) {
          for (TextBlock block in result.blocks) {
            for (TextLine line in block.lines) {
              final String text = line.text.trim();
              if (text.isEmpty) continue;
              if (!allDetectedLines.contains(text)) {
                allDetectedLines.add(text);
                rawLinesWithMeta.add({
                  'text': text,
                  'height': line.boundingBox.height.toDouble(),
                  'normalizedTop': line.boundingBox.top / imageHeight,
                });
              }
            }
          }
        }
        
        processFullBlocks(fullResult);
      }

      await textRecognizer.close();

      // Clean up temp cropped file
      if (isCameraCapture) {
        try {
          await File('${path}_cropped.jpg').delete();
        } catch (_) {}
      }
      
      if (rawLinesWithMeta.isEmpty) {
        _laserController.stop();
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("No text detected on card/badge. Please try a clearer image."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      setState(() {
        _ocrStatus = "Analyzing text layout...";
        _ocrProgress = 0.5;
      });

      final finalLinesMeta = rawLinesWithMeta;

      // ──────────────────────────────────────────────────────────────────────
      // INTELLIGENT CONTACT PARSING ENGINE v3
      // Rule-based Multi-Pass Extraction with Confidence Scoring
      // ──────────────────────────────────────────────────────────────────────

      // Pre-processing: Clean texts and fix OCR confusions
      List<String> rawTexts = finalLinesMeta.map<String>((m) => m['text'] as String).toList();
      final List<String> croppedTexts = rawTexts; // We fallback to rawTexts as croppedTexts was removed previously in the pipeline
      List<String> cleanedLines = [];
      
      for (final line in allDetectedLines) {
        // Fix typical ML Kit mistakes for business cards
        String clean = line.replaceAll('(a)', '@').replaceAll('.corn', '.com');
        // If it looks like a phone number but has letters 'o' or 'l', fix them
        if (RegExp(r'[0-9]').hasMatch(clean) && !clean.contains('@') && !RegExp(r'[a-zA-Z]{4,}').hasMatch(clean)) {
          clean = clean.replaceAll(RegExp(r'[oO]'), '0').replaceAll(RegExp(r'[lI]'), '1');
        }
        
        // Split combined lines (e.g. "CEO | Tech Corp")
        final parts = clean.split(RegExp(r'[\s]*[|/•·\\][\s]*|\s+[-—]\s+'));
        for (var p in parts) {
          final t = p.trim();
          if (t.length > 2) cleanedLines.add(t);
        }
      }

      // Add unique cropped lines as well to ensure spatial ones aren't missed
      for (final line in croppedTexts) {
        String clean = line.replaceAll('(a)', '@').replaceAll('.corn', '.com');
        final parts = clean.split(RegExp(r'[\s]*[|/•·\\][\s]*|\s+[-—]\s+'));
        for (var p in parts) {
          final t = p.trim();
          if (t.length > 2 && !cleanedLines.contains(t)) {
            cleanedLines.add(t);
          }
        }
      }

      String? email;
      String? phone;
      String? website;
      String? name;
      String? title;
      String? company;
      List<String> addressParts = [];
      
      // ── Step 0.5: ML Kit Language ID & Entity Extraction ──
      final String fullTextContext = cleanedLines.join('\n');
      
      final languageIdentifier = LanguageIdentifier(confidenceThreshold: 0.5);
      String detectedLanguage = 'en';
      try {
        detectedLanguage = await languageIdentifier.identifyLanguage(fullTextContext);
        debugPrint("Detected language: $detectedLanguage");
      } catch (_) {} finally {
        languageIdentifier.close();
      }

      // Entity extraction seeds — these give us a head start but regex can override
      String? entityEmail;
      String? entityPhone;
      List<String> entityAddresses = [];
      
      final entityExtractor = EntityExtractor(
        language: (detectedLanguage == 'fr') 
            ? EntityExtractorLanguage.french 
            : (detectedLanguage == 'ar')
                ? EntityExtractorLanguage.arabic
                : EntityExtractorLanguage.english
      );
      
      try {
        final List<EntityAnnotation> annotations = await entityExtractor.annotateText(fullTextContext);
        for (final annotation in annotations) {
          for (final entity in annotation.entities) {
             if (entity.type == EntityType.email && entityEmail == null) {
                entityEmail = annotation.text;
             } else if (entity.type == EntityType.phone && entityPhone == null) {
                entityPhone = annotation.text;
             } else if (entity.type == EntityType.address) {
                entityAddresses.add(annotation.text);
             }
          }
        }
      } catch (_) {} finally {
        entityExtractor.close();
      }

      // ── Step 1: Extract High Confidence fields (Email, Phone, Web, Address) ──
      
      // Robust Email Regex
      final emailRegExp = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', caseSensitive: false);
      // Phone: very permissive — any sequence of 7+ digits with optional separators and country code
      final phoneRegExpAlg = RegExp(r'(?:\+213|00213|0)[\s\-\.\/]?(?:5|6|7)[\s\-\.\/]?[0-9]{2}[\s\-\.\/]?[0-9]{2}[\s\-\.\/]?[0-9]{2}[\s\-\.\/]?[0-9]{2}');
      final phoneRegExpGen = RegExp(r'(?:\+?[\d]{1,4}[\s\-\.\/]?)?(?:\(?\d{1,5}\)?[\s\-\.\/]?)?(?:\d[\s\-\.\/]?){6,14}\d');
      // Website Regex
      final webRegExp = RegExp(r'(https?://)?(?:www\.)?[a-zA-Z0-9\-]+\.[a-zA-Z]{2,6}(/\S*)?', caseSensitive: false);
      
      // Expanded address keywords (French, Arabic transliterated, English)
      final addressKeywords = [
        'street', 'road', 'avenue', 'ave', 'boulevard', 'blvd', 'route', 'drive', 'lane', 'place', 'square',
        'cité', 'cite', 'bp ', 'b.p.', 'p.o.', 'p.o', 'boite postale', 'box',
        'rue', 'ruelle', 'impasse', 'passage', 'chemin', 'allée', 'allee', 'quartier', 'lot',
        'hai', 'hay', 'حي', 'شارع', 'طريق', 'زنقة',
        'wilaya', 'daira', 'daïra', 'commune',
        'floor', 'suite', 'building', 'bldg', 'tower', 'étage', 'etage', 'bât', 'bat', 'immeuble',
        'alger', 'algiers', 'oran', 'constantine', 'annaba', 'blida', 'setif', 'sétif', 'tlemcen',
        'batna', 'djelfa', 'sidi', 'bel', 'ain', 'bordj', 'el ', 'tizi', 'bechar', 'biskra',
      ];
      
      // Lines consumed by high-confidence extraction (tracked by index)
      Set<int> consumedIndices = {};

      for (int i = 0; i < cleanedLines.length; i++) {
        final line = cleanedLines[i];
        bool matchedHighConfidence = false;
        final lower = line.toLowerCase().trim();

        // Check Email
        if (email == null) {
          final m = emailRegExp.firstMatch(line);
          if (m != null) {
            email = m.group(0);
            matchedHighConfidence = true;
          }
        }

        // Check Phone — don't skip lines already matched as email
        if (!matchedHighConfidence && phone == null && !line.contains('@')) {
          final algM = phoneRegExpAlg.firstMatch(line);
          if (algM != null) {
            phone = algM.group(0);
            matchedHighConfidence = true;
          } else {
            final genM = phoneRegExpGen.firstMatch(line);
            if (genM != null) {
              final digitsCount = genM.group(0)!.replaceAll(RegExp(r'[^\d]'), '').length;
              if (digitsCount >= 7 && digitsCount <= 15) {
                phone = genM.group(0);
                matchedHighConfidence = true;
              }
            }
          }
        }
        
        // Check for phone-like lines: lines that are mostly digits (label + number)
        if (!matchedHighConfidence && phone == null) {
          final stripped = line.replaceAll(RegExp(r'[\s\-\.\(\)\+/:]'), '');
          final digitCount = stripped.replaceAll(RegExp(r'[^\d]'), '').length;
          final letterCount = stripped.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
          if (digitCount >= 7 && letterCount <= 5) {
            // Extract just the number part
            final numMatch = RegExp(r'[\+\d][\d\s\-\.\(\)/]{6,}').firstMatch(line);
            if (numMatch != null) {
              phone = numMatch.group(0)!.trim();
              matchedHighConfidence = true;
            }
          }
        }

        // Check Website/LinkedIn
        if (!matchedHighConfidence && website == null && !line.contains('@')) {
          if (lower.contains('linkedin.com') || lower.contains('github.com') || lower.contains('twitter.com') || lower.contains('facebook.com') || lower.contains('instagram.com')) {
            website = line;
            matchedHighConfidence = true;
          } else {
            final wm = webRegExp.firstMatch(lower);
            if (wm != null && lower.contains('.')) {
              final ext = wm.group(0)!.split('.').last.replaceAll(RegExp(r'[^a-z]'), '');
              if (['com', 'org', 'net', 'io', 'dz', 'fr', 'co', 'me', 'info', 'biz', 'edu', 'gov', 'ly', 'ma', 'tn', 'uk', 'de'].contains(ext)) {
                website = wm.group(0);
                matchedHighConfidence = true;
              }
            }
          }
        }
        
        // Address: accumulate ALL lines that look like address parts
        if (!matchedHighConfidence) {
          bool isAddress = false;
          // Keyword check
          if (addressKeywords.any((kw) => lower.contains(kw))) {
            isAddress = true;
          }
          // Postal code patterns: 5-digit, or digit+space+digit patterns
          if (!isAddress && RegExp(r'\b\d{4,6}\b').hasMatch(line) && line.length < 60) {
            // Line has a postal code and isn't too long (rules out serial numbers)
            final hasLetters = RegExp(r'[a-zA-ZÀ-ÿ]').hasMatch(line);
            if (hasLetters) isAddress = true;
          }
          // Pattern: "number + words" like "12 Avenue de la Liberté"
          if (!isAddress && RegExp(r'^\d{1,5}\s*[,.]?\s+[a-zA-ZÀ-ÿ]').hasMatch(line)) {
            isAddress = true;
          }
          
          if (isAddress) {
            addressParts.add(line);
            matchedHighConfidence = true;
          }
        }

        if (matchedHighConfidence) {
          consumedIndices.add(i);
        }
      }
      
      // Use entity extraction as fallback for phone
      if (phone == null && entityPhone != null) {
        phone = entityPhone;
      }
      // Use entity extraction as fallback for email
      if (email == null && entityEmail != null) {
        email = entityEmail;
      }
      // Merge entity addresses into our address parts
      for (final ea in entityAddresses) {
        if (!addressParts.any((p) => p.toLowerCase().contains(ea.toLowerCase()))) {
          addressParts.add(ea);
        }
      }

      // Build remaining lines (not consumed by high-confidence)
      List<String> remainingLines = [];
      for (int i = 0; i < cleanedLines.length; i++) {
        if (!consumedIndices.contains(i)) {
          final line = cleanedLines[i];
          final lower = line.toLowerCase();
          // Remove noise lines
          if (lower.replaceAll(RegExp(r'[^a-zà-ÿ]'), '').length < 3) continue;
          if (['tel:', 'fax:', 'mob:', 'phone:', 'email:', 'e-mail:', 'website:', 'web:', 'tél:', 'tél', 'tel', 'fax', 'mob', 'gsm'].contains(lower.trim().replaceAll(':', '').toLowerCase())) continue;
          remainingLines.add(line);
        }
      }

      // ── Step 2: Extract Medium Confidence fields (Job Title, Company) ──

      final jobTitleWords = <String>{
        'ceo', 'cfo', 'cto', 'coo', 'cmo', 'cio', 'vp', 'president', 'vice-president',
        'director', 'manager', 'supervisor', 'coordinator',
        'founder', 'co-founder', 'cofounder', 'partner', 'lead', 'head', 'chief', 'officer',
        'developer', 'engineer', 'architect', 'designer', 'analyst', 'consultant', 'specialist', 'advisor',
        'professor', 'lecturer', 'researcher', 'scientist', 'doctor', 'dr', 'pharmacist',
        'secretary', 'assistant', 'associate', 'intern', 'trainee', 'executive',
        'accountant', 'auditor', 'lawyer', 'attorney', 'advocate', 'notary', 'judge',
        'nurse', 'surgeon', 'dentist', 'veterinarian',
        // French
        'directeur', 'directrice', 'gérant', 'gérante', 'responsable', 'chef', 'fondateur', 'fondatrice',
        'ingénieur', 'technicien', 'technicienne', 'médecin', 'professeur', 'enseignant',
        'développeur', 'spécialiste', 'expert', 'attaché', 'adjoint', 'conseiller', 'conseillère',
        'secrétaire', 'comptable', 'avocat', 'avocate', 'notaire', 'juge',
        'infirmier', 'infirmière', 'chirurgien', 'dentiste', 'pharmacien', 'pharmacienne',
        'chargé', 'chargée', 'maître', 'maitre',
        // Arabic transliterated
        'moudir', 'mohandes', 'tabib', 'mohandis', 'mudir', 'rais',
      };

      final companyIndicators = <String>{
        'ltd', 'corp', 'corporation', 'inc', 'incorporated', 'llc', 'plc', 'gmbh', 'ag', 'sa', 'sarl', 'sas',
        'eurl', 'spa', 'group', 'groupe', 'holding', 'solutions', 'technologies', 'technology', 'tech',
        'systems', 'services', 'consulting', 'partners', 'enterprises', 'industries', 'global',
        'digital', 'media', 'creative', 'studio', 'agency', 'agence', 'hub', 'labs', 'ventures',
        'company', 'compagnie', 'société', 'societe', 'entreprise', 'institute', 'institut',
        'university', 'université', 'universite', 'school', 'école', 'ecole', 'lycée', 'lycee', 'college',
        'hospital', 'hôpital', 'hopital', 'clinic', 'clinique', 'cabinet', 'pharmacie', 'laboratoire',
        'association', 'foundation', 'fondation', 'organization', 'organisation',
        'ministry', 'ministère', 'ministere', 'department', 'département',
        'syndicate', 'bureau', 'center', 'centre', 'office',
        'bank', 'banque', 'assurance', 'insurance',
        'factory', 'usine', 'atelier', 'workshop',
      };

      List<String> remainingForName = [];

      for (final line in remainingLines) {
        bool matchedMedium = false;
        final lowerWords = line.toLowerCase().split(RegExp(r'\s+'));
        
        // Check Job Title
        if (title == null) {
          if (jobTitleWords.any((kw) => lowerWords.contains(kw))) {
            title = line;
            matchedMedium = true;
          } else {
             // Partial match with word boundaries and length limit
             if (line.length < 50) {
               for (final kw in jobTitleWords) {
                 if (kw.length >= 4 && RegExp(r'\b' + RegExp.escape(kw) + r'\b', caseSensitive: false).hasMatch(line.toLowerCase())) {
                   title = line;
                   matchedMedium = true;
                   break;
                 }
               }
             }
          }
        }
        
        // Check Company
        if (!matchedMedium && company == null) {
          if (companyIndicators.any((kw) => lowerWords.contains(kw))) {
            company = line;
            matchedMedium = true;
          }
        }

        if (!matchedMedium) {
          remainingForName.add(line);
        }
      }

      // ── Step 3: Extract Name — Font-size + position weighted scoring ──
      // The name is almost always the LARGEST text on the card and near the TOP.
      // We score ALL remaining lines, not just leftover unmatched ones.
      
      double maxHeight = 0.0;
      for (final meta in finalLinesMeta) {
        if (meta['height'] != null && (meta['height'] as double) > maxHeight) {
          maxHeight = meta['height'] as double;
        }
      }
      
      int bestNameScore = -1;
      
      for (final line in remainingForName) {
        // Hard skip: lines with digits, email-like lines, very short lines
        if (line.contains(RegExp(r'[0-9]'))) continue;
        if (line.contains('@') || line.contains('www') || line.contains('http')) continue;
        if (line.length < 3) continue;
        
        int score = 0;
        final words = line.split(RegExp(r'\s+'));
        
        // Word count scoring: 2-3 words is ideal for names, 1 word is okay, 4 is acceptable
        if (words.length >= 2 && words.length <= 3) score += 15;
        else if (words.length == 1 && line.length >= 3) score += 5;
        else if (words.length == 4) score += 8;
        else if (words.length > 5) score -= 10; // Probably a sentence, not a name
        
        // Capitalization scoring
        final capitalized = words.where((w) => w.isNotEmpty && w[0] == w[0].toUpperCase()).length;
        if (capitalized == words.length) score += 10;
        
        // All-caps scoring (common on business cards)
        if (words.every((w) => w == w.toUpperCase() && w.length > 1)) score += 5;
        
        // Only letters, spaces, hyphens, dots, apostrophes (name-like characters)
        if (RegExp(r"^[a-zA-ZÀ-ÿ\u0600-\u06FF\s\-\.'\u200C]+$").hasMatch(line)) score += 8;
        
        // Bounding box height boost — THE MOST IMPORTANT SIGNAL
        if (maxHeight > 0) {
          final metaMatch = finalLinesMeta.where((m) {
            final metaText = (m['text'] as String).toLowerCase();
            return metaText.contains(line.toLowerCase()) || line.toLowerCase().contains(metaText);
          }).toList();
          if (metaMatch.isNotEmpty) {
            final double height = metaMatch.first['height'] as double;
            final double heightRatio = height / maxHeight;
            if (heightRatio > 0.85) score += 30;      // Largest text — almost certainly the name
            else if (heightRatio > 0.65) score += 15;
            else if (heightRatio > 0.5) score += 5;
          }
        }
        
        // Position boost — names are typically in the top third of the card
        final posMatch = finalLinesMeta.where((m) {
          final metaText = (m['text'] as String).toLowerCase();
          return metaText.contains(line.toLowerCase()) || line.toLowerCase().contains(metaText);
        }).toList();
        if (posMatch.isNotEmpty) {
          final double normalizedTop = posMatch.first['normalizedTop'] as double;
          if (normalizedTop < 0.3) score += 8;   // Top third
          else if (normalizedTop < 0.5) score += 3;   // Top half
        }
        
        if (score > bestNameScore) {
          bestNameScore = score;
          name = line;
        }
      }
      
      // If we still don't have a name, look at consumed lines too — 
      // sometimes the name line also contained an address keyword spuriously
      if (name == null || bestNameScore < 10) {
        for (final meta in finalLinesMeta) {
          final line = meta['text'] as String;
          if (line.contains(RegExp(r'[0-9]')) || line.contains('@')) continue;
          if (line.length < 3 || line.length > 40) continue;
          final words = line.split(RegExp(r'\s+'));
          if (words.length > 4) continue;
          
          final double height = (meta['height'] as double?) ?? 0;
          if (maxHeight > 0 && height / maxHeight > 0.8) {
            // This is the largest text and looks name-like
            if (RegExp(r"^[a-zA-ZÀ-ÿ\u0600-\u06FF\s\-\.'\u200C]+$").hasMatch(line)) {
              name = line;
              break;
            }
          }
        }
      }
      
      // Combine address parts into a single string
      String? address = addressParts.isNotEmpty ? addressParts.join(', ') : "";

      // Fallback: If no company found, use email domain
      if (company == null && email != null) {
        final parts = email.split('@');
        if (parts.length > 1) {
          final domainPart = parts[1].split('.')[0];
          final freeDomains = {'gmail', 'yahoo', 'hotmail', 'outlook', 'icloud', 'live', 'aol', 'protonmail', 'zoho'};
          if (!freeDomains.contains(domainPart.toLowerCase())) {
            company = domainPart[0].toUpperCase() + domainPart.substring(1);
          }
        }
      }

      // ── Step 4: Merge with Previous Scan Data (Rescan Logic) ──
      final prevData = widget.previousScanData;
      if (prevData != null) {
        // Only override if the new pass didn't find it or if we explicitly want to merge.
        // The simplest merge is: prefer the non-empty value. If both exist, keep the old one 
        // if user had already edited it, but here we just prefer non-empty.
        name = name ?? prevData['name'] as String?;
        title = title ?? prevData['title'] as String?;
        company = company ?? prevData['company'] as String?;
        email = email ?? prevData['email'] as String?;
        phone = phone ?? prevData['phone'] as String?;
        website = website ?? prevData['website'] as String?;
        address = (address.isEmpty) ? (prevData['address'] as String? ?? "") : address;
      }

      // Post-processing Sanitation
      final String cleanName = _sanitizeField(name ?? "");
      final String cleanTitle = _sanitizeField(title ?? "");
      final String cleanCompany = _sanitizeField(company ?? "");
      final String cleanDept = "";

      setState(() {
        _ocrStatus = "scan_qr_extracting_metadata".tr();
        _ocrProgress = 0.8;
      });
      
      // Allow the 0.8 progress animation to play slightly so the user sees something is happening
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      
      setState(() {
        _ocrStatus = "scan_qr_scan_successful".tr();
        _ocrProgress = 1.0;
      });
      
      // Give the success checkmark animation exactly enough time to play (600ms) before navigating
      await Future.delayed(const Duration(milliseconds: 600));
      
      if (mounted) {
        _laserController.stop();
        setState(() => _isConnecting = false);
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ReviewContactScreen(
              initialName: cleanName,
              initialTitle: cleanTitle,
              initialEmail: email ?? "",
              initialPhone: phone ?? "",
              initialWebsite: website ?? "",
              initialCompany: cleanCompany,
              initialDepartment: cleanDept,
              initialAddress: address ?? "",
              source: _scanType,
            ),
          ),
        );
      }
      
    } catch (e) {
      debugPrint("OCR Error: $e");
      _laserController.stop();
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("OCR Recognition failed: $e"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<String?> _saveToSupabase(
    String name,
    String title,
    String avatarUrl, {
    String? email,
    String? phone,
    String? website,
    String? company,
    String? department,
    String? targetUserId,
  }) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserId = currentUser?.id;
      if (currentUserId == null) return null;
      // 0. Fetch target profile if we have targetUserId to get their tags
      Map<String, dynamic>? targetProfile;
      if (targetUserId != null) {
        targetProfile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', targetUserId)
            .maybeSingle();
      }

      // 0.5 Check subscription or trial status before proceeding
      final profileRes = await Supabase.instance.client.from('profiles').select('created_at, subscription_end_date').eq('id', currentUserId).single();
      
      final now = DateTime.now();
      bool isActive = false;
      
      if (profileRes['subscription_end_date'] != null) {
        final subEnd = DateTime.parse(profileRes['subscription_end_date']);
        if (subEnd.isAfter(now)) isActive = true;
      }
      
      if (!isActive && profileRes['created_at'] != null) {
        final createdAt = DateTime.parse(profileRes['created_at']);
        final trialEnd = createdAt.add(const Duration(days: 15));
        if (trialEnd.isAfter(now)) isActive = true;
      }

      if (!isActive) {
        throw Exception("Your trial/subscription has expired. Please upgrade to save connections.");
      }

      // Fetch scanner profile if we have targetUserId so we can provide sender metadata and save mutual connection
      Map<String, dynamic>? myProfile;
      if (targetUserId != null && currentUser != null) {
        myProfile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', currentUserId)
            .maybeSingle();
      }

      // 1. Save connection for the current user
      final newConn = await Supabase.instance.client.from('connections').insert({
        'user_id': currentUserId,
        'linked_profile_id': targetUserId,
        'name': name,
        'title': title,
        'avatar_url': avatarUrl,
        'source': _scanType,
        'is_new': true,
        'email': email,
        'phone': phone,
        'website': website,
        'company': company,
        'department': department,
        'tags': targetProfile?['interests'] ?? [],
        'notes': myProfile != null ? jsonEncode({
          'sender_name': myProfile['full_name'],
          'sender_title': myProfile['job_title'],
          'sender_company': myProfile['company_name'],
          'sender_avatar': myProfile['avatar_url'],
        }) : null,
      }).select('id').maybeSingle();
      
      final connectionId = newConn?['id'] as String?;

      // 2. Save mutual connection for the scanned user (two-way link)
      if (targetUserId != null && myProfile != null) {
        final String myJob = myProfile['job_title'] ?? '';
        final String myComp = myProfile['company_name'] ?? '';
        final String myTitle = myJob.isNotEmpty
            ? (myComp.isNotEmpty ? "$myJob at $myComp" : myJob)
            : (myComp.isNotEmpty ? "Professional at $myComp" : "Attendee");

        await Supabase.instance.client.from('connections').insert({
          'user_id': targetUserId, // Scanned user ID
          'linked_profile_id': currentUserId, // Mutual link back to scanner
          'name': myProfile['full_name'] ?? 'Eventzone User',
          'title': myTitle,
          'avatar_url': myProfile['avatar_url'] ?? '',
          'source': 'QR Code',
          'is_new': true,
          'email': myProfile['email'],
          'phone': myProfile['phone'],
          'website': myProfile['website'],
          'company': myComp,
          'department': myProfile['department'],
          'tags': myProfile['interests'] ?? [],
        });
      }
      
      return connectionId;
    } catch (e) {
      debugPrint("Error saving to Supabase: $e");
      return null;
    }
  }

  Future<void> _toggleCameraFlash() async {
    if (_cameraAwesomeState != null && _isCameraReady) {
      try {
        _isFlashOn = !_isFlashOn;
        // With CameraAwesome, sensor config manages the flash
        _cameraAwesomeState!.sensorConfig.setFlashMode(
          _isFlashOn ? FlashMode.always : FlashMode.none
        );
        setState(() {});
      } catch (e) {
        debugPrint("Error toggling camera flash: $e");
      }
    }
  }

  Widget _buildTypeTab(String type, IconData icon) {
    final bool isSelected = _scanType == type;
    return GestureDetector(
      onTap: () async {
        if (_scanType == type) return;

        // Turn off torch/flash when switching modes and re-engage auto-focus
        if (_cameraAwesomeState != null) {
          try {
            _cameraAwesomeState!.sensorConfig.setFlashMode(FlashMode.none);
            CamerawesomePlugin.startAutoFocus();
          } catch (_) {}
        }
        
        setState(() {
          _scanType = type;
          _isFlashOn = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? EventzoneTheme.primaryAction : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.white24 : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              type == "QR Code" 
                ? "scan_qr_tab_qr".tr() 
                : (type == "Business Card" ? "scan_qr_tab_card".tr() : "scan_qr_tab_badge".tr()),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic scannable area calculations based on selection (bigger sizes)
    double frameWidth = 280;
    double frameHeight = 280;
    
    if (_scanType == "QR Code") {
      frameWidth = 280;
      frameHeight = 280;
    } else if (_scanType == "Business Card") {
      frameWidth = 340;
      frameHeight = 200;
    } else if (_scanType == "Event Badge") {
      frameWidth = 280;
      frameHeight = 420;
    }

    final size = MediaQuery.of(context).size;
    final double left = (size.width - frameWidth) / 2;
    // Align frame offset slightly upward to accommodate bottom sheets/buttons
    final double top = (size.height - frameHeight) / 2 - 50; 
    final Rect targetRect = Rect.fromLTWH(left, top, frameWidth, frameHeight);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera View
          if (_hasCameraPermission == true && _isReadyToBuildCamera)
            Positioned.fill(
              child: KeyedSubtree(
                key: _cameraKey,
                child: CameraAwesomeBuilder.custom(
                  previewFit: CameraPreviewFit.cover,
                  saveConfig: SaveConfig.photo(
                    pathBuilder: (sensors) async {
                      final Directory extDir = await getTemporaryDirectory();
                      final testDir = await Directory('${extDir.path}/camerawesome').create(recursive: true);
                      return SingleCaptureRequest('${testDir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg', sensors.first);
                    },
                  ),
                  onPreviewTapBuilder: (state) => OnPreviewTap(
                    onTap: (position, flutterPreviewSize, pixelPreviewSize) {
                      state.when(
                        onPhotoMode: (pm) => pm.focusOnPoint(
                          flutterPosition: position,
                          pixelPreviewSize: pixelPreviewSize,
                          flutterPreviewSize: flutterPreviewSize,
                          androidFocusSettings: AndroidFocusSettings(
                            autoCancelDurationInMillis: 2500,
                          ),
                        ),
                      );
                    },
                  ),
                  onImageForAnalysis: _processAnalysisImage,
                  imageAnalysisConfig: AnalysisConfig(
                    androidOptions: const AndroidAnalysisOptions.nv21(
                      width: 500,
                    ),
                    maxFramesPerSecond: 10,
                  ),
                  builder: (cameraState, preview) {
                    _onCameraStateReceived(cameraState);
                    return const SizedBox.shrink(); // Transparent background so the stack shows our custom UI
                  },
                ),
            ),
          ),
          
          // 2. Smoothly animated mask and corner overlays
          TweenAnimationBuilder<Rect?>(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            tween: RectTween(
              begin: _lastTargetRect ?? targetRect,
              end: targetRect,
            ),
            builder: (context, animRect, child) {
              _lastTargetRect = targetRect;
              final Rect rect = animRect ?? targetRect;
              return Stack(
                children: [
                  // Dark Overlay with Cutout Mask (sharp corners)
                  ClipPath(
                    clipper: ScannerOverlayClipper(cutoutRect: rect),
                    child: Container(
                      color: Colors.black.withOpacity(0.65),
                    ),
                  ),

                  // Hide camera view completely while processing
                  IgnorePointer(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      color: _isConnecting ? EventzoneTheme.backgroundEnd.withOpacity(0.98) : Colors.transparent,
                    ),
                  ),

                  // Clear cutout corner stroke (sharp corners)
                  if (!_isConnecting)
                    Positioned.fromRect(
                      rect: rect,
                      child: CustomPaint(
                        painter: ScannerCornersPainter(
                          color: Colors.white,
                          strokeWidth: 3.5,
                          cornerLength: 24.0,
                        ),
                      ),
                    ),

                  // Overlay indicators inside the rect
                  if (_isConnecting) ...[

                    // OCR progress status box centered in the viewfinder
                    Positioned.fromRect(
                      rect: rect,
                      child: Center(
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(_ocrProgress == 1.0),
                          tween: Tween<double>(begin: 0.8, end: 1.0),
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.elasticOut,
                          builder: (context, val, child) {
                            return Transform.scale(
                              scale: val,
                              child: Opacity(
                                opacity: ((val - 0.8) / 0.2).clamp(0.0, 1.0),
                                child: child,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: GlassContainer(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              borderRadius: 30,
                              child: Row(
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                                    child: _ocrProgress == 1.0
                                        ? const Icon(LucideIcons.checkCircle, color: EventzoneTheme.accentSuccess, size: 32, key: ValueKey('success'))
                                        : const PremiumSpinner(size: 28, key: ValueKey('spinner')),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _ocrStatus,
                                          style: TextStyle(
                                            color: _ocrProgress == 1.0 ? EventzoneTheme.accentSuccess : Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: TweenAnimationBuilder<double>(
                                            tween: Tween<double>(begin: 0, end: _ocrProgress),
                                            duration: const Duration(milliseconds: 400),
                                            curve: Curves.easeOutCubic,
                                            builder: (context, val, child) {
                                              return LinearProgressIndicator(
                                                value: val,
                                                backgroundColor: Colors.white10,
                                                minHeight: 4,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  _ocrProgress == 1.0 ? EventzoneTheme.accentSuccess : EventzoneTheme.primaryAction,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Camera permission required card
                    if (_hasCameraPermission == false)
                      Positioned.fromRect(
                        rect: rect,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: GlassContainer(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              borderRadius: 20,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.cameraOff, color: Colors.amber, size: 36),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Camera Access Needed".tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "Please grant camera access to scan codes and business cards.".tr(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton(
                                    onPressed: () {
                                      if (_isPermanentlyDenied) {
                                        openAppSettings();
                                      } else {
                                        _checkAndRequestCameraPermission(requestIfNeeded: true);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: EventzoneTheme.primaryAction,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Text(
                                      _isPermanentlyDenied ? "Open Settings".tr() : "Grant Permission".tr(),
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    // Camera initialization failure recovery card
                    else if (_cameraInitFailed)
                      Positioned.fromRect(
                        rect: rect,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: GlassContainer(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                              borderRadius: 20,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(LucideIcons.refreshCw, color: Colors.orangeAccent, size: 32),
                                  const SizedBox(height: 12),
                                  Text(
                                    "Camera Didn't Open".tr(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    "The device camera was unavailable or delayed.".tr(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    onPressed: _restartCameraManual,
                                    icon: const Icon(LucideIcons.refreshCw, size: 14),
                                    label: Text("Restart Camera".tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: EventzoneTheme.primaryAction,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    // Subtle starting indicator while camera hardware initializes
                    else if (!_isCameraReady)
                      Positioned.fromRect(
                        rect: rect,
                        child: Center(
                          child: GlassContainer(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            borderRadius: 20,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  "Starting camera...".tr(),
                                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              );
            },
          ),
          
          // 3. Interface HUD Overlays
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(LucideIcons.x, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const AddContactScreen()),
                          );
                        },
                        icon: const Icon(LucideIcons.pen, size: 14, color: Colors.white),
                        label: Text("Enter manually".tr(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          backgroundColor: Colors.white.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Pushes selector/info controls to bottom portion
                const Spacer(),
                
                // Selector for the 3 scanning modes
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTypeTab("QR Code", LucideIcons.qrCode),
                        const SizedBox(width: 8),
                        _buildTypeTab("Business Card", LucideIcons.contact),
                      ],
                    ),
                  ),
                ),
                
                if (!_isConnecting)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(40, 12, 40, 40),
                    child: GlassContainer(
                      padding: const EdgeInsets.all(24),
                      borderRadius: 24,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _scanType == "QR Code" ? "scan_qr_instruction".tr() : "scan_qr_align_card".tr(),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Flash Button (left)
                              IconButton(
                                icon: Icon(
                                  _isFlashOn ? LucideIcons.zap : LucideIcons.zapOff,
                                  color: _isFlashOn ? Colors.amber : Colors.white70,
                                  size: 24,
                                ),
                                onPressed: _toggleCameraFlash,
                                tooltip: "Toggle Flash",
                              ),
                              
                              // Shutter / Scan Button (center)
                              if (_scanType != "QR Code")
                                GestureDetector(
                                  onTap: _captureAndExtractText,
                                  child: Container(
                                    width: 68,
                                    height: 68,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 4),
                                    ),
                                    child: Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 68, height: 68),
                                
                              // Gallery Button (right)
                              IconButton(
                                icon: const Icon(
                                  LucideIcons.image,
                                  color: Colors.white70,
                                  size: 24,
                                ),
                                onPressed: _pickAndProcessFromGallery,
                                tooltip: "Scan from Gallery",
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sanitizeField(String value) {
    if (value.isEmpty) return "";
    
    // Strip common garbage prefix/suffix noise (e.g. leading/trailing pipe symbols, slashes, dashes, dots, commas, colons, brackets)
    String cleaned = value.trim();
    
    // Remove leading/trailing symbols, commas, pipes
    while (cleaned.isNotEmpty && RegExp(r'^[|/\-:,;().\[\]\s]').hasMatch(cleaned)) {
      cleaned = cleaned.substring(1).trim();
    }
    while (cleaned.isNotEmpty && RegExp(r'[|/\-:,;().\[\]\s]$').hasMatch(cleaned)) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    
    // Replace multiple spaces with a single space
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    
    // If the string is all uppercase capital words, convert to title casing for premium appearance
    if (cleaned.length > 1) {
      final words = cleaned.split(' ');
      if (words.every((w) => w == w.toUpperCase() && w.length > 1 && !w.contains(RegExp(r'[0-9]')))) {
        cleaned = words.map((w) {
          if (w.isEmpty) return "";
          return w[0] + w.substring(1).toLowerCase();
        }).join(' ');
      }
    }
    
    return cleaned;
  }
}

// Custom clipper creating a sharp transparent cutout inside a dark overlay (not rounded)
class ScannerOverlayClipper extends CustomClipper<Path> {
  final Rect cutoutRect;

  ScannerOverlayClipper({required this.cutoutRect});

  @override
  Path getClip(Size size) {
    final Path backgroundPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final Path cutoutPath = Path()..addRect(cutoutRect);
    return Path.combine(PathOperation.difference, backgroundPath, cutoutPath);
  }

  @override
  bool shouldReclip(covariant ScannerOverlayClipper oldClipper) {
    return oldClipper.cutoutRect != cutoutRect;
  }
}

// Custom Painter to draw white L-shaped marks strictly on the corners (sharp and un-rounded)
class ScannerCornersPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double cornerLength;

  ScannerCornersPainter({
    this.color = Colors.white,
    this.strokeWidth = 3.5,
    this.cornerLength = 24.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final double w = size.width;
    final double h = size.height;

    // Top-Left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, cornerLength)
        ..lineTo(0, 0)
        ..lineTo(cornerLength, 0),
      paint,
    );

    // Top-Right corner
    canvas.drawPath(
      Path()
        ..moveTo(w - cornerLength, 0)
        ..lineTo(w, 0)
        ..lineTo(w, cornerLength),
      paint,
    );

    // Bottom-Left corner
    canvas.drawPath(
      Path()
        ..moveTo(0, h - cornerLength)
        ..lineTo(0, h)
        ..lineTo(cornerLength, h),
      paint,
    );

    // Bottom-Right corner
    canvas.drawPath(
      Path()
        ..moveTo(w - cornerLength, h)
        ..lineTo(w, h)
        ..lineTo(w, h - cornerLength),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PremiumSpinner extends StatefulWidget {
  final double size;
  final Color color;
  const PremiumSpinner({super.key, this.size = 32, this.color = EventzoneTheme.primaryAction});

  @override
  State<PremiumSpinner> createState() => _PremiumSpinnerState();
}

class _PremiumSpinnerState extends State<PremiumSpinner> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: ShaderMask(
        shaderCallback: (rect) {
          return SweepGradient(
            colors: [widget.color.withOpacity(0.0), widget.color],
            stops: const [0.0, 1.0],
          ).createShader(rect);
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
        ),
      ),
    );
  }
}

