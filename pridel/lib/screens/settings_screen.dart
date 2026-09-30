import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/app_alert.dart';
import '../models/planning.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import 'backup_screen.dart';
import 'diagnostics_screen.dart';
import 'history_screen.dart';
import 'household_screen.dart';
import 'leftovers_screen.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? usePantry;
  bool? alerts;
  int horizon = 7;
  PlanningPreferences? preferences;
  List<String>? healthIssues;
  int householdCount = 0;
  StorageSummary? storage;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_externalChange);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    super.dispose();
  }

  void _externalChange() {
    if (widget.controller.affects(AppArea.settings)) _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final results = await Future.wait([
      widget.controller.database.getUsePantry(),
      widget.controller.database.getInAppAlertsEnabled(),
      widget.controller.database.getPlanHorizonDays(),
      widget.controller.database.getPlanningPreferences(),
      widget.controller.database.dataHealthIssues(),
      widget.controller.database.getHousehold(activeOnly: true),
      widget.controller.database.getStorageSummary(),
    ]);
    if (!mounted || token != _loadToken) return;
    setState(() {
      usePantry = results[0] as bool;
      alerts = results[1] as bool;
      horizon = results[2] as int;
      preferences = results[3] as PlanningPreferences;
      healthIssues = results[4] as List<String>;
      householdCount = (results[5] as List).length;
      storage = results[6] as StorageSummary;
    });
  }

  Future<void> _savePreferences(PlanningPreferences value) async {
    await widget.controller.database.setPlanningPreferences(value);
    setState(() => preferences = value);
    widget.controller
        .dataChanged({AppArea.settings, AppArea.shopping, AppArea.plan});
  }

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} kB'
      : '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final prefs = preferences;
    return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
      const PageHeader(
          title: 'Nastavenia',
          subtitle: 'Domácnosť, plánovanie, upozornenia, dáta a súkromie.'),
      _section(
          context,
          'Domácnosť',
          Card(
              child: ListTile(
                  leading:
                      const CircleAvatar(child: Icon(Icons.people_outline)),
                  title: const Text('Členovia domácnosti'),
                  subtitle: Text(
                      '$householdCount aktívnych · porcie, alergény a neobľúbené suroviny'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          HouseholdScreen(controller: widget.controller)))))),
      _section(
          context,
          'Zásoby a upozornenia',
          Column(children: [
            Card(
                child: SwitchListTile(
                    value: usePantry ?? true,
                    onChanged: usePantry == null
                        ? null
                        : (v) async {
                            await widget.controller.database.setUsePantry(v);
                            setState(() => usePantry = v);
                            widget.controller.dataChanged({
                              AppArea.settings,
                              AppArea.shopping,
                              AppArea.plan,
                              AppArea.pantry
                            });
                          },
                    title: const Text('Využívať zásoby'),
                    subtitle: const Text(
                        'Ak je vypnuté, plán ani nákup neodpočítavajú Chladničku, Špajzu ani Mrazničku.'))),
            const SizedBox(height: 10),
            Card(
                child: SwitchListTile(
                    value: alerts ?? true,
                    onChanged: alerts == null
                        ? null
                        : (v) async {
                            await widget.controller.database
                                .setInAppAlertsEnabled(v);
                            setState(() => alerts = v);
                            widget.controller
                                .dataChanged({AppArea.settings, AppArea.home});
                          },
                    title: const Text('Upozornenia v aplikácii'),
                    subtitle: const Text(
                        'Expirácia, zvyšky a chýbajúci plán. Po potvrdení zmiznú.'))),
            const SizedBox(height: 10),
            Card(
                child: ListTile(
                    leading: const Icon(Icons.takeout_dining),
                    title: const Text('Zvyšky jedál'),
                    subtitle: const Text(
                        'Dostupné, rezervované, zjedené alebo vyhodené.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            LeftoversScreen(controller: widget.controller))))),
          ])),
      _section(
          context,
          'Plánovanie',
          Column(children: [
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Bežný horizont plánu'),
                          const SizedBox(height: 10),
                          SegmentedButton<int>(
                              segments: const [
                                ButtonSegment(value: 7, label: Text('7 dní')),
                                ButtonSegment(value: 14, label: Text('14 dní')),
                                ButtonSegment(value: 28, label: Text('28 dní'))
                              ],
                              selected: {
                                horizon
                              },
                              onSelectionChanged: (v) async {
                                final value = v.first;
                                await widget.controller.database
                                    .setPlanHorizonDays(value);
                                setState(() => horizon = value);
                              }),
                          const SizedBox(height: 8),
                          Text(
                              'Kalendár nemá koniec. Toto len určuje, koľko dní dopredu chceš bežne pripravovať.',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]))),
            if (prefs != null) ...[
              const SizedBox(height: 10),
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        _numberSetting(context,
                            title: 'Ryba za týždeň',
                            value: prefs.fishPerWeek,
                            values: const [0, 1, 2, 3],
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(fishPerWeek: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Bezmäsité hlavné jedlá',
                            value: prefs.vegetarianMainsPerWeek,
                            values: const [0, 1, 2, 3, 4, 5],
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(vegetarianMainsPerWeek: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Strukovinové hlavné jedlá',
                            value: prefs.legumeMainsPerWeek,
                            values: const [0, 1, 2, 3, 4],
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(legumeMainsPerWeek: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Dni s ovocím',
                            value: prefs.minFruitDaysPerWeek,
                            values: const [0, 1, 2, 3, 4, 5, 6, 7],
                            suffix: ' dní',
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(minFruitDaysPerWeek: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Dni so zeleninou pri hlavnom jedle',
                            value: prefs.minVegetableMainDaysPerWeek,
                            values: const [0, 1, 2, 3, 4, 5, 6, 7],
                            suffix: ' dní',
                            onChanged: (v) => _savePreferences(prefs.copyWith(
                                minVegetableMainDaysPerWeek: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Maximum sladkých hlavných jedál',
                            value: prefs.maxSweetMainsPerWeek,
                            values: const [0, 1, 2, 3],
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(maxSweetMainsPerWeek: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Rovnaký zdroj bielkovín najviac po sebe',
                            value: prefs.maxSameProteinStreak,
                            values: const [1, 2, 3, 4],
                            suffix: ' dni',
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(maxSameProteinStreak: v))),
                        const Divider(),
                        _numberSetting(context,
                            title: 'Pauza pred zopakovaním receptu',
                            value: prefs.avoidRepeatDays,
                            values: const [7, 14, 21, 28, 35],
                            suffix: ' dní',
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(avoidRepeatDays: v))),
                        const Divider(),
                        SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: prefs.preferQuickWeekdays,
                            onChanged: (v) => _savePreferences(
                                prefs.copyWith(preferQuickWeekdays: v)),
                            title: const Text(
                                'Uprednostniť rýchle jedlá cez pracovné dni')),
                        Text(
                            'Pravidlá riadia pestrosť plánu, nie individuálnu zdravotnú diétu.',
                            style: Theme.of(context).textTheme.bodySmall),
                      ])))
            ],
          ])),
      _section(
          context,
          'História a dáta',
          Column(children: [
            Card(
                child: Column(children: [
              ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('História jedál'),
                  subtitle: Text(
                      '${storage?.historyCount ?? 0} hotových jedál uložených ako snapshot'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          HistoryScreen(controller: widget.controller)))),
              const Divider(indent: 56),
              ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Záloha a obnova'),
                  subtitle:
                      const Text('Kompletná lokálna záloha vlastných dát.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          BackupScreen(controller: widget.controller)))),
              const Divider(indent: 56),
              ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: Text(
                      'Úložisko ${storage == null ? '…' : _size(storage!.databaseBytes)}'),
                  subtitle: Text(
                      '${storage?.recipeCount ?? 0} receptov · ${storage?.pantryCount ?? 0} zásob'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          DiagnosticsScreen(controller: widget.controller)))),
            ])),
          ])),
      _section(
          context,
          'Podpora a kontrola',
          Card(
              child: Column(children: [
            ListTile(
                leading: CircleAvatar(
                    backgroundColor: (healthIssues?.isEmpty ?? false)
                        ? AppTheme.success.withValues(alpha: .10)
                        : AppTheme.warning.withValues(alpha: .10),
                    child: Icon((healthIssues?.isEmpty ?? false)
                        ? Icons.verified_outlined
                        : Icons.warning_amber_outlined)),
                title: Text(healthIssues == null
                    ? 'Kontrolujem…'
                    : healthIssues!.isEmpty
                        ? 'Databáza je konzistentná'
                        : 'Našli sa upozornenia'),
                subtitle: healthIssues?.isNotEmpty == true
                    ? Text(healthIssues!.join('\n'))
                    : const Text(
                        'Recepty, suroviny, jednotky a databázové väzby.'),
                trailing: IconButton(
                    onPressed: _load, icon: const Icon(Icons.refresh))),
            const Divider(indent: 56),
            ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Diagnostika a nahlásenie problému'),
                subtitle:
                    const Text('Skopíruje technické údaje bez osobných správ.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        DiagnosticsScreen(controller: widget.controller)))),
            const Divider(indent: 56),
            ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Spustiť úvodné nastavenie znova'),
                subtitle: const Text('Nezmaže recepty, históriu ani zásoby.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OnboardingScreen(
                        controller: widget.controller,
                        onDone: () => Navigator.of(context).pop())))),
          ]))),
      _section(
          context,
          'Súkromie a verzia',
          const Card(
              child: Column(children: [
            ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('Dáta zostávajú v zariadení'),
                subtitle: Text(
                    'Bez účtu, polohy, kontaktov a mikrofónu. Cloud nie je v tejto bete zapnutý.')),
            Divider(indent: 56),
            ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('PRÍDEL Flutter beta 0.6'),
                subtitle: Text(
                    'SQLite · svetlý režim · lokálne dáta · snapshoty histórie')),
          ]))),
    ]);
  }

  Widget _section(BuildContext context, String title, Widget child) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
        child
      ]));
  Widget _numberSetting(BuildContext context,
          {required String title,
          required int value,
          required List<int> values,
          String suffix = '',
          required ValueChanged<int> onChanged}) =>
      Row(children: [
        Expanded(child: Text(title)),
        DropdownButton<int>(
            value: value,
            items: [
              for (final item in values)
                DropdownMenuItem(value: item, child: Text('$item$suffix'))
            ],
            onChanged: (v) {
              if (v != null) onChanged(v);
            })
      ]);
}
