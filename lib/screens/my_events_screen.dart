import 'package:flutter/material.dart';
import '../theme/eventzone_theme.dart';
import '../widgets/event_card.dart';
import '../models/event_model.dart';

import 'event_details_screen.dart';

class MyEventsScreen extends StatelessWidget {
  final List<EventModel> registeredEvents;
  final Function(EventModel) onAccessEvent;

  const MyEventsScreen({
    super.key, 
    required this.registeredEvents,
    required this.onAccessEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EventzoneTheme.buildPlayfulBackground(
        child: SafeArea(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "MANAGEMENT",
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: EventzoneTheme.primaryAction,
                              letterSpacing: 2,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "My Events",
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              fontSize: 32,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              if (registeredEvents.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_busy, size: 64, color: Colors.white10),
                        const SizedBox(height: 16),
                        Text("No registrations yet", style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white38)),
                        TextButton(
                          onPressed: () {},
                          child: const Text("Browse Events", style: TextStyle(color: EventzoneTheme.primaryAction)),
                        )
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final event = registeredEvents[index];
                        return EventCard(
                          title: event.title,
                          date: event.date,
                          location: event.location,
                          category: event.category,
                          imageUrl: event.imageUrl,
                          isJoined: true,
                          onRegister: () => onAccessEvent(event),
                          onViewDetails: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EventDetailsScreen(
                                  event: event,
                                  onRegister: () {},
                                  onAccess: () => onAccessEvent(event),
                                ),
                              ),
                            );
                          },
                        );
                      },
                      childCount: registeredEvents.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
