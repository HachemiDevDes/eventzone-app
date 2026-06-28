import 'dart:convert';
import 'dart:io';

void main() async {
  final url = Uri.parse('https://awkreadldqmidcrrqukm.supabase.co/rest/v1/events');
  final client = HttpClient();
  
  final dummyEvents = [
    {
      'id': 'e1a8ca9e-8b1b-4b14-8f7d-81534f378a51',
      'title': 'TechFlow Summit 2024',
      'event_date': 'Oct 12-14, 2024',
      'location': 'San Francisco, CA',
      'category': 'TECH',
      'image_url': 'https://images.unsplash.com/photo-1540575861501-7cf05a4b125a?w=800&q=80',
      'stats': '487 Registered • 12 Hubs',
      'description': 'Premium B2B networking event focused on industry-leading innovations and executive partnerships.',
    },
    {
      'id': '7b55f6e8-2321-4f38-bc0d-7b2a0c4f8d62',
      'title': 'Global AI Executive Forum',
      'event_date': 'Nov 05, 2024',
      'location': 'London, UK',
      'category': 'AI',
      'image_url': 'https://images.unsplash.com/photo-1485827404703-89b55fcc595e?w=800&q=80',
      'stats': '320 Registered • 5 Hubs',
      'description': 'Premium B2B networking event focused on industry-leading innovations and executive partnerships.',
    },
    {
      'id': 'cc283c74-2ff4-436f-870a-4bf3f295b9c0',
      'title': 'FinTech Revolution',
      'event_date': 'Dec 02, 2024',
      'location': 'New York, NY',
      'category': 'FINANCE',
      'image_url': 'https://images.unsplash.com/photo-1551836022-d5d88e9218df?w=800&q=80',
      'stats': '1.2k Registered • 20 Hubs',
      'description': 'Premium B2B networking event focused on industry-leading innovations and executive partnerships.',
    },
  ];

  try {
    print('Inserting/upserting events...');
    final request = await client.postUrl(url);
    request.headers.set('apikey', 'sb_publishable_MluMrwkWs5-YedITa6ggNw_imK2nv8z');
    request.headers.set('Authorization', 'Bearer sb_publishable_MluMrwkWs5-YedITa6ggNw_imK2nv8z');
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Prefer', 'resolution=merge-duplicates');
    
    request.add(utf8.encode(jsonEncode(dummyEvents)));
    final response = await request.close();
    
    final responseBody = await response.transform(utf8.decoder).join();
    print('Status code: ${response.statusCode}');
    print('Response: $responseBody');
  } catch (e) {
    print('Error: $e');
  } finally {
    client.close();
  }
}
