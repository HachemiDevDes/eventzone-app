import 'package:flutter/material.dart';

/// Top-level GlobalKey for the root navigator, enabling navigation and dialogs
/// from anywhere in the app, including background services and realtime callbacks.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
