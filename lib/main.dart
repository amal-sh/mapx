import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MapXApp());
}

class MapXApp extends StatelessWidget {
  const MapXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const HomeScreen(),
    );
  }
}
