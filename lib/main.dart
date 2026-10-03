import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'media/decision_store.dart';
import 'media/json_file.dart';
import 'media/media_library.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Sempre em retrato (o manifest já trava; isso garante no Flutter também).
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final dataDir = (await getApplicationSupportDirectory()).path;
  final store = DecisionStore(JsonFile(File('$dataDir/decisions.json')));
  await store.load();

  // Garante que nenhum swipe se perde se o sistema matar o app no fundo.
  AppLifecycleListener(onHide: store.flush, onDetach: store.flush);

  runApp(MediaSwipeApp(library: MediaLibrary(dataDir: dataDir), store: store));
}

class MediaSwipeApp extends StatelessWidget {
  const MediaSwipeApp({super.key, required this.library, required this.store});

  final MediaLibrary library;
  final DecisionStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Media Swipe',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(library: library, store: store),
    );
  }
}
