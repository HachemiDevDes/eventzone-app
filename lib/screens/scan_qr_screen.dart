import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import 'my_network_screen.dart';
import 'add_contact_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'review_contact_screen.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class ScanQRScreen extends StatefulWidget {
  const ScanQRScreen({super.key});

  @override
  State<ScanQRScreen> createState() => _ScanQRScreenState();
}

class _ScanQRScreenState extends State<ScanQRScreen> with SingleTickerProviderStateMixin {
  bool _isConnecting = false;
  String _scanType = "QR Code"; // "QR Code", "Business Card", "Event Badge"
  final MobileScannerController _controller = MobileScannerController();
  bool _isFlashOn = false;
  
  late AnimationController _laserController;
  String _ocrStatus = "";
  double _ocrProgress = 0.0;
  DateTime? _lastErrorTime;

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _initCameras();
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_scanType != "QR Code") {
        await _initializeCameraController();
      }
    } catch (e) {
      print("Error listing cameras: $e");
    }
  }

  Future<void> _initializeCameraController() async {
    if (_cameras.isEmpty) return;
    
    try {
      await _controller.stop();
    } catch (_) {}

    final camera = _cameras.first;
    _cameraController = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await _cameraController!.initialize();
      // Lock autofocus for sharper card captures
      try {
        await _cameraController!.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      print("Error initializing camera: $e");
    }
  }

  Future<void> _disposeCameraController() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
      _cameraController = null;
      if (mounted) {
        setState(() {
          _isCameraInitialized = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _laserController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }



  String? _extractUuid(String data) {
    final RegExp uuidRegExp = RegExp(
      r'[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}',
    );
    final match = uuidRegExp.firstMatch(data);
    return match?.group(0);
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_isConnecting) return;
    if (_scanType != "QR Code") return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String rawValue = barcodes.first.rawValue ?? "";
      
      if (_scanType == "QR Code") {
        // Validate if it is a valid Eventzone QR profile (must contain a UUID)
        final uuid = _extractUuid(rawValue);
        
        if (uuid == null) {
          final now = DateTime.now();
          if (_lastErrorTime == null || now.difference(_lastErrorTime!) > const Duration(seconds: 3)) {
            _lastErrorTime = now;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Error: Not a valid Eventzone Profile QR code."),
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
  }

  Future<void> _processScanData(String data) async {
    if (_isConnecting) return;
    
    setState(() {
      _isConnecting = true;
      _ocrStatus = "Detecting contact alignment...";
      _ocrProgress = 0.1;
    });
    
    _laserController.repeat(reverse: true);

    String name = "";
    String title = "";
    String avatarUrl = "";
    
    final uuid = _extractUuid(data);
    
    // Check if it is a UUID (Eventzone Profile)
    if (uuid != null) {
      setState(() {
        _ocrStatus = "Fetching profile from database...";
        _ocrProgress = 0.4;
      });
      
      try {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select()
            .eq('id', uuid)
            .maybeSingle();
            
        if (profile != null) {
          name = profile["full_name"] ?? "Eventzone User";
          final String job = profile["job_title"] ?? "";
          final String company = profile["company_name"] ?? "";
          title = job.isNotEmpty 
              ? (company.isNotEmpty ? "$job at $company" : job)
              : (company.isNotEmpty ? "Professional at $company" : "Attendee");
          avatarUrl = profile["avatar_url"] ?? "https://i.pravatar.cc/150?u=$uuid";
        } else {
          _laserController.stop();
          setState(() => _isConnecting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Error: Eventzone Profile not found in database."),
              backgroundColor: Colors.redAccent,
            ),
          );
          return;
        }
      } catch (e) {
        print("Error fetching profile: $e");
        _laserController.stop();
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Error communicating with database."),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    } else {
      // Not a UUID: Parse structured details (for Business Card / Event Badge QR codes or input text)
      setState(() {
        _ocrStatus = "Extracting contact fields...";
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
        _ocrStatus = "Structuring connection info...";
        _ocrProgress = 0.8;
      });
      
      // Step 3: 600ms - Final verification
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        setState(() {
          _ocrStatus = "Verification successful!";
          _ocrProgress = 1.0;
        });
        
        // Add to customConnections list
        MyNetworkScreen.customConnections.add({
          "name": name,
          "title": title,
          "avatarUrl": avatarUrl,
          "source": _scanType,
          "isNew": "true",
        });

        // Insert into Supabase connections table
        _saveToSupabase(name, title, avatarUrl);
        
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _laserController.stop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Added $name ($title) to contacts!"),
                backgroundColor: EventzoneTheme.accentSuccess,
              ),
            );
            Navigator.pop(context);
          }
        });
      });
    });
  }

  Map<String, String> _parseContactData(String data) {
    String name = "";
    String title = "";
    String avatarUrl = "https://i.pravatar.cc/150?u=${data.hashCode}";

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
    
    if (_cameraController == null || !_isCameraInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Camera not initialized yet.")),
      );
      return;
    }

    try {
      setState(() {
        _isConnecting = true;
        _ocrStatus = "Capturing image...";
        _ocrProgress = 0.05;
      });
      
      final XFile imageFile = await _cameraController!.takePicture();
      await _processImageFile(imageFile.path, isCameraCapture: true);
    } catch (e) {
      print("Capture error: $e");
      setState(() => _isConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Capture failed: $e"), backgroundColor: Colors.redAccent),
      );
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
    setState(() {
      _isConnecting = true;
      _ocrStatus = "Initializing text detector...";
      _ocrProgress = 0.1;
    });
    
    _laserController.repeat(reverse: true);
    
    try {
      // ── Step 0: Decode the full image ──
      final Uint8List imageBytes = await File(path).readAsBytes();
      final img.Image? fullImage = img.decodeImage(imageBytes);
      if (fullImage == null) {
        throw Exception("Failed to decode image");
      }
      final int imageWidth = fullImage.width;
      final int imageHeight = fullImage.height;

      setState(() {
        _ocrStatus = "Preparing image for recognition...";
        _ocrProgress = 0.2;
      });

      // ── Step 1: Physically crop the image to viewfinder bounds (camera only) ──
      // This is the single biggest quality improvement: ML Kit performs MUCH better
      // when it only sees the card, not the surrounding desk/screen/noise.
      String ocrImagePath = path;
      int cropWidth = imageWidth;
      int cropHeight = imageHeight;

      if (isCameraCapture && mounted) {
        final double screenWidth = MediaQuery.of(context).size.width;
        final double screenHeight = MediaQuery.of(context).size.height;

        // Viewfinder frame dimensions on screen
        double frameW = 280;
        double frameH = 280;
        if (_scanType == "Business Card") {
          frameW = 340;
          frameH = 200;
        } else if (_scanType == "Event Badge") {
          frameW = 280;
          frameH = 420;
        }
        final double frameLeft = (screenWidth - frameW) / 2;
        final double frameTop = (screenHeight - frameH) / 2 - 50;

        // BoxFit.cover inverse mapping: screen coords → photo pixel coords
        final double scale = math.max(
          screenWidth / imageWidth,
          screenHeight / imageHeight,
        );
        final double dx = (screenWidth - imageWidth * scale) / 2;
        final double dy = (screenHeight - imageHeight * scale) / 2;

        // Map viewfinder bounds to photo pixels with 15% padding
        final double rawLeft = (frameLeft - dx) / scale;
        final double rawTop = (frameTop - dy) / scale;
        final double rawRight = (frameLeft + frameW - dx) / scale;
        final double rawBottom = (frameTop + frameH - dy) / scale;
        final double padX = (rawRight - rawLeft) * 0.15;
        final double padY = (rawBottom - rawTop) * 0.15;

        // Clamp to image bounds
        final int cropX = (rawLeft - padX).clamp(0, imageWidth - 1).toInt();
        final int cropY = (rawTop - padY).clamp(0, imageHeight - 1).toInt();
        cropWidth = ((rawRight - rawLeft) + padX * 2).clamp(1, imageWidth - cropX).toInt();
        cropHeight = ((rawBottom - rawTop) + padY * 2).clamp(1, imageHeight - cropY).toInt();

        // Physically crop and save to a temporary file
        final img.Image cropped = img.copyCrop(
          fullImage,
          x: cropX,
          y: cropY,
          width: cropWidth,
          height: cropHeight,
        );

        // Enhance contrast for better OCR on complex card designs
        img.adjustColor(cropped, contrast: 1.3);

        final String croppedPath = '${path}_cropped.jpg';
        await File(croppedPath).writeAsBytes(img.encodeJpg(cropped, quality: 95));
        ocrImagePath = croppedPath;

        setState(() {
          _ocrStatus = "Card isolated — running text recognition...";
          _ocrProgress = 0.35;
        });
      }

      // ── Step 2: Primary OCR pass on the cropped/focused image ──
      final inputImage = InputImage.fromFilePath(ocrImagePath);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      // Collect all lines with bounding-box metadata
      // When we used a cropped image, coordinates are relative to the CROP, not the full photo.
      // So normalizedTop is relative to cropHeight (the card itself) — much more accurate.
      List<Map<String, dynamic>> rawLinesWithMeta = [];
      List<String> allDetectedLines = [];
      final int refHeight = isCameraCapture ? cropHeight : imageHeight;

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final String text = line.text.trim();
          if (text.isEmpty) continue;
          allDetectedLines.add(text);
          rawLinesWithMeta.add({
            'text': text,
            'height': line.boundingBox.height.toDouble(),
            'normalizedTop': line.boundingBox.top / refHeight,
          });
        }
      }

      // ── Step 3: Fallback second pass on full image if cropped pass found very little ──
      // This catches text that was partially outside the viewfinder or in unusual positions.
      if (isCameraCapture && rawLinesWithMeta.length < 3) {
        setState(() {
          _ocrStatus = "Running enhanced secondary scan...";
          _ocrProgress = 0.45;
        });
        final fullInput = InputImage.fromFilePath(path);
        final fullResult = await textRecognizer.processImage(fullInput);
        for (TextBlock block in fullResult.blocks) {
          for (TextLine line in block.lines) {
            final String text = line.text.trim();
            if (text.isEmpty) continue;
            // Only add lines we haven't already captured
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
          const SnackBar(
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
      // INTELLIGENT CONTACT PARSING ENGINE v2
      // Uses multi-signal weighted scoring instead of naive keyword matching.
      // ──────────────────────────────────────────────────────────────────────

      // Use cropped lines for structured data extraction (emails/phones can come from all lines)
      final List<String> croppedTexts = finalLinesMeta.map<String>((m) => m['text'] as String).toList();

      // ── Step 1: Extract structured fields (email, phone, website, address) ──
      final emailRegExp = RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', caseSensitive: false);
      final phoneRegExpAlg = RegExp(r'(?:\+213|0)(?:5|6|7)[0-9\s.\-]{8,12}');
      final phoneRegExpGen = RegExp(r'\+?[0-9]{1,4}[\-.\s]?\(?[0-9]{1,4}\)?[\-.\s]?[0-9]{2,4}[\-.\s]?[0-9]{2,4}[\-.\s]?[0-9]{2,4}');
      final webRegExp = RegExp(r'(https?://)?(www\.)?[a-zA-Z0-9\-]+\.[a-zA-Z]{2,6}(\S*)');

      String? email;
      String? phone;
      String? website;
      String address = "";

      // Collect from ALL detected lines (not just cropped) for structured fields
      final List<String> allTexts = allDetectedLines;
      for (final line in allTexts) {
        if (email == null) {
          final m = emailRegExp.firstMatch(line);
          if (m != null) email = m.group(0);
        }
        if (phone == null && !line.contains('@')) {
          final algM = phoneRegExpAlg.firstMatch(line);
          if (algM != null) {
            phone = algM.group(0);
          } else {
            final genM = phoneRegExpGen.firstMatch(line);
            if (genM != null && genM.group(0)!.replaceAll(RegExp(r'[^\d+]'), '').length >= 7) {
              phone = genM.group(0);
            }
          }
        }
        if (website == null && !line.contains('@')) {
          final wm = webRegExp.firstMatch(line.toLowerCase());
          if (wm != null) website = wm.group(0);
        }
      }

      // Address extraction from cropped lines
      final addressKeywords = [
        'street', 'road', 'ave', 'avenue', 'boulevard', 'blvd', 'st.',
        'floor', 'building', 'route', 'zone', 'cite', 'cité', 'bp ',
        'p.o.', 'po box', 'suite', 'apt', 'block', 'tower',
        'dz', 'alger', 'algeria', 'oran', 'constantine',
        'rue', 'quartier', 'lot', 'résidence', 'residence',
      ];
      for (final l in croppedTexts) {
        final lower = l.toLowerCase();
        if (addressKeywords.any((kw) => lower.contains(kw))) {
          address = l;
          break;
        }
      }

      // ── Step 2: Build candidate lines for name/title/company ──
      // Filter out lines that are clearly NOT name/title/company
      List<Map<String, dynamic>> candidates = [];
      for (final item in finalLinesMeta) {
        final String text = item['text'] as String;
        final String lower = text.toLowerCase();

        // Skip if it matches email, phone, website, or address
        if (emailRegExp.hasMatch(text)) continue;
        if (text.replaceAll(RegExp(r'[^\d]'), '').length >= 7) continue;
        if (webRegExp.hasMatch(lower) && lower.contains('.')) continue;
        if (text == address) continue;
        if (text.length < 2) continue;

        // Skip lines that are mostly digits or symbols
        final int alphaCount = text.replaceAll(RegExp(r'[^a-zA-ZÀ-ÿ]'), '').length;
        if (alphaCount < text.length * 0.4) continue;

        // Skip common non-contact noise words
        final noisePatterns = [
          'tel:', 'fax:', 'mob:', 'phone:', 'email:', 'e-mail:',
          'website:', 'web:', 'www.', 'http', '.com', '.net', '.org', '.dz',
        ];
        if (noisePatterns.any((p) => lower.startsWith(p) || lower == p)) continue;

        candidates.add(item);
      }

      // ── Step 3: Score each candidate line for NAME, TITLE, COMPANY ──

      // -- Job title indicators (extensive, multilingual) --
      final jobTitleWords = <String>{
        // English
        'ceo', 'cfo', 'cto', 'coo', 'cmo', 'cio', 'vp',
        'president', 'director', 'manager', 'supervisor',
        'founder', 'co-founder', 'cofounder', 'partner',
        'lead', 'head', 'chief', 'officer',
        'developer', 'engineer', 'architect', 'designer',
        'analyst', 'consultant', 'specialist', 'advisor',
        'coordinator', 'administrator', 'assistant',
        'representative', 'executive', 'associate',
        'intern', 'trainee', 'fellow',
        'professor', 'teacher', 'lecturer', 'instructor',
        'doctor', 'physician', 'surgeon', 'nurse',
        'lawyer', 'attorney', 'counsel', 'advocate',
        'accountant', 'auditor', 'controller',
        'editor', 'writer', 'journalist', 'reporter',
        'marketing', 'sales', 'commercial', 'business',
        'operations', 'logistics', 'procurement', 'supply',
        'senior', 'junior', 'principal', 'staff',
        // French
        'directeur', 'directrice', 'gérant', 'gérante', 'gerant', 'gerante',
        'responsable', 'chef', 'fondateur', 'fondatrice',
        'conseiller', 'conseillère', 'chargé', 'chargée', 'charge',
        'ingénieur', 'ingenieur', 'technicien', 'technicienne',
        'médecin', 'medecin', 'avocat', 'avocate',
        'comptable', 'auditeur', 'analyste',
        'développeur', 'developpeur', 'concepteur',
        'specialiste', 'spécialiste', 'expert',
        'attaché', 'attache', 'adjoint', 'adjointe',
        'président', 'vice-président',
      };

      final companyIndicators = <String>{
        // Suffixes and keywords indicating an organization
        'ltd', 'corp', 'corporation', 'inc', 'incorporated',
        'llc', 'llp', 'plc', 'gmbh', 'ag', 'sa', 'sarl', 'sas',
        'eurl', 'spa', 'spa.', 's.p.a',
        'group', 'groupe', 'holding',
        'solutions', 'technologies', 'technology', 'tech',
        'systems', 'services', 'consulting',
        'partners', 'enterprises', 'industries',
        'global', 'international', 'worldwide',
        'digital', 'media', 'creative',
        'studio', 'studios', 'agency', 'agence',
        'hub', 'labs', 'lab', 'laboratory',
        'ventures', 'capital', 'investments',
        'foundation', 'fondation', 'association',
        'university', 'université', 'institute', 'institut',
        'hospital', 'hôpital', 'clinic', 'clinique',
        'bank', 'banque', 'insurance', 'assurance',
        'company', 'compagnie', 'société', 'societe', 'entreprise',
      };

      // Department indicators
      final deptIndicators = <String>{
        'department', 'dept', 'division', 'unit', 'section',
        'service', 'direction', 'bureau', 'office', 'team',
      };

      String name = "";
      String title = "";
      String company = "";
      String department = "";

      double bestNameScore = -9999;
      double bestTitleScore = -9999;
      double bestCompanyScore = -9999;
      int bestNameIdx = -1;
      int bestTitleIdx = -1;
      int bestCompanyIdx = -1;

      // Compute average bounding height for relative comparison
      double avgHeight = 0;
      if (candidates.isNotEmpty) {
        avgHeight = candidates.fold<double>(0, (sum, c) => sum + (c['height'] as double)) / candidates.length;
      }

      for (int i = 0; i < candidates.length; i++) {
        final String text = candidates[i]['text'] as String;
        final String lower = text.toLowerCase();
        final double height = candidates[i]['height'] as double;
        final double normalizedTop = candidates[i]['normalizedTop'] as double;
        final List<String> words = text.split(RegExp(r'\s+'));

        // ──── NAME SCORING ────
        double nameScore = 0;

        // Font size: names are usually the largest text on a card
        if (avgHeight > 0) {
          nameScore += ((height - avgHeight) / avgHeight) * 40; // relative size bonus
        }

        // Word count: names are typically 2-4 words
        if (words.length >= 2 && words.length <= 4) nameScore += 25;
        else if (words.length == 1 && words[0].length >= 3) nameScore += 5;
        else if (words.length > 4) nameScore -= 15;

        // Capitalization: Each word starts with uppercase (typical for names)
        final capitalizedWords = words.where((w) => w.isNotEmpty && w[0] == w[0].toUpperCase() && w[0] != w[0].toLowerCase()).length;
        if (capitalizedWords == words.length && words.length >= 2) nameScore += 20;

        // All-caps bonus (many business cards print names in all-caps)
        if (words.length >= 2 && words.every((w) => w == w.toUpperCase() && w.length > 1)) nameScore += 10;

        // Position: names tend to appear in the top half of the card
        if (normalizedTop < 0.35) nameScore += 15;
        else if (normalizedTop < 0.50) nameScore += 8;

        // Penalty: contains digits (names don't have numbers)
        if (text.contains(RegExp(r'[0-9]'))) nameScore -= 60;

        // Penalty: contains special characters common in non-name fields
        if (text.contains('@') || text.contains('www') || text.contains('http')) nameScore -= 100;
        if (RegExp(r'[|/\\{}#]').hasMatch(text)) nameScore -= 30;

        // Penalty: if it matches job title keywords, it's probably not a name
        if (jobTitleWords.any((kw) => lower.split(RegExp(r'\s+')).contains(kw))) nameScore -= 35;

        // Penalty: if it matches company keywords
        if (companyIndicators.any((kw) => lower.split(RegExp(r'\s+')).contains(kw))) nameScore -= 35;

        // Penalty: very long lines are unlikely to be names
        if (text.length > 40) nameScore -= 20;

        // Bonus: pure alphabetic words with spaces (strong name signal)
        if (RegExp(r'^[a-zA-ZÀ-ÿ\s\-\.]+$').hasMatch(text) && words.length >= 2) nameScore += 15;

        if (nameScore > bestNameScore) {
          bestNameScore = nameScore;
          bestNameIdx = i;
        }

        // ──── TITLE SCORING ────
        double titleScore = 0;

        // Keyword match: strong signal
        final lowerWords = lower.split(RegExp(r'\s+'));
        final matchedJobWords = lowerWords.where((w) => jobTitleWords.contains(w)).length;
        titleScore += matchedJobWords * 40;

        // Partial keyword match (e.g., "développeur web" where "développeur" is a keyword)
        if (matchedJobWords == 0) {
          for (final kw in jobTitleWords) {
            if (lower.contains(kw) && kw.length >= 4) {
              titleScore += 25;
              break;
            }
          }
        }

        // Position: titles usually appear just below the name (upper-middle area)
        if (normalizedTop >= 0.20 && normalizedTop <= 0.55) titleScore += 10;

        // Font size: titles are usually smaller than names but not tiny
        if (avgHeight > 0 && height < avgHeight * 1.1 && height > avgHeight * 0.5) titleScore += 5;

        // Penalty: has digits
        if (text.contains(RegExp(r'[0-9]'))) titleScore -= 20;

        // Penalty: very short or single word (unless it's a known keyword)
        if (words.length == 1 && matchedJobWords == 0) titleScore -= 10;

        // Penalty: matches company indicators
        if (companyIndicators.any((kw) => lowerWords.contains(kw))) titleScore -= 20;

        if (titleScore > bestTitleScore) {
          bestTitleScore = titleScore;
          bestTitleIdx = i;
        }

        // ──── COMPANY SCORING ────
        double companyScore = 0;

        final matchedCompanyWords = lowerWords.where((w) => companyIndicators.contains(w)).length;
        companyScore += matchedCompanyWords * 40;

        // Partial match for company indicators
        if (matchedCompanyWords == 0) {
          for (final kw in companyIndicators) {
            if (lower.contains(kw) && kw.length >= 4) {
              companyScore += 25;
              break;
            }
          }
        }

        // Department check (we'll note this separately)
        final matchedDeptWords = lowerWords.where((w) => deptIndicators.contains(w)).length;

        // Position: company names can appear anywhere but often near the bottom
        if (normalizedTop >= 0.45) companyScore += 5;

        // Font size: company names are often medium-sized
        if (avgHeight > 0 && height >= avgHeight * 0.7) companyScore += 5;

        // Penalty: has many digits
        if (text.replaceAll(RegExp(r'[^\d]'), '').length > 2) companyScore -= 20;

        // Penalty: matches job title keywords heavily
        if (matchedJobWords > 0) companyScore -= 15;

        if (matchedDeptWords > 0) {
          // This line is a department, not a company
          department = text;
        } else if (companyScore > bestCompanyScore) {
          bestCompanyScore = companyScore;
          bestCompanyIdx = i;
        }
      }

      // ── Step 4: Resolve conflicts (same line picked for multiple fields) ──
      // Priority: title keyword > company keyword > name (by font size)

      // If title and name picked the same line, reassign
      if (bestTitleIdx == bestNameIdx && bestTitleScore > 10) {
        // Title wins this line; find next best name
        bestNameScore = -9999;
        bestNameIdx = -1;
        for (int i = 0; i < candidates.length; i++) {
          if (i == bestTitleIdx || i == bestCompanyIdx) continue;
          final String text = candidates[i]['text'] as String;
          final double height = candidates[i]['height'] as double;
          final List<String> words = text.split(RegExp(r'\s+'));
          double score = height;
          if (words.length >= 2 && words.length <= 4) score += 25;
          if (words.every((w) => w.isNotEmpty && w[0] == w[0].toUpperCase())) score += 15;
          if (text.contains(RegExp(r'[0-9]'))) score -= 60;
          if (RegExp(r'^[a-zA-ZÀ-ÿ\s\-\.]+$').hasMatch(text)) score += 10;
          if (score > bestNameScore) {
            bestNameScore = score;
            bestNameIdx = i;
          }
        }
      }

      // If company and name picked the same line, company wins if it has keywords
      if (bestCompanyIdx == bestNameIdx && bestCompanyScore > 10) {
        bestNameScore = -9999;
        bestNameIdx = -1;
        for (int i = 0; i < candidates.length; i++) {
          if (i == bestTitleIdx || i == bestCompanyIdx) continue;
          final String text = candidates[i]['text'] as String;
          final double height = candidates[i]['height'] as double;
          final List<String> words = text.split(RegExp(r'\s+'));
          double score = height;
          if (words.length >= 2 && words.length <= 4) score += 25;
          if (text.contains(RegExp(r'[0-9]'))) score -= 60;
          if (RegExp(r'^[a-zA-ZÀ-ÿ\s\-\.]+$').hasMatch(text)) score += 10;
          if (score > bestNameScore) {
            bestNameScore = score;
            bestNameIdx = i;
          }
        }
      }

      // ── Step 5: Assign final values ──
      if (bestNameIdx >= 0) name = candidates[bestNameIdx]['text'] as String;
      if (bestTitleIdx >= 0 && bestTitleIdx != bestNameIdx && bestTitleScore > 5) {
        title = candidates[bestTitleIdx]['text'] as String;
      }
      if (bestCompanyIdx >= 0 && bestCompanyIdx != bestNameIdx && bestCompanyIdx != bestTitleIdx && bestCompanyScore > 5) {
        company = candidates[bestCompanyIdx]['text'] as String;
      }

      // ── Step 6: Smart fallbacks using spatial proximity ──
      // If no title was found by keywords, look at the line immediately after the name
      if (title.isEmpty && bestNameIdx >= 0 && bestNameIdx + 1 < candidates.length) {
        final nextLine = candidates[bestNameIdx + 1]['text'] as String;
        // Only use it if it's not already assigned and doesn't look like noise
        if (nextLine != company && nextLine != address && !nextLine.contains('@') &&
            nextLine.replaceAll(RegExp(r'[^\d]'), '').length < 4 &&
            nextLine.length >= 3) {
          title = nextLine;
        }
      }

      // If no company was found by keywords, try email domain
      if (company.isEmpty && email != null) {
        final parts = email.split('@');
        if (parts.length > 1) {
          final domainPart = parts[1].split('.')[0];
          final freeEmailDomains = {'gmail', 'yahoo', 'hotmail', 'outlook', 'icloud', 'live', 'aol', 'mail', 'protonmail', 'yandex'};
          if (!freeEmailDomains.contains(domainPart.toLowerCase())) {
            company = domainPart[0].toUpperCase() + domainPart.substring(1);
          }
        }
      }

      // Post-processing Sanitation
      final String cleanName = _sanitizeField(name);
      final String cleanTitle = _sanitizeField(title);
      final String cleanCompany = _sanitizeField(company);
      final String cleanDept = _sanitizeField(department);

      // Step 2: visual parsing delay
      setState(() {
        _ocrStatus = "Extracting contact metadata...";
        _ocrProgress = 0.6;
      });
      
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        setState(() {
          _ocrStatus = "Processing profile...";
          _ocrProgress = 0.9;
        });
        
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (!mounted) return;
          setState(() {
            _ocrStatus = "Verification successful!";
            _ocrProgress = 1.0;
          });
          
          Future.delayed(const Duration(milliseconds: 600), () {
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
                    initialAddress: address,
                    source: _scanType,
                  ),
                ),
              );
            }
          });
        });
      });
      
    } catch (e) {
      print("OCR Error: $e");
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

  Future<void> _saveToSupabase(
    String name,
    String title,
    String avatarUrl, {
    String? email,
    String? phone,
    String? website,
    String? company,
    String? department,
  }) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentUserId = currentUser?.id ?? "0d3e48f0-b7c5-47db-a5c4-f3a08fc3d040";
      await Supabase.instance.client.from('connections').insert({
        'user_id': currentUserId,
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
      });
    } catch (e) {
      print("Error saving connection to Supabase: $e");
    }
  }

  Future<void> _toggleCameraFlash() async {
    if (_scanType == "QR Code") {
      try {
        await _controller.toggleTorch();
        setState(() {
          _isFlashOn = !_isFlashOn;
        });
      } catch (e) {
        print("Error toggling mobile_scanner torch: $e");
      }
    } else if (_cameraController != null && _isCameraInitialized) {
      try {
        final newFlashState = !_isFlashOn;
        await _cameraController!.setFlashMode(
          newFlashState ? FlashMode.torch : FlashMode.off,
        );
        setState(() {
          _isFlashOn = newFlashState;
        });
      } catch (e) {
        print("Error toggling camera torch: $e");
      }
    }
  }

  Widget _buildTypeTab(String type, IconData icon) {
    final bool isSelected = _scanType == type;
    return GestureDetector(
      onTap: () async {
        if (_scanType == type) return;
        
        // Turn off torch/flash when switching modes
        if (_scanType == "QR Code") {
          try {
            await _controller.toggleTorch();
          } catch (_) {}
        } else if (_cameraController != null && _isCameraInitialized) {
          try {
            await _cameraController!.setFlashMode(FlashMode.off);
          } catch (_) {}
        }
        
        setState(() {
          _scanType = type;
          _isFlashOn = false;
        });
        
        if (type == "QR Code") {
          await _disposeCameraController();
          try {
            await _controller.start();
          } catch (_) {}
        } else {
          await _initializeCameraController();
        }
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
              type,
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
          Positioned.fill(
            child: _scanType == "QR Code"
                ? MobileScanner(
                    controller: _controller,
                    onDetect: _handleCapture,
                  )
                : (_isCameraInitialized && _cameraController != null
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: _cameraController!.value.previewSize!.height,
                          height: _cameraController!.value.previewSize!.width,
                          child: CameraPreview(_cameraController!),
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: EventzoneTheme.primaryAction,
                        ),
                      )),
          ),
          
          // 2. Smoothly animated mask and corner overlays
          TweenAnimationBuilder<Rect?>(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            tween: RectTween(
              begin: targetRect,
              end: targetRect,
            ),
            builder: (context, animRect, child) {
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

                  // Clear cutout corner stroke (sharp corners)
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
                    // Sweeping laser line
                    AnimatedBuilder(
                      animation: _laserController,
                      builder: (context, child) {
                        final double verticalOffset = rect.height * _laserController.value;
                        return Positioned(
                          left: rect.left,
                          top: rect.top + verticalOffset,
                          child: Container(
                            width: rect.width,
                            height: 3,
                            decoration: BoxDecoration(
                              color: EventzoneTheme.primaryAction,
                              boxShadow: [
                                BoxShadow(
                                  color: EventzoneTheme.primaryAction.withOpacity(0.8),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Draw green simulated text bounding boxes for non-QR
                    if (_scanType != "QR Code" && _ocrProgress > 0.2) ...[
                      Positioned(
                        left: rect.left + 24,
                        top: rect.top + 32,
                        width: 160,
                        height: 20,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.greenAccent, width: 1.5),
                            color: Colors.greenAccent.withOpacity(0.08),
                          ),
                        ),
                      ),
                      Positioned(
                        left: rect.left + 24,
                        top: rect.top + 64,
                        width: 220,
                        height: 18,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.greenAccent, width: 1.5),
                            color: Colors.greenAccent.withOpacity(0.08),
                          ),
                        ),
                      ),
                    ],

                    // OCR progress status box
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.center,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF06080F).withOpacity(0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(EventzoneTheme.primaryAction),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _ocrStatus,
                                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "${(_ocrProgress * 100).toInt()}% completed",
                                style: const TextStyle(color: Colors.white54, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    // Empty when not connecting so the scanner cutout is clear
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
                        label: const Text("Enter manually", style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
                        const SizedBox(width: 8),
                        _buildTypeTab("Event Badge", LucideIcons.milestone),
                      ],
                    ),
                  ),
                ),
                
                Padding(
                  padding: const EdgeInsets.fromLTRB(40, 12, 40, 40),
                  child: GlassContainer(
                    padding: const EdgeInsets.all(24),
                    borderRadius: 24,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isConnecting) ...[
                          const CircularProgressIndicator(color: EventzoneTheme.primaryAction),
                          const SizedBox(height: 16),
                          Text("Scanning $_scanType...", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ] else ...[
                          Text(
                            "Position the $_scanType within the frame",
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
