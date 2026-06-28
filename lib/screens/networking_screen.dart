import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';

class NetworkingScreen extends StatefulWidget {
  const NetworkingScreen({super.key});

  @override
  State<NetworkingScreen> createState() => _NetworkingScreenState();
}

class _NetworkingScreenState extends State<NetworkingScreen> {
  final Set<int> _connectedIndices = {};

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
                    Text("COMMUNITY", style: Theme.of(context).textTheme.labelLarge?.copyWith(color: EventzoneTheme.primaryAction)),
                    const SizedBox(height: 8),
                    Text("Attendee Directory", style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 28, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 16),
                    GlassContainer(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      borderRadius: 30,
                      child: const TextField(
                        decoration: InputDecoration(
                          hintText: "Search by name or company...",
                          border: InputBorder.none,
                          icon: Icon(LucideIcons.search, color: Colors.white38, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                  itemCount: 20,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final names = ["Sarah Chen", "Marcus Wright", "Elena Rodriguez", "David Kim", "James Wilson"];
                    final titles = ["CTO @ TechFlow", "Product Lead @ Google", "Design Director", "Founder @ Stealth", "Architect"];
                    final name = names[index % names.length];
                    final title = titles[index % titles.length];
                    final isConnected = _connectedIndices.contains(index);
                    
                    return GlassContainer(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _buildAvatar(name, index),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(title, style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                          _buildConnectButton(index, isConnected),
                        ],
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

  Widget _buildAvatar(String name, int index) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            EventzoneTheme.primaryAction.withOpacity(0.5),
            EventzoneTheme.accentSuccess.withOpacity(0.3),
          ],
        ),
      ),
      child: Center(
        child: Text(
          name.split(' ').map((e) => e[0]).join(),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildConnectButton(int index, bool isConnected) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: isConnected
          ? const Icon(LucideIcons.checkCircle, color: EventzoneTheme.accentSuccess, key: ValueKey('check'))
          : TextButton(
              key: const ValueKey('btn'),
              onPressed: () => setState(() => _connectedIndices.add(index)),
              style: TextButton.styleFrom(
                backgroundColor: EventzoneTheme.primaryAction.withOpacity(0.1),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("Connect", style: TextStyle(color: EventzoneTheme.primaryAction, fontWeight: FontWeight.bold)),
            ),
    );
  }
}
