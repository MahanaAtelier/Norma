import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/household_member.dart';

class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  List<HouseholdMember> members = const [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final value = await widget.controller.database.getHousehold();
    if (!mounted) return;
    setState(() {
      members = value;
      loading = false;
    });
  }

  Future<void> _edit([HouseholdMember? existing]) async {
    final name = TextEditingController(text: existing?.name ?? '');
    String role = existing?.role ?? 'adult';
    double portion = existing?.portion ?? 1;
    bool active = existing?.active ?? true;
    final allergens = TextEditingController(text: existing?.allergens ?? '');
    final dislikes = TextEditingController(text: existing?.dislikes ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    existing == null
                        ? 'Pridať člena domácnosti'
                        : 'Upraviť člena',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Meno')),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'adult',
                        label: Text('Dospelý'),
                        icon: Icon(Icons.person_outline)),
                    ButtonSegment(
                        value: 'child',
                        label: Text('Dieťa'),
                        icon: Icon(Icons.child_care)),
                  ],
                  selected: {role},
                  onSelectionChanged: (value) =>
                      setSheetState(() => role = value.first),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<double>(
                  initialValue: portion,
                  decoration: const InputDecoration(labelText: 'Bežná porcia'),
                  items: const [
                    DropdownMenuItem(
                        value: 0.5, child: Text('Polovičná porcia')),
                    DropdownMenuItem(value: 1.0, child: Text('Celá porcia')),
                    DropdownMenuItem(value: 1.5, child: Text('1,5 porcie')),
                    DropdownMenuItem(value: 2.0, child: Text('2 porcie')),
                  ],
                  onChanged: (value) =>
                      setSheetState(() => portion = value ?? 1),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: allergens,
                  decoration: const InputDecoration(
                      labelText: 'Alergény', hintText: 'napr. mlieko, orechy'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dislikes,
                  decoration: const InputDecoration(
                      labelText: 'Neobľúbené suroviny',
                      hintText: 'napr. huby, brokolica'),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  onChanged: (value) => setSheetState(() => active = value),
                  title: const Text('Zahrnúť do plánovania'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Uložiť'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved == true) {
      try {
        await widget.controller.database.saveHouseholdMember(
          id: existing?.id,
          name: name.text,
          role: role,
          portion: portion,
          active: active,
          allergens: allergens.text,
          dislikes: dislikes.text,
        );
        widget.controller.dataChanged({AppArea.settings, AppArea.plan});
        await _reload();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    name.dispose();
    allergens.dispose();
    dislikes.dispose();
  }

  Future<void> _delete(HouseholdMember member) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odstrániť člena?'),
        content: Text(
            'Člen „${member.name}“ sa odstráni z budúcich plánov. Staré plány zostanú zachované.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušiť')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Odstrániť')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.database.deleteHouseholdMember(member.id);
      widget.controller.dataChanged({AppArea.settings, AppArea.plan});
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
      appBar: AppBar(title: const Text('Domácnosť')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Pridať'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
              itemCount: members.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final member = members[index];
                return Card(
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                        child: Icon(member.isChild
                            ? Icons.child_care
                            : Icons.person_outline)),
                    title: Text(member.name),
                    subtitle: Text([
                      member.isChild ? 'dieťa' : 'dospelý',
                      member.portion == 0.5
                          ? '½ porcie'
                          : '${member.portion.toStringAsFixed(member.portion % 1 == 0 ? 0 : 1)} porcie',
                      if (!member.active) 'mimo plánovania',
                    ].join(' · ')),
                    onTap: () => _edit(member),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') _edit(member);
                        if (value == 'delete') _delete(member);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Upraviť')),
                        PopupMenuItem(
                            value: 'delete', child: Text('Odstrániť')),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
