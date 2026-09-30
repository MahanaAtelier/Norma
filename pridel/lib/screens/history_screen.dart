import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/meal_entry.dart';
import '../utils/date_utils.dart';
import '../utils/meal_types.dart';
import '../widgets/empty_state.dart';
import 'recipe_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<MealEntry> meals = const [];
  bool loading = true;
  int days = 90;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = DateTime.now();
    final value = await widget.controller.database
        .getMealEntries(now.subtract(Duration(days: days)), now);
    if (!mounted) return;
    setState(() {
      meals = value
          .where((e) => e.isDone)
          .toList(growable: false)
          .reversed
          .toList(growable: false);
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<MealEntry>>{};
    for (final meal in meals) {
      groups.putIfAbsent(PridelDates.iso(meal.date), () => []).add(meal);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('História')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 30, label: Text('30 dní')),
                      ButtonSegment(value: 90, label: Text('90 dní')),
                      ButtonSegment(value: 365, label: Text('Rok')),
                    ],
                    selected: {days},
                    onSelectionChanged: (v) {
                      setState(() {
                        days = v.first;
                        loading = true;
                      });
                      _load();
                    },
                  ),
                ),
                Expanded(
                  child: groups.isEmpty
                      ? const EmptyState(
                          icon: Icons.history,
                          title: 'História je zatiaľ prázdna',
                          message:
                              'Jedlá označené ako Hotovo sa zobrazia tu. Staré recepty zostávajú uložené ako snapshot.')
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          children: [
                            for (final entry in groups.entries) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                                child: Text(
                                    PridelDates.dayLabel(
                                        DateTime.parse(entry.key)),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                              ),
                              Card(
                                child: Column(
                                  children: [
                                    for (int i = 0;
                                        i < entry.value.length;
                                        i++) ...[
                                      ListTile(
                                        leading: const Icon(
                                            Icons.check_circle_outline),
                                        title: Text(
                                            entry.value[i].snapshot?.name ??
                                                'Jedlo'),
                                        subtitle: Text(MealTypes.label(
                                            entry.value[i].mealType)),
                                        trailing: entry.value[i].snapshot ==
                                                null
                                            ? null
                                            : const Icon(Icons.chevron_right),
                                        onTap: entry.value[i].snapshot == null
                                            ? null
                                            : () => Navigator.of(context).push(
                                                MaterialPageRoute(
                                                    builder: (_) =>
                                                        RecipeDetailScreen(
                                                            controller: widget
                                                                .controller,
                                                            recipe: entry
                                                                .value[i]
                                                                .snapshot!,
                                                            snapshotOnly:
                                                                true))),
                                      ),
                                      if (i < entry.value.length - 1)
                                        const Divider(indent: 56),
                                    ]
                                  ],
                                ),
                              ),
                            ]
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
