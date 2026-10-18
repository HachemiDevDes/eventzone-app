import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/crm_api_service.dart';

enum CrmType { hubspot, salesforce, zoho, odoo }

extension CrmTypeExtension on CrmType {
  String get name {
    switch (this) {
      case CrmType.hubspot:
        return 'HubSpot';
      case CrmType.salesforce:
        return 'Salesforce';
      case CrmType.zoho:
        return 'Zoho CRM';
      case CrmType.odoo:
        return 'Odoo';
    }
  }

  String get id {
    switch (this) {
      case CrmType.hubspot:
        return 'hubspot';
      case CrmType.salesforce:
        return 'salesforce';
      case CrmType.zoho:
        return 'zoho';
      case CrmType.odoo:
        return 'odoo';
    }
  }
}

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
});

// A provider that keeps track of which CRMs are connected
final crmConnectionsProvider = StateNotifierProvider<CrmConnectionsNotifier, Map<CrmType, bool>>((ref) {
  return CrmConnectionsNotifier(ref.read(secureStorageProvider));
});

class CrmConnectionsNotifier extends StateNotifier<Map<CrmType, bool>> {
  final FlutterSecureStorage _storage;

  CrmConnectionsNotifier(this._storage) : super({}) {
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final Map<CrmType, bool> status = {};
    for (var type in CrmType.values) {
      final key = '${type.id}_connected';
      final value = await _storage.read(key: key);
      status[type] = value == 'true';
    }
    state = status;
  }

  Future<void> connect(CrmType type, Map<String, String> credentials) async {
    // Save credentials to secure storage
    for (var entry in credentials.entries) {
      await _storage.write(key: '${type.id}_${entry.key}', value: entry.value);
    }
    await _storage.write(key: '${type.id}_connected', value: 'true');
    await _loadConnections();
  }

  Future<void> disconnect(CrmType type) async {
    // Delete credentials from secure storage
    await _storage.delete(key: '${type.id}_connected');
    if (type == CrmType.hubspot) {
      await _storage.delete(key: '${type.id}_token');
    } else if (type == CrmType.salesforce) {
      await _storage.delete(key: '${type.id}_url');
      await _storage.delete(key: '${type.id}_token');
    } else if (type == CrmType.zoho) {
      await _storage.delete(key: '${type.id}_token');
      await _storage.delete(key: '${type.id}_dc');
    } else if (type == CrmType.odoo) {
      await _storage.delete(key: '${type.id}_url');
      await _storage.delete(key: '${type.id}_db');
      await _storage.delete(key: '${type.id}_api_key');
    }
    await _loadConnections();
  }
}

// Stores the selected format for export (XLSX, CSV, or a CrmType ID)
final exportFormatProvider = StateProvider<String?>((ref) => null);

// State for the CRM push export flow
enum CrmExportStatus { idle, pushing, success, error }

class CrmExportState {
  final CrmExportStatus status;
  final int successCount;
  final int skipCount;
  final int errorCount;
  final String? errorMessage;

  CrmExportState({
    this.status = CrmExportStatus.idle,
    this.successCount = 0,
    this.skipCount = 0,
    this.errorCount = 0,
    this.errorMessage,
  });

  CrmExportState copyWith({
    CrmExportStatus? status,
    int? successCount,
    int? skipCount,
    int? errorCount,
    String? errorMessage,
  }) {
    return CrmExportState(
      status: status ?? this.status,
      successCount: successCount ?? this.successCount,
      skipCount: skipCount ?? this.skipCount,
      errorCount: errorCount ?? this.errorCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

final crmExportProvider = StateNotifierProvider<CrmExportNotifier, CrmExportState>((ref) {
  return CrmExportNotifier(ref.read(secureStorageProvider));
});

class CrmExportNotifier extends StateNotifier<CrmExportState> {
  final FlutterSecureStorage _storage;

  CrmExportNotifier(this._storage) : super(CrmExportState());

  void reset() {
    state = CrmExportState();
  }

  Future<void> pushContacts(CrmType type, List<Map<String, dynamic>> contacts) async {
    if (contacts.isEmpty) return;
    
    state = state.copyWith(status: CrmExportStatus.pushing);
    
    try {
      CrmExportResult result;
      switch (type) {
        case CrmType.hubspot:
          final token = await _storage.read(key: '${type.id}_token');
          result = await CrmApiService.pushToHubSpot(contacts, token);
          break;
        case CrmType.salesforce:
          final url = await _storage.read(key: '${type.id}_url');
          final token = await _storage.read(key: '${type.id}_token');
          result = await CrmApiService.pushToSalesforce(contacts, url, token);
          break;
        case CrmType.zoho:
          final token = await _storage.read(key: '${type.id}_token');
          final dc = await _storage.read(key: '${type.id}_dc');
          result = await CrmApiService.pushToZoho(contacts, token, dc);
          break;
        case CrmType.odoo:
          final url = await _storage.read(key: '${type.id}_url');
          final db = await _storage.read(key: '${type.id}_db');
          final apiKey = await _storage.read(key: '${type.id}_api_key');
          result = await CrmApiService.pushToOdoo(contacts, url, db, apiKey);
          break;
      }
      
      state = state.copyWith(
        status: CrmExportStatus.success,
        successCount: result.successCount,
        skipCount: result.skipCount,
        errorCount: result.errorCount,
        errorMessage: result.errorMessage,
      );
    } catch (e) {
      state = state.copyWith(
        status: CrmExportStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}
