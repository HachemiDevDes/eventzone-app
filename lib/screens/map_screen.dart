import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/glass_container.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  String _selectedBooth = "None";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 48),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "VENUE",
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: EventzoneTheme.primaryAction,
                                letterSpacing: 2,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Live Floor Plan",
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                fontSize: 28,
                              ),
                        ),
                      ],
                    ),
                    GlassContainer(
                      padding: const EdgeInsets.all(8),
                      borderRadius: 12,
                      child: const Icon(LucideIcons.locateFixed, color: EventzoneTheme.primaryAction, size: 20),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                  child: Stack(
                    children: [
                      GlassContainer(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: InteractiveViewer(
                            boundaryMargin: const EdgeInsets.all(200),
                            minScale: 0.1,
                            maxScale: 5.0,
                            child: Center(
                              child: _buildMapView(),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: _buildBoothInfo(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapView() {
    return Container(
      width: 800,
      height: 1000,
      color: Colors.white.withOpacity(0.01),
      child: Stack(
        children: [
          ...List.generate(20, (i) => Positioned(top: i * 50.0, left: 0, right: 0, child: Container(height: 1, color: Colors.white.withOpacity(0.03)))),
          ...List.generate(16, (i) => Positioned(left: i * 50.0, top: 0, bottom: 0, child: Container(width: 1, color: Colors.white.withOpacity(0.03)))),
          _buildBooth(200, 50, 400, 200, "MAIN STAGE", isAccent: true),
          _buildBooth(100, 350, 120, 100, "SAMSUNG - A1"),
          _buildBooth(300, 350, 120, 100, "GOOGLE - A2"),
          _buildBooth(500, 350, 120, 100, "APPLE - A3"),
          _buildBooth(100, 550, 120, 100, "META - B1"),
          _buildBooth(300, 550, 120, 100, "OPENAI - B2"),
          _buildBooth(500, 550, 120, 100, "ANTHROPIC - B3"),
          Positioned(
            left: 400,
            top: 750,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: EventzoneTheme.primaryAction,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: EventzoneTheme.primaryAction.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
              ),
              child: const Center(child: Icon(LucideIcons.navigation, size: 12, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBooth(double left, double top, double width, double height, String label, {bool isAccent = false}) {
    bool isSelected = _selectedBooth == label;
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: () => setState(() => _selectedBooth = label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: isSelected 
                ? EventzoneTheme.primaryAction.withOpacity(0.4) 
                : (isAccent ? EventzoneTheme.accentSuccess.withOpacity(0.1) : Colors.white.withOpacity(0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? EventzoneTheme.primaryAction : (isAccent ? EventzoneTheme.accentSuccess : Colors.white10),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoothInfo() {
    if (_selectedBooth == "None") return const SizedBox.shrink();
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: EventzoneTheme.primaryAction.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
            child: const Icon(LucideIcons.info, color: EventzoneTheme.primaryAction, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selectedBooth, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Text("Industry: Tech/Innovation", style: TextStyle(color: Colors.white38, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: EventzoneTheme.primaryAction, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            child: const Text("Details"),
          ),
        ],
      ),
    );
  }
}
