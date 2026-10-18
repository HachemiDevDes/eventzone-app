import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class StatusPill extends StatelessWidget {
  final String label;
  final bool isLive;
  final Color? customColor;
  final Color? customBorderColor;

  const StatusPill({
    super.key,
    required this.label,
    this.isLive = false,
    this.customColor,
    this.customBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: customColor ??
            (isLive 
                ? const Color(0xFFE11D48) // Red color for live
                : const Color(0xFF1E293B)), // Solid slate grey
        borderRadius: BorderRadius.circular(20),
        border: customBorderColor != null
            ? Border.all(color: customBorderColor!, width: 1.5)
            : (isLive
                ? null
                : Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.0,
                  )),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive)
            Container(
              width: 6,
              height: 6,
              margin: EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ).animate(onPlay: (controller) => controller.repeat(reverse: true))
             .fade(begin: 0.3, end: 1.0, duration: 800.ms),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    if (isLive) {
      return pill.animate(onPlay: (controller) => controller.repeat(reverse: true))
                 .scaleXY(end: 1.03, duration: 1200.ms, curve: Curves.easeInOut);
    }

    return pill;
  }
}
