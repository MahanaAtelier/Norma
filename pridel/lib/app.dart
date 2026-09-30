import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'screens/home_shell.dart';
import 'screens/onboarding_screen.dart';
import 'theme/app_theme.dart';

class PridelApp extends StatefulWidget {
  const PridelApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<PridelApp> createState() => _PridelAppState();
}

class _PridelAppState extends State<PridelApp> {
  bool? ready;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await widget.controller.database.getOnboardingComplete();
    if (mounted) setState(() => ready = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PRÍDEL',
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      home: ready == null
          ? const Scaffold(body: Center(child: CircularProgressIndicator()))
          : ready == false
              ? OnboardingScreen(
                  controller: widget.controller,
                  onDone: () => setState(() => ready = true))
              : HomeShell(controller: widget.controller),
    );
  }
}
