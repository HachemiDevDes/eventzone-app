import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  final String label;
  final bool isLive;

  const StatusPill({
    super.key,
    required this.label,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLive 
            ? const Color(0xFF059669) // Solid emerald green (rich and bright)
            : const Color(0xFF1E293B), // Solid slate grey (dark and clean)
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isLive ? const Color(0xFF34D399) : Colors.white54, // Bright borders
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white, // Pure white text for maximum readability
              fontSize: 12,
              fontWeight: FontWeight.bold, // Bold text for extra emphasis
              letterSpacing: 0.5,
            ),
          ),
          if (isLive) ...[
            const SizedBox(width: 4),
            const Text(
              "✓",
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ]
        ],
      ),
    );
  }
}
