import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/status_pill.dart';

class EventSessionsScreen extends StatelessWidget {
  const EventSessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "SCHEDULE",
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: EventzoneTheme.primaryAction,
                            letterSpacing: 2,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Sessions & Agenda",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            fontSize: 28,
                          ),
                    ),
                  ],
                ),
              ),
              // Day Selector
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  children: [
                    _buildDayChip("Day 1", isSelected: true),
                    _buildDayChip("Day 2"),
                    _buildDayChip("Day 3"),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    final times = ["09:00 AM", "10:30 AM", "12:00 PM", "01:30 PM", "03:00 PM", "04:30 PM"];
                    final titles = [
                      "Opening Keynote",
                      "Future of AI & Robotics",
                      "Networking Lunch",
                      "Cloud Infrastructure 2.0",
                      "Cybersecurity Deep Dive",
                      "Closing Remarks"
                    ];
                    final isLive = index == 1;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GlassContainer(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              children: [
                                Text(
                                  times[index],
                                  style: TextStyle(
                                    color: isLive ? EventzoneTheme.primaryAction : Colors.white38,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                if (isLive) ...[
                                  const SizedBox(height: 8),
                                  const StatusPill(label: "LIVE", isLive: true),
                                ]
                              ],
                            ),
                            const SizedBox(width: 20),
                            Container(width: 1, height: 60, color: Colors.white10),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    titles[index],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(LucideIcons.mapPin, size: 12, color: Colors.white38),
                                      const SizedBox(width: 4),
                                      Text(
                                        index % 2 == 0 ? "Main Hall" : "Room 402",
                                        style: const TextStyle(fontSize: 12, color: Colors.white38),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        radius: 10,
                                        backgroundImage: NetworkImage("https://i.pravatar.cc/150?u=a"),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        "Sarah Chen +2",
                                        style: TextStyle(fontSize: 11, color: Colors.white70),
                                      ),
                                      const Spacer(),
                                      const Icon(LucideIcons.plusCircle, size: 18, color: EventzoneTheme.primaryAction),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDayChip(String label, {bool isSelected = false}) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: isSelected ? EventzoneTheme.primaryAction : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: isSelected ? Colors.transparent : Colors.white10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white60,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
