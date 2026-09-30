import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/recipe.dart';

class CookingModeScreen extends StatefulWidget {
  const CookingModeScreen({super.key, required this.recipe});
  final Recipe recipe;

  @override
  State<CookingModeScreen> createState() => _CookingModeScreenState();
}

class _CookingModeScreenState extends State<CookingModeScreen> {
  int index = 0;

  List<String> get steps {
    final raw = widget.recipe.step.trim();
    if (raw.isEmpty) return const ['Postup zatiaľ nie je doplnený.'];
    final normalized = raw.replaceAll(RegExp(r'\r\n?'), '\n');
    var pieces = normalized
        .split(RegExp(r'\n+|(?<=[.!?])\s+(?=[A-ZÁÄČĎÉÍĹĽŇÓÔŔŠŤÚÝŽ])'));
    pieces = pieces.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return pieces.isEmpty ? [raw] : pieces;
  }

  void _move(int delta) {
    final next = (index + delta).clamp(0, steps.length - 1).toInt();
    if (next != index) {
      HapticFeedback.selectionClick();
      setState(() => index = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = steps;
    return Scaffold(
      appBar: AppBar(title: const Text('Režim varenia')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.recipe.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (index + 1) / all.length),
              const SizedBox(height: 8),
              Text('Krok ${index + 1} z ${all.length}',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(all[index],
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(height: 1.35)),
              const Spacer(),
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: index == 0 ? null : () => _move(-1),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Späť'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: index == all.length - 1
                            ? () => Navigator.pop(context)
                            : () => _move(1),
                        icon: Icon(index == all.length - 1
                            ? Icons.check
                            : Icons.arrow_forward),
                        label: Text(
                            index == all.length - 1 ? 'Hotovo' : 'Ďalej'))),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
