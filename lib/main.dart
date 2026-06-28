import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/eventzone_theme.dart';
import 'screens/discovery_screen.dart';
import 'screens/event_dashboard.dart';
import 'screens/networking_screen.dart';
import 'screens/map_screen.dart';
import 'screens/my_events_screen.dart';
import 'screens/my_network_screen.dart';
import 'screens/event_partners_screen.dart';
import 'screens/event_sessions_screen.dart';
import 'screens/event_speakers_screen.dart';
import 'models/event_model.dart';
import 'widgets/qr_action_sheet.dart';

import 'services/supabase_service.dart';

import 'screens/edit_profile_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
  await Supabase.initialize(
    url: 'https://awkreadldqmidcrrqukm.supabase.co',
    publishableKey: 'sb_publishable_MluMrwkWs5-YedITa6ggNw_imK2nv8z',
  );

  runApp(const EventzoneApp());
}

class EventzoneApp extends StatelessWidget {
  const EventzoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eventzone Attendee',
      debugShowCheckedModeBanner: false,
      theme: EventzoneTheme.darkTheme,
      home: const MainNavigationHolder(),
    );
  }
}

enum AppViewMode { global, event }

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _globalIndex = 0;
  int _eventIndex = 0;
  AppViewMode _currentMode = AppViewMode.global;
  EventModel? _activeEvent;
  final List<EventModel> _registeredEvents = [];
  List<EventModel> _allEvents = [];
  bool _isLoading = true;
  final _supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final events = await _supabaseService.fetchEvents();
    setState(() {
      _allEvents = events;
      _isLoading = false;
    });
  }

  void _onRegisterEvent(EventModel event) {
    if (event.isJoined) {
      _onAccessEvent(event);
      return;
    }
    setState(() {
      event.isJoined = true;
      if (!_registeredEvents.contains(event)) {
        _registeredEvents.add(event);
      }
      _globalIndex = 1;
    });
    
    // In a real app, we'd call _supabaseService.registerForEvent here
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Registered for ${event.title}!"),
        backgroundColor: EventzoneTheme.accentSuccess,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onAccessEvent(EventModel event) {
    setState(() {
      _activeEvent = event;
      _currentMode = AppViewMode.event;
      _eventIndex = 0;
    });
  }

  void _exitEvent() {
    setState(() {
      _currentMode = AppViewMode.global;
    });
  }

  void _navigateToEventIndex(int index) {
    setState(() {
      _eventIndex = index;
    });
  }

  void _showQRMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const QRActionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EventzoneTheme.backgroundStart,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _currentMode == AppViewMode.global 
          ? _buildGlobalView() 
          : _buildEventView(),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildGlobalView() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: EventzoneTheme.primaryAction));
    }

    switch (_globalIndex) {
      case 0: return DiscoveryScreen(
        onEventJoined: _onRegisterEvent,
        onAccessEvent: _onAccessEvent,
        events: _allEvents,
      );
      case 1: return MyEventsScreen(
        registeredEvents: _registeredEvents, 
        onAccessEvent: _onAccessEvent,
      );
      case 2: return const MyNetworkScreen();
      case 3: return const EditProfileScreen();
      default: return DiscoveryScreen(
        onEventJoined: _onRegisterEvent,
        onAccessEvent: _onAccessEvent,
        events: _allEvents,
      );
    }
  }

  Widget _buildEventView() {
    if (_activeEvent == null) return const SizedBox.shrink();
    
    final isAtDashboard = _eventIndex == 0;
    
    return Stack(
      children: [
        _buildEventScreen(),
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          child: GestureDetector(
            onTap: isAtDashboard 
                ? _exitEvent 
                : () {
                    setState(() {
                      _eventIndex = 0;
                    });
                  },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.arrowLeft, color: Colors.white, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    isAtDashboard ? "EXIT EVENT" : "BACK", 
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEventScreen() {
    switch (_eventIndex) {
      case 0: return EventDashboard(event: _activeEvent!, onNavigate: _navigateToEventIndex);
      case 1: return const EventSessionsScreen();
      case 2: return const NetworkingScreen();
      case 3: return const MapScreen();
      case 4: return const EventSpeakersScreen();
      case 5: return const EventPartnersScreen(type: "Exhibitors");
      case 6: return const EventPartnersScreen(type: "Sponsors");
      default: return EventDashboard(event: _activeEvent!, onNavigate: _navigateToEventIndex);
    }
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        color: EventzoneTheme.backgroundEnd,
        border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
      ),
      child: BottomAppBar(
        color: Colors.transparent,
        elevation: 0,
        height: 70, // Fixed height to avoid overflow
        padding: EdgeInsets.zero,
        notchMargin: 10,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _currentMode == AppViewMode.global 
            ? [
                _buildNavItem(LucideIcons.compass, "Eventzone", 0, true),
                _buildNavItem(LucideIcons.calendar, "My Events", 1, true),
                _buildBarScanButton(),
                _buildNavItem(LucideIcons.users, "Contacts", 2, true),
                _buildNavItem(LucideIcons.user, "Profile", 3, true),
              ]
            : [
                _buildNavItem(LucideIcons.layoutDashboard, "Hub", 0, false),
                _buildNavItem(LucideIcons.calendarCheck, "Schedule", 1, false),
                _buildBarScanButton(),
                _buildNavItem(LucideIcons.users, "Attendees", 2, false),
                _buildNavItem(LucideIcons.map, "Map", 3, false),
              ],
        ),
      ),
    );
  }

  Widget _buildBarScanButton() {
    return Transform.translate(
      offset: const Offset(0, -8),
      child: GestureDetector(
        onTap: _showQRMenu,
        child: Container(
          width: 52,
          height: 52,
          decoration: const BoxDecoration(
            color: EventzoneTheme.primaryAction,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(LucideIcons.scan, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index, bool isGlobal) {
    final bool isSelected = (isGlobal ? _globalIndex : _eventIndex) == index;
    return InkWell(
      onTap: () {
        setState(() {
          if (isGlobal) {
            _globalIndex = index;
          } else {
            _eventIndex = index;
          }
        });
      },
      child: SizedBox(
        width: 60,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? EventzoneTheme.primaryAction : Colors.white38,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? EventzoneTheme.primaryAction : Colors.white38,
                fontSize: 9,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
