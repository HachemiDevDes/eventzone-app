import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ScannedBusinessCard {
  final String name;
  final String title;
  final String company;
  final String? department;
  final String email;
  final String phone;
  final String? website;
  final String? address;
  final String? notes;
  final bool isBusinessCard;
  final String? confidence;
  final bool hasVisualChallenges;

  const ScannedBusinessCard({
    required this.name,
    required this.title,
    required this.company,
    this.department,
    required this.email,
    required this.phone,
    this.website,
    this.address,
    this.notes,
    this.isBusinessCard = true,
    this.confidence,
    this.hasVisualChallenges = false,
  });

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is List) {
      final joined = value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join('\n');
      return joined.isEmpty ? null : joined;
    }
    final str = value.toString().trim();
    return str.isEmpty ? null : str;
  }

  factory ScannedBusinessCard.fromJson(Map<String, dynamic> json) {
    final rawDept = _parseString(json['department']);
    final rawAddr = _parseString(json['address']);
    final rawNotes = _parseString(json['notes']);
    final rawName = _parseString(json['name']) ?? '';
    final rawTitle = _parseString(json['title']) ?? '';
    final rawCompany = _parseString(json['company']) ?? '';

    return ScannedBusinessCard(
      name: rawName,
      title: rawTitle,
      company: rawCompany,
      department: rawDept,
      email: BusinessCardScannerService.normalizeEmail(_parseString(json['email'])) ?? '',
      phone: BusinessCardScannerService.normalizePhone(_parseString(json['phone'])) ?? '',
      website: BusinessCardScannerService.normalizeWebsite(_parseString(json['website'])),
      address: rawAddr,
      notes: rawNotes,
      isBusinessCard: json['is_business_card'] == true,
      confidence: json['confidence'] as String?,
      hasVisualChallenges: json['has_visual_challenges'] == true,
    );
  }

  bool get isEmpty =>
      name.isEmpty &&
      company.isEmpty &&
      email.isEmpty &&
      phone.isEmpty &&
      title.isEmpty;
}

class BusinessCardScannerResult {
  final bool isSuccess;
  final bool isNotBusinessCard;
  final String? errorMessage;
  final ScannedBusinessCard? card;
  final String? modelUsed;
  final bool escalated;
  final String? confidence;

  const BusinessCardScannerResult({
    required this.isSuccess,
    this.isNotBusinessCard = false,
    this.errorMessage,
    this.card,
    this.modelUsed,
    this.escalated = false,
    this.confidence,
  });

  factory BusinessCardScannerResult.success(
    ScannedBusinessCard card, {
    String? modelUsed,
    bool escalated = false,
    String? confidence,
  }) {
    return BusinessCardScannerResult(
      isSuccess: true,
      card: card,
      modelUsed: modelUsed,
      escalated: escalated,
      confidence: confidence,
    );
  }

  factory BusinessCardScannerResult.notBusinessCard([
    String? message,
    String? modelUsed,
    bool escalated = false,
  ]) {
    return BusinessCardScannerResult(
      isSuccess: false,
      isNotBusinessCard: true,
      errorMessage: message ?? 'No business card or credential badge detected in the image.',
      modelUsed: modelUsed,
      escalated: escalated,
    );
  }

  factory BusinessCardScannerResult.failure(String error) {
    return BusinessCardScannerResult(
      isSuccess: false,
      errorMessage: error,
    );
  }
}

class BusinessCardScannerService {
  static final BusinessCardScannerService _instance =
      BusinessCardScannerService._internal();

  factory BusinessCardScannerService() => _instance;

  BusinessCardScannerService._internal();

  /// Normalizes email addresses: strips internal whitespace (e.g. user @ domain.com),
  /// fixes optical commas (e.g. user@domain,com -> user@domain.com), and cleans surrounding delimiters and trailing punctuation.
  /// Accepts nullable String? and returns clean nullable String? (null if empty or absent).
  static String? normalizeEmail(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.toLowerCase().startsWith('mailto:')) {
      cleaned = cleaned.substring(7).trim();
    }
    // Remove internal spaces
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), '');
    // Strip leading/trailing brackets, quotes, punctuation
    cleaned = cleaned.replaceAll(RegExp(r'^[<(\["\s]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[>)\]"\s.,;:]+$'), '');
    // Fix optical commas commonly read instead of periods
    cleaned = cleaned.replaceAll(',', '.');
    // Fix accidental double periods (e.g. name@domain..com -> name@domain.com)
    cleaned = cleaned.replaceAll(RegExp(r'\.{2,}'), '.');
    // Final trim of trailing punctuation or brackets
    cleaned = cleaned.replaceAll(RegExp(r'[.,;:>)\s]+$'), '');
    cleaned = cleaned.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Normalizes phone numbers: preserves leading '+', removes label prefixes (Tel, Tél, Mob, GSM, Fax, etc.),
  /// handles international brackets e.g. (+213), and strips non-dialable stray OCR characters.
  /// Accepts nullable String? and returns clean nullable String? (null if empty or absent).
  static String? normalizePhone(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    // Strip common label prefixes (English, French, etc.)
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^(tél|tel|téléphone|telephone|phone|mob|mobile|cell|portable|port|gsm|fixe|fax|p|m|t)'
        r'(\s*[\/&,]\s*(fax|tel|tél|mob|mobile|cell|phone|fixe|t|m|p))?'
        r'\s*[:.\-]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    // Detect if international '+' was present anywhere in raw or cleaned phone
    final hasPlus = cleaned.contains('+');

    // Handle patterns like "(+213)" -> normalize to "+213 "
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\(\s*\+(\d+)\s*\)'),
      (match) => '+${match.group(1)} ',
    );

    // Remove non-dialable stray characters (preserve digits, spaces, -, (, ), ., /)
    cleaned = cleaned.replaceAll(RegExp(r'[^\d+\s\-()./]'), '');

    // Ensure single leading '+' if international
    if (hasPlus) {
      cleaned = '+${cleaned.replaceAll('+', '').trim()}';
    } else {
      cleaned = cleaned.replaceAll('+', '').trim();
    }

    // Trim trailing separators or punctuation
    cleaned = cleaned.replaceAll(RegExp(r'[.\-\s/]+$'), '');

    // Normalize multiple consecutive spaces
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');

    cleaned = cleaned.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Normalizes website URLs: trims label prefixes (Web:, Site:, etc.), internal whitespace,
  /// optical commas, trailing periods, commas, or trailing slashes.
  /// Accepts nullable String? and returns clean nullable String? (null if empty or absent).
  static String? normalizeWebsite(String? raw) {
    if (raw == null) return null;
    var cleaned = raw.trim();
    if (cleaned.isEmpty) return null;

    // Strip common label prefixes
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^(site\s*web|site|website|web|url)\s*[:.\-]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    // Strip surrounding brackets or quotes
    cleaned = cleaned.replaceAll(RegExp(r'^[<(\["\s]+|[>)\]"\s]+$'), '');

    // Remove internal spaces (URLs never contain spaces)
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), '');

    // Fix optical commas read instead of periods (e.g. www,eventzone,dz)
    if (!cleaned.contains('?')) {
      cleaned = cleaned.replaceAll(',', '.');
    }

    // Trim trailing punctuation and slashes (loop until clean)
    while (cleaned.isNotEmpty && RegExp(r'[.,;:"/]$').hasMatch(cleaned)) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    cleaned = cleaned.trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Scans a business card or badge image using GPT-4o via the Eventzone Supabase Edge Function.
  Future<BusinessCardScannerResult> scanCardImage(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        return BusinessCardScannerResult.failure('Image file does not exist');
      }

      // 1. Prepare image bytes:
      // If the image was already cropped by the viewfinder isolate, it is already oriented and compressed.
      // Avoid re-compressing it, which adds unnecessary delay. Otherwise, compress to max 1600px at quality 88.
      Uint8List finalBytes;
      String mimeType = 'image/jpeg';
      final isAlreadyCropped = imageFile.path.endsWith('_card_crop.jpg');

      if (isAlreadyCropped) {
        finalBytes = await imageFile.readAsBytes();
        mimeType = 'image/jpeg';
      } else {
        Uint8List? compressedBytes;
        try {
          compressedBytes = await FlutterImageCompress.compressWithFile(
            imageFile.path,
            minWidth: 1600,
            minHeight: 1600,
            quality: 90,
            autoCorrectionAngle: true,
            format: CompressFormat.jpeg,
          );
        } catch (e) {
          debugPrint('[BusinessCardScanner] Compression / rotation error (fallback to raw bytes): $e');
        }

        if (compressedBytes != null && compressedBytes.isNotEmpty) {
          finalBytes = compressedBytes;
          mimeType = 'image/jpeg';
        } else {
          // Fallback: Read raw bytes and detect MIME from file extension
          finalBytes = await imageFile.readAsBytes();
          final pathLower = imageFile.path.toLowerCase();
          if (pathLower.endsWith('.png')) {
            mimeType = 'image/png';
          } else if (pathLower.endsWith('.webp')) {
            mimeType = 'image/webp';
          } else if (pathLower.endsWith('.heic') || pathLower.endsWith('.heif')) {
            mimeType = 'image/heic';
          } else {
            mimeType = 'image/jpeg';
          }
        }
      }

      final String base64Image = base64Encode(finalBytes);

      // 2. Pure AI Vision extraction via Eventzone Supabase Edge Function with GPT-4o
      final response = await Supabase.instance.client.functions.invoke(
        'scan-business-card',
        body: {
          'image_base64': base64Image,
          'mime_type': mimeType,
          'model': 'gpt-4o',
        },
      ).timeout(
        const Duration(seconds: 35),
        onTimeout: () => throw TimeoutException('Network timed out while communicating with the AI service.'),
      );

      if (response.status != 200) {
        final errorMsg = response.data is Map
            ? (response.data['error'] ?? 'Edge Function error')
            : 'Edge Function status ${response.status}';
        return BusinessCardScannerResult.failure(errorMsg.toString());
      }

      final dynamic rawData = response.data;
      if (rawData is! Map) {
        return BusinessCardScannerResult.failure('Invalid response format from server');
      }
      final Map<String, dynamic> data = Map<String, dynamic>.from(rawData);

      final meta = data['meta'] as Map<String, dynamic>?;
      final modelUsed = meta?['model_used'] as String? ?? 'gpt-4o';
      final escalated = meta?['escalated'] as bool? ?? false;
      final confidence = meta?['confidence'] as String?;
      debugPrint('[BusinessCardScanner] Model used: $modelUsed (escalated: $escalated, confidence: $confidence)');

      if (data['is_business_card'] == false || data['error'] == 'not_a_business_card') {
        final msg = data['message'] as String? ??
            'The scanned image does not appear to be a business card or credential badge.';
        return BusinessCardScannerResult.notBusinessCard(msg, modelUsed, escalated);
      }

      final dynamic rawCard = data['data'];
      if (data['success'] == true && rawCard is Map) {
        final cardData = Map<String, dynamic>.from(rawCard);
        final card = ScannedBusinessCard.fromJson(cardData);
        return BusinessCardScannerResult.success(
          card,
          modelUsed: modelUsed,
          escalated: escalated,
          confidence: confidence,
        );
      }

      return BusinessCardScannerResult.failure(
        data['error']?.toString() ?? 'Unexpected server response',
      );
    } catch (e) {
      debugPrint('BusinessCardScannerService error: $e');
      String errorMsg = e.toString();
      if (e is FunctionException) {
        final details = e.details;
        if (details is Map && details['error'] != null) {
          errorMsg = details['error'].toString();
        } else if (details is String) {
          try {
            final parsed = jsonDecode(details);
            if (parsed is Map && parsed['error'] != null) {
              errorMsg = parsed['error'].toString();
            } else {
              errorMsg = details;
            }
          } catch (_) {
            errorMsg = details;
          }
        } else if (details != null) {
          errorMsg = details.toString();
        }
      }
      return BusinessCardScannerResult.failure(errorMsg);
    }
  }
}
