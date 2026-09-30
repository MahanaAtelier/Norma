import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  final importController = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    importController.dispose();
    super.dispose();
  }

  Future<String> _backupJson() => widget.controller.database.exportBackupJson();

  Future<void> _saveBackupFile() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await _backupJson();
      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final uri = await FilePicker.saveFile(
        dialogTitle: 'Uložiť zálohu PRÍDEL',
        fileName: 'PRIDEL-zaloha-$stamp.json',
        bytes: utf8.encode(data),
        mimeType: 'application/json',
      );
      if (!mounted || uri == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Záloha bola uložená mimo aplikácie.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Uloženie zálohy zlyhalo: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _copyBackup() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final data = await _backupJson();
      await Clipboard.setData(ClipboardData(text: data));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Záloha je skopírovaná do schránky.')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pickBackupFile() async {
    if (busy) return;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Vybrať zálohu PRÍDEL',
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      importController.text = utf8.decode(bytes);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Načítanie súboru zlyhalo: $e')));
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) importController.text = data!.text!;
  }

  Future<void> _restore() async {
    if (importController.text.trim().isEmpty || busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Obnoviť zálohu?'),
        content: const Text(
            'Aktuálne lokálne údaje sa nahradia obsahom zálohy. Vstavané recepty zostanú zachované.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušiť')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Obnoviť')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await widget.controller.database
          .importBackupJson(importController.text.trim());
      widget.controller.dataChanged();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Záloha bola obnovená.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Obnova zlyhala: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Záloha a obnova')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Card(
              child: ListTile(
                leading: Icon(Icons.shield_outlined),
                title: Text('Záloha obsahuje tvoje lokálne dáta'),
                subtitle: Text(
                    'Domácnosť, zásoby, jedálniček, históriu, zvyšky, vlastné recepty, ceny a nastavenia.'),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : _saveBackupFile,
                icon: const Icon(Icons.save_alt_outlined),
                label: const Text('Uložiť zálohu do súboru'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _copyBackup,
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Skopírovať zálohu do schránky'),
              ),
            ),
            const SizedBox(height: 28),
            Text('Obnova', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Vyber súbor zálohy PRÍDEL alebo vlož text zálohy. Pred obnovou sa kontroluje typ a verzia zálohy.'),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _pickBackupFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Vybrať súbor zálohy'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: importController,
              minLines: 5,
              maxLines: 10,
              decoration:
                  const InputDecoration(hintText: '{ "app": "PRIDEL", ... }'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: _paste,
                        icon: const Icon(Icons.content_paste),
                        label: const Text('Vložiť zo schránky'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton(
                        onPressed: busy ? null : _restore,
                        child: const Text('Obnoviť'))),
              ],
            ),
          ],
        ),
      );
}
