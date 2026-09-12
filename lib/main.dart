import 'package:flutter/material.dart';

import 'data/map_repository.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MapXApp());
}

class MapXApp extends StatelessWidget {
  const MapXApp({super.key, this.repository});

  final MapRepository? repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: HomeScreen(repository: repository),
    );
  }
}
