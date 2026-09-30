import 'dart:ui';

import 'package:flutter/material.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'data/app_database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final database = AppDatabase();
  try {
    await database.initialize();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      database.logError(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      database.logError(error, stack);
      return true;
    };
    runApp(PridelApp(controller: AppController(database)));
  } catch (error, stack) {
    FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack));
    runApp(StartupFailureApp(message: error.toString()));
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 42),
                const SizedBox(height: 18),
                const Text('PRÍDEL sa nepodarilo bezpečne spustiť',
                    style:
                        TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                const Text(
                    'Dáta sme zámerne nemenili. Skús aplikáciu zavrieť a znovu otvoriť. Ak problém zostane, pošli túto hlášku.'),
                const SizedBox(height: 14),
                SelectableText(message, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
