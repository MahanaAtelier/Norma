import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/app_alert.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<String>? issues;
  List<Map<String, Object?>> logs = const [];
  StorageSummary? storage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      widget.controller.database.dataHealthIssues(),
      widget.controller.database.getErrorLog(),
      widget.controller.database.getStorageSummary(),
    ]);
    if (!mounted) return;
    setState(() {
      issues = values[0] as List<String>;
      logs = values[1] as List<Map<String, Object?>>;
      storage = values[2] as StorageSummary;
    });
  }

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> _copyReport() async {
    final report = StringBuffer()
      ..writeln('PRÍDEL Flutter beta 0.5')
      ..writeln('DB: ${_size(storage?.databaseBytes ?? 0)}')
      ..writeln('Recepty: ${storage?.recipeCount ?? 0}')
      ..writeln('Zásoby: ${storage?.pantryCount ?? 0}')
      ..writeln('História: ${storage?.historyCount ?? 0}')
      ..writeln(
          'Kontrola: ${(issues?.isEmpty ?? false) ? 'OK' : issues?.join(' | ')}')
      ..writeln('Posledné chyby:');
    for (final log in logs.take(5)) {
      report.writeln('${log['created_at']}: ${log['message']}');
    }
    await Clipboard.setData(ClipboardData(text: report.toString()));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnostika je skopírovaná.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Diagnostika'), actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ]),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
                child: ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title:
                        Text('Databáza ${_size(storage?.databaseBytes ?? 0)}'),
                    subtitle: Text(
                        '${storage?.recipeCount ?? 0} receptov · ${storage?.pantryCount ?? 0} zásob · ${storage?.historyCount ?? 0} hotových jedál'))),
            const SizedBox(height: 10),
            Card(
                child: ListTile(
                    leading: Icon((issues?.isEmpty ?? false)
                        ? Icons.verified_outlined
                        : Icons.warning_amber_outlined),
                    title: Text(issues == null
                        ? 'Kontrolujem dáta…'
                        : issues!.isEmpty
                            ? 'Interná kontrola je v poriadku'
                            : 'Kontrola našla upozornenia'),
                    subtitle: issues?.isNotEmpty == true
                        ? Text(issues!.join('\n'))
                        : null)),
            const SizedBox(height: 20),
            Text('Posledné technické chyby',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (logs.isEmpty) const Text('Žiadna uložená chyba.'),
            ...logs.take(10).map((log) => Card(
                child: ListTile(
                    title: Text(log['message'].toString(),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(log['created_at'].toString())))),
            const SizedBox(height: 14),
            FilledButton.icon(
                onPressed: _copyReport,
                icon: const Icon(Icons.copy),
                label: const Text('Skopírovať diagnostiku pre podporu')),
            TextButton(
                onPressed: () async {
                  await widget.controller.database.clearErrorLog();
                  await _load();
                },
                child: const Text('Vymazať technický log')),
          ],
        ),
      );
}
