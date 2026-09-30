import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen(
      {super.key, required this.controller, required this.onDone});
  final AppController controller;
  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final adultName = TextEditingController(text: 'Ja');
  final childName = TextEditingController();
  int step = 0;
  bool hasChild = false;
  bool usePantry = true;
  bool alerts = true;
  int horizon = 7;
  bool saving = false;

  @override
  void dispose() {
    adultName.dispose();
    childName.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final members = await widget.controller.database.getHousehold();
      final adults = members.where((m) => !m.isChild).toList();
      final children = members.where((m) => m.isChild).toList();
      final name = adultName.text.trim().isEmpty ? 'Ja' : adultName.text.trim();
      await widget.controller.database.saveHouseholdMember(
        id: adults.isEmpty ? null : adults.first.id,
        name: name,
        role: 'adult',
        portion: adults.isEmpty ? 1 : adults.first.portion,
        active: true,
        allergens: adults.isEmpty ? '' : adults.first.allergens,
        dislikes: adults.isEmpty ? '' : adults.first.dislikes,
      );
      if (hasChild && childName.text.trim().isNotEmpty) {
        await widget.controller.database.saveHouseholdMember(
          id: children.isEmpty ? null : children.first.id,
          name: childName.text.trim(),
          role: 'child',
          portion: children.isEmpty ? 1 : children.first.portion,
          active: true,
          allergens: children.isEmpty ? '' : children.first.allergens,
          dislikes: children.isEmpty ? '' : children.first.dislikes,
        );
      }
      await widget.controller.database.setUsePantry(usePantry);
      await widget.controller.database.setInAppAlertsEnabled(alerts);
      await widget.controller.database.setPlanHorizonDays(horizon);
      await widget.controller.database.setOnboardingComplete(true);
      HapticFeedback.mediumImpact();
      widget.controller.dataChanged();
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [_welcome(), _household(), _pantry(), _plan(), _alerts()];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Row(
                children: [
                  const Text('PRÍDEL',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  const Spacer(),
                  Text('${step + 1}/${pages.length}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Expanded(
                child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child:
                        KeyedSubtree(key: ValueKey(step), child: pages[step]))),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (step > 0)
                    OutlinedButton(
                        onPressed: () => setState(() => step--),
                        child: const Text('Späť')),
                  const Spacer(),
                  FilledButton(
                    onPressed: saving
                        ? null
                        : step == pages.length - 1
                            ? _finish
                            : () => setState(() => step++),
                    child: Text(step == pages.length - 1
                        ? (saving ? 'Ukladám…' : 'Začať používať')
                        : 'Pokračovať'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame(
          {required IconData icon,
          required String title,
          required String text,
          required Widget child}) =>
      ListView(
        padding: const EdgeInsets.fromLTRB(24, 54, 24, 24),
        children: [
          CircleAvatar(radius: 31, child: Icon(icon, size: 30)),
          const SizedBox(height: 24),
          Text(title,
              style: Theme.of(context).textTheme.headlineLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(text,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center),
          const SizedBox(height: 30),
          child,
        ],
      );

  Widget _welcome() => _frame(
        icon: Icons.restaurant_menu,
        title: 'Menej rozmýšľania, čo variť',
        text:
            'PRÍDEL spojí rodinný jedálniček, recepty, zásoby, zvyšky a nákup. Najprv nastavíme pár vecí pre vašu domácnosť.',
        child: const Card(
            child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                    'Účet nepotrebuješ. Základné dáta zostávajú lokálne v zariadení.'))),
      );

  Widget _household() => _frame(
        icon: Icons.people_outline,
        title: 'Kto je doma?',
        text:
            'Porcie, alergény a jedlá sa budú plánovať podľa členov domácnosti.',
        child: Column(children: [
          TextField(
              controller: adultName,
              decoration: const InputDecoration(labelText: 'Meno dospelého')),
          const SizedBox(height: 10),
          SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: hasChild,
              onChanged: (v) => setState(() => hasChild = v),
              title: const Text('Pridať dieťa')),
          if (hasChild)
            TextField(
                controller: childName,
                decoration: const InputDecoration(labelText: 'Meno dieťaťa')),
          const SizedBox(height: 8),
          Text(
              'Ďalších členov, alergény a veľkosť porcií doplníš kedykoľvek v Nastaveniach.',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  Widget _pantry() => _frame(
        icon: Icons.kitchen_outlined,
        title: 'Chceš využívať zásoby?',
        text:
            'Keď je táto voľba zapnutá, PRÍDEL odpočíta to, čo máš v Chladničke, Špajzi a Mrazničke, a uprednostní potraviny pred spotrebou.',
        child: Card(
            child: SwitchListTile(
                value: usePantry,
                onChanged: (v) => setState(() => usePantry = v),
                title: const Text('Využívať zásoby'),
                subtitle:
                    const Text('Môžeš to neskôr vypnúť bez vymazania zásob.'))),
      );

  Widget _plan() => _frame(
        icon: Icons.calendar_month_outlined,
        title: 'Ako ďaleko plánovať?',
        text:
            'Nastavenie určuje, koľko dní dopredu chceš mať bežne pripravených. Kalendár samotný nemá pevný koniec.',
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 dní')),
            ButtonSegment(value: 14, label: Text('14 dní')),
            ButtonSegment(value: 28, label: Text('28 dní')),
          ],
          selected: {horizon},
          onSelectionChanged: (v) => setState(() => horizon = v.first),
        ),
      );

  Widget _alerts() => _frame(
        icon: Icons.notifications_none,
        title: 'Užitočné upozornenia',
        text:
            'PRÍDEL môže upozorniť na potraviny pred spotrebou, zvyšky a chýbajúci plán. Po potvrdení upozornenie zmizne.',
        child: Card(
            child: SwitchListTile(
                value: alerts,
                onChanged: (v) => setState(() => alerts = v),
                title: const Text('Upozornenia v aplikácii'),
                subtitle: const Text(
                    'Systémové notifikácie mimo aplikácie pridáme až po samostatnom povolení v release verzii.'))),
      );
}
