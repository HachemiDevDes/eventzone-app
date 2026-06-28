class EventModel {
  final String id;
  final String title;
  final String date;
  final String location;
  final String category;
  final String description;
  final String? stats;
  final String imageUrl;
  bool isJoined;

  EventModel({
    required this.id,
    required this.title,
    required this.date,
    required this.location,
    required this.category,
    required this.imageUrl,
    this.description = "Premium B2B networking event focused on industry-leading innovations and executive partnerships.",
    this.stats,
    this.isJoined = false,
  });
}

final List<EventModel> dummyEvents = [
  EventModel(
    id: "e1a8ca9e-8b1b-4b14-8f7d-81534f378a51",
    title: "TechFlow Summit 2024",
    date: "Oct 12-14, 2024",
    location: "San Francisco, CA",
    category: "TECH",
    imageUrl: "https://images.unsplash.com/photo-1540575861501-7cf05a4b125a?w=800&q=80",
    stats: "487 Registered • 12 Hubs",
  ),
  EventModel(
    id: "7b55f6e8-2321-4f38-bc0d-7b2a0c4f8d62",
    title: "Global AI Executive Forum",
    date: "Nov 05, 2024",
    location: "London, UK",
    category: "AI",
    imageUrl: "https://images.unsplash.com/photo-1485827404703-89b55fcc595e?w=800&q=80",
    stats: "320 Registered • 5 Hubs",
  ),
  EventModel(
    id: "cc283c74-2ff4-436f-870a-4bf3f295b9c0",
    title: "FinTech Revolution",
    date: "Dec 02, 2024",
    location: "New York, NY",
    category: "FINANCE",
    imageUrl: "https://images.unsplash.com/photo-1551836022-d5d88e9218df?w=800&q=80",
    stats: "1.2k Registered • 20 Hubs",
  ),
];
