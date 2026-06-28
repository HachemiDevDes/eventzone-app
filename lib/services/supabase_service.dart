import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/event_model.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  // 📅 Fetch all events from the 'events' table
  Future<List<EventModel>> fetchEvents() async {
    try {
      final response = await _supabase
          .from('events')
          .select()
          .order('created_at', ascending: false);
      
      return (response as List).map((data) => EventModel(
        id: data['id'],
        title: data['name'] ?? 'Untitled Event',
        date: data['start_date'] ?? data['date'] ?? 'TBA',
        location: data['location'] ?? 'Online',
        category: data['type'] ?? 'EVENT',
        imageUrl: data['banner'] ?? data['cover_url'] ?? 'https://images.unsplash.com/photo-1540575861501-7cf05a4b125a?w=800&q=80',
        description: data['description'] ?? '',
        stats: data['capacity'] != null ? '${data['capacity']} Capacity' : null,
        isJoined: false, // Will be updated by registration check
      )).toList();
    } catch (e) {
      print('Error fetching events: $e');
      return [];
    }
  }

  // 📝 Register for an event
  Future<bool> registerForEvent(String eventId, String profileId) async {
    try {
      await _supabase.from('event_registrations').insert({
        'event_id': eventId,
        'profile_id': profileId,
      });
      return true;
    } catch (e) {
      print('Error registering: $e');
      return false;
    }
  }

  // 🤝 Connect with another attendee via QR
  Future<void> connectWithUser(String currentUserId, String targetUserId) async {
    try {
      await _supabase.from('connections').upsert({
        'user_id': currentUserId,
        'connected_user_id': targetUserId,
        'status': 'connected',
      });
    } catch (e) {
      print('Error connecting: $e');
    }
  }

  // 👤 Fetch a user profile
  Future<Map<String, dynamic>?> fetchProfile(String profileId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', profileId)
          .maybeSingle();
      return response;
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  // 👤 Update a user profile
  Future<bool> updateProfile(String profileId, {
    required String fullName,
    required String jobTitle,
    required String companyName,
    String? avatarUrl,
    String? address,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _supabase.from('profiles').update({
        'full_name': fullName,
        'job_title': jobTitle,
        'company_name': companyName,
        'avatar_url': avatarUrl,
        'address': address,
        'metadata': metadata,
      }).eq('id', profileId);
      return true;
    } catch (e) {
      print('Error updating profile: $e');
      return false;
    }
  }

  // 🤝 Fetch connections/leads
  Future<List<Map<String, dynamic>>> fetchConnections(String userId) async {
    try {
      final response = await _supabase
          .from('connections')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching connections: $e');
      return [];
    }
  }

  // 💾 Save connection/lead
  Future<bool> saveConnection(Map<String, dynamic> connectionData) async {
    try {
      await _supabase.from('connections').insert(connectionData);
      return true;
    } catch (e) {
      print('Error saving connection: $e');
      return false;
    }
  }

  // ❌ Delete connection/lead
  Future<bool> deleteConnection(String connectionId) async {
    try {
      await _supabase.from('connections').delete().eq('id', connectionId);
      return true;
    } catch (e) {
      print('Error deleting connection: $e');
      return false;
    }
  }
}
