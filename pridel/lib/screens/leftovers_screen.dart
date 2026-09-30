import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/leftover.dart';
import '../utils/date_utils.dart';

class LeftoversScreen extends StatefulWidget {
  const LeftoversScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<LeftoversScreen> createState() => _LeftoversScreenState();
}

class _LeftoversScreenState extends State<LeftoversScreen> {
  List<Leftover> items = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final value =
        await widget.controller.database.getLeftovers(status: 'available');
    if (!mounted) return;
    setState(() {
      items = value;
      loading = false;
    });
  }

  Future<void> _discard(Leftover item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vyhodiť zvyšok?'),
        content:
            Text('„${item.recipeName}“ sa už nebude ponúkať do jedálnička.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušiť')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vyhodiť')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.database.discardLeftover(item.id);
      widget.controller.dataChanged({AppArea.leftovers});
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Zvyšok bol odstránený.'),
          action: SnackBarAction(
              label: 'Vrátiť',
              onPressed: () async {
                await widget.controller.database.restoreLeftover(item.id);
                widget.controller.dataChanged({AppArea.leftovers});
                await _reload();
              }),
        ));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _consume(Leftover item) async {
    try {
      await widget.controller.database.consumeLeftoverOutsidePlan(item.id);
      widget.controller.dataChanged({AppArea.leftovers});
      await _reload();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zvyšky jedál')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                          'Momentálne nemáš evidovaný žiadny použiteľný zvyšok.')))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final days = item.useBy == null
                        ? null
                        : PridelDates.daysBetween(DateTime.now(), item.useBy!);
                    final urgent = days != null && days <= 1;
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        leading: CircleAvatar(
                            child: Icon(urgent
                                ? Icons.schedule_outlined
                                : Icons.takeout_dining)),
                        title: Text(item.recipeName),
                        subtitle: Text([
                          '${item.portions.toStringAsFixed(item.portions % 1 == 0 ? 0 : 1)} porcie',
                          if (item.useBy != null)
                            'spotrebovať do ${PridelDates.compactDay(item.useBy!)}',
                        ].join(' · ')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'eat') _consume(item);
                            if (value == 'discard') _discard(item);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'eat',
                                child: Text('Zjedené mimo plánu')),
                            PopupMenuItem(
                                value: 'discard', child: Text('Vyhodiť')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
