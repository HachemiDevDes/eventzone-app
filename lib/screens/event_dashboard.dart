import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';
import '../widgets/status_pill.dart';
import '../models/event_model.dart';

import 'edit_profile_screen.dart';

class EventDashboard extends StatelessWidget {
  final EventModel event;
  final Function(int) onNavigate;

  const EventDashboard({super.key, required this.event, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const StatusPill(label: "LIVE NOW", isLive: true),
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => EditProfileScreen()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: EventzoneTheme.accentSuccess, width: 2),
                        ),
                        child: const CircleAvatar(
                          radius: 18,
                          backgroundImage: NetworkImage("https://i.pravatar.cc/150?u=me"),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        fontSize: 32,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Event Pass: #EZ-9942",
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: EventzoneTheme.accentSuccess,
                        letterSpacing: 2,
                      ),
                ),
                const SizedBox(height: 32),

                // Core Hub Grid
                Text("EVENT HUB", style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  children: [
                    _buildHubItem(context, LucideIcons.calendar, "Agenda", 1),
                    _buildHubItem(context, LucideIcons.users, "Attendees", 2),
                    _buildHubItem(context, LucideIcons.map, "Floor Plan", 3),
                    _buildHubItem(context, LucideIcons.mic2, "Speakers", 4),
                    _buildHubItem(context, LucideIcons.store, "Exhibitors", 5),
                    _buildHubItem(context, LucideIcons.award, "Sponsors", 6),
                  ],
                ),

                const SizedBox(height: 32),
                
                _buildSectionHeader(context, "Real-time Stats"),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildMetricCard(context, "487", "Registered", LucideIcons.barChart3)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildMetricCard(context, "12", "Active Hubs", LucideIcons.smartphone)),
                  ],
                ),
                const SizedBox(height: 16),
                GlassContainer(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Main Hall Capacity", style: Theme.of(context).textTheme.titleLarge),
                          const Text("82%", style: TextStyle(color: EventzoneTheme.accentSuccess, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: const LinearProgressIndicator(
                          value: 0.82,
                          minHeight: 10,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(EventzoneTheme.accentSuccess),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHubItem(BuildContext context, IconData icon, String label, int targetIndex) {
    return GestureDetector(
      onTap: () => onNavigate(targetIndex),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: EventzoneTheme.primaryAction, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const Text("View All", style: TextStyle(color: EventzoneTheme.primaryAction, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMetricCard(BuildContext context, String value, String label, IconData icon) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: EventzoneTheme.primaryAction, size: 20),
          const SizedBox(height: 12),
          Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }
}
