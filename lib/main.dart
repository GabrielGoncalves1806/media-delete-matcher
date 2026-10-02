import 'package:flutter/material.dart';

import 'media/decision_store.dart';
import 'media/media_library.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = DecisionStore();
  await store.load();
  runApp(MediaSwipeApp(library: MediaLibrary(), store: store));
}

class MediaSwipeApp extends StatelessWidget {
  const MediaSwipeApp({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'media_swipe',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(library: library, store: store),
    );
  }
}
