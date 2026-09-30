import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/household_member.dart';
import '../models/leftover.dart';
import '../models/meal_entry.dart';
import '../models/planning.dart';
import '../models/recipe.dart';
import '../services/planner_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/meal_types.dart';
import '../widgets/page_header.dart';
import 'recipe_detail_screen.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late DateTime weekStart;
  late DateTime selectedDay;
  late final PlannerService planner;
  List<MealEntry> entries = const [];
  WeekBalanceSummary? balance;
  Map<int, List<String>> warnings = const {};
  bool loading = true;
  int _loadToken = 0;
  bool generating = false;

  @override
  void initState() {
    super.initState();
    final today = PridelDates.dateOnly(DateTime.now());
    weekStart = PridelDates.startOfWeek(today);
    selectedDay = today;
    planner = PlannerService(widget.controller.database);
    widget.controller.addListener(_externalChange);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    super.dispose();
  }

  void _externalChange() {
    if (widget.controller.affects(AppArea.plan)) _reload();
  }

  Future<void> _reload() async {
    final token = ++_loadToken;
    final end = weekStart.add(const Duration(days: 6));
    final results = await Future.wait([
      widget.controller.database.getMealEntries(weekStart, end),
      planner.summarizeWeek(weekStart),
      planner.validateWeek(weekStart),
    ]);
    if (!mounted || token != _loadToken) return;
    setState(() {
      entries = results[0] as List<MealEntry>;
      balance = results[1] as WeekBalanceSummary;
      warnings = results[2] as Map<int, List<String>>;
      loading = false;
    });
  }

  void _moveWeek(int delta) {
    setState(() {
      weekStart = weekStart.add(Duration(days: 7 * delta));
      selectedDay = weekStart;
      loading = true;
    });
    _reload();
  }

  MealEntry? _entry(String mealType) {
    final key = PridelDates.iso(selectedDay);
    for (final e in entries) {
      if (PridelDates.iso(e.date) == key && e.mealType == mealType) return e;
    }
    return null;
  }

  Future<void> _generate() async {
    if (generating) return;
    setState(() => generating = true);
    try {
      final horizon = await widget.controller.database.getPlanHorizonDays();
      final weeks = (horizon / 7).ceil();
      for (int i = 0; i < weeks; i++) {
        await planner.generateWeek(weekStart.add(Duration(days: i * 7)),
            onlyEmpty: true);
      }
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Doplnený plán na $horizon dní.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plánovanie sa nepodarilo: $e')));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> _choose(String mealType, MealEntry? current) async {
    if (current?.isDone == true) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Hotové jedlo najprv vráť späť.')));
      return;
    }
    final choiceServings = current?.servings.isNotEmpty == true
        ? current!.servings
        : await widget.controller.database.defaultServings();
    final neededPortions = choiceServings
        .where((s) => s.eating)
        .fold<double>(0, (sum, s) => sum + s.portion);
    final leftovers = (await planner.compatibleLeftovers(selectedDay, mealType))
        .where((l) => l.portions + 0.001 >= neededPortions)
        .toList(growable: false);
    final recommendations = await planner.recommend(
      date: selectedDay,
      mealType: mealType,
      replacingEntryId: current?.id,
      limit: 10,
    );
    if (!mounted) return;

    final choice = await showModalBottomSheet<_MealChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text('Vybrať: ${MealTypes.label(mealType)}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            Text(
                'Poradie zohľadňuje pestrosť, rodinu, zásoby, cenu, čas prípravy a opakovanie jedál.',
                style: Theme.of(context).textTheme.bodySmall),
            if (leftovers.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Najprv spotrebovať',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ...leftovers.map((leftover) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            child: Icon(Icons.takeout_dining)),
                        title: Text(leftover.recipeName),
                        subtitle: Text(
                            '${_number(leftover.portions)} porcie${leftover.useBy == null ? '' : ' · do ${PridelDates.compactDay(leftover.useBy!)}'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(
                            context, _MealChoice.leftover(leftover)),
                      ),
                    ),
                  )),
            ],
            const SizedBox(height: 18),
            Text('Odporúčané recepty',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (recommendations.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                      'Pre tieto pravidlá sa nenašiel vhodný recept. Skontroluj alergény a zakázané suroviny v domácnosti.')),
            ...recommendations.asMap().entries.map((item) {
              final rank = item.key + 1;
              final rec = item.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(child: Text(rank.toString())),
                    title: Text(rec.recipe.name),
                    subtitle: Text(rec.reasons.isEmpty
                        ? rec.recipe.category
                        : rec.reasons.join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.pop(context, _MealChoice.recipe(rec.recipe)),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
    if (choice == null) return;

    try {
      final servings = choiceServings;
      if (current?.recipeId != null && choice.recipe?.id != current!.recipeId) {
        await widget.controller.database.setRecipeCooldown(
            current.recipeId!, DateTime.now().add(const Duration(days: 21)));
      }
      if (choice.leftover != null) {
        await widget.controller.database.assignLeftover(
            date: selectedDay,
            mealType: mealType,
            leftover: choice.leftover!,
            servings: servings);
      } else if (choice.recipe != null) {
        await widget.controller.database.savePlannedMeal(
            date: selectedDay,
            mealType: mealType,
            recipe: choice.recipe!,
            servings: servings);
      }
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _editServings(MealEntry entry) async {
    if (entry.isDone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pri hotovom jedle najprv zruš Hotovo.')));
      return;
    }
    final members =
        await widget.controller.database.getHousehold(activeOnly: true);
    final current = <int, MealServing>{
      for (final s in entry.servings) s.memberId: s
    };
    final drafts = <int, _ServingDraft>{
      for (final member in members)
        member.id: _ServingDraft(
          member: member,
          eating: current[member.id]?.eating ?? true,
          portion: current[member.id]?.portion ?? member.portion,
        )
    };
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Kto bude jesť?',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              ...members.map((member) {
                final draft = drafts[member.id]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Checkbox(
                              value: draft.eating,
                              onChanged: (v) => setSheetState(
                                  () => draft.eating = v ?? false)),
                          Expanded(child: Text(member.name)),
                          DropdownButton<double>(
                            value: draft.portion,
                            onChanged: draft.eating
                                ? (v) =>
                                    setSheetState(() => draft.portion = v ?? 1)
                                : null,
                            items: const [
                              DropdownMenuItem(value: 0.5, child: Text('½')),
                              DropdownMenuItem(value: 1.0, child: Text('1')),
                              DropdownMenuItem(value: 1.5, child: Text('1½')),
                              DropdownMenuItem(value: 2.0, child: Text('2')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Uložiť porcie')),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    final servings = [
      for (final draft in drafts.values)
        MealServing(
            memberId: draft.member.id,
            name: draft.member.name,
            role: draft.member.role,
            portion: draft.portion,
            eating: draft.eating)
    ];
    try {
      await widget.controller.database.updateMealServings(entry.id, servings);
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _complete(MealEntry entry) async {
    final preview =
        await widget.controller.database.previewCompletion(entry.id);
    if (!mounted) return;
    final leftoverController = TextEditingController(text: '0');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Označiť jedlo ako hotové?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (preview.hasShortages) ...[
              Text('V sklade chýbajú: ${preview.shortages.keys.join(', ')}.',
                  style: const TextStyle(
                      color: AppTheme.warning, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text(
                  'Ak si suroviny mala mimo evidencie, môžeš pokračovať. Zo skladu sa odpočíta iba to, čo je v ňom naozaj evidované.'),
              const SizedBox(height: 14),
            ],
            if (!entry.isLeftover)
              TextField(
                controller: leftoverController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Koľko hotových porcií zostalo?',
                    helperText: '0 = nič nezostalo'),
              )
            else
              const Text(
                  'Ak časť zvyšku nezješ, zostávajúce porcie sa automaticky vrátia medzi dostupné zvyšky.'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušiť')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hotovo')),
        ],
      ),
    );
    final leftover =
        double.tryParse(leftoverController.text.replaceAll(',', '.')) ?? 0;
    leftoverController.dispose();
    if (confirmed != true) return;
    try {
      await widget.controller.database.completeMeal(entry.id,
          leftoverPortions: leftover, allowShortage: preview.hasShortages);
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _undo(MealEntry entry) async {
    try {
      await widget.controller.database.undoMealCompletion(entry.id);
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _clear(MealEntry entry) async {
    try {
      await widget.controller.database.clearMeal(entry.id);
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _discardPlannedLeftover(MealEntry entry) async {
    if (entry.leftoverId == null || entry.isDone) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vyhodiť zvyšok?'),
        content: const Text(
            'Zvyšok sa odstráni z jedálnička aj zo zoznamu dostupných zvyškov.'),
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
      final leftoverId = entry.leftoverId!;
      await widget.controller.database.clearMeal(entry.id);
      await widget.controller.database.discardLeftover(leftoverId);
      widget.controller.dataChanged(
          {AppArea.plan, AppArea.shopping, AppArea.pantry, AppArea.leftovers});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _openRecipe(MealEntry entry) {
    final recipe = entry.snapshot;
    if (recipe == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => RecipeDetailScreen(
          controller: widget.controller, recipe: recipe, snapshotOnly: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final today = PridelDates.dateOnly(DateTime.now());
    return Column(
      children: [
        PageHeader(
          title: 'PRÍDEL',
          subtitle: PridelDates.weekRange(weekStart),
          trailing: IconButton.filledTonal(
            tooltip: 'Doplniť plán podľa nastaveného horizontu',
            onPressed: generating ? null : _generate,
            icon: generating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome_outlined),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              IconButton(
                  onPressed: () => _moveWeek(-1),
                  icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      weekStart = PridelDates.startOfWeek(today);
                      selectedDay = today;
                      loading = true;
                    });
                    _reload();
                  },
                  child: const Text('Tento týždeň'),
                ),
              ),
              IconButton(
                  onPressed: () => _moveWeek(1),
                  icon: const Icon(Icons.chevron_right)),
            ],
          ),
        ),
        SizedBox(
          height: 68,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: 7,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final day = weekStart.add(Duration(days: index));
              final selected =
                  PridelDates.iso(day) == PridelDates.iso(selectedDay);
              final isToday = PridelDates.iso(day) == PridelDates.iso(today);
              return ChoiceChip(
                selected: selected,
                onSelected: (_) => setState(() => selectedDay = day),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(PridelDates.weekdayShort[index]),
                    Text('${day.day}',
                        style: TextStyle(
                            fontWeight:
                                isToday ? FontWeight.w800 : FontWeight.w600)),
                  ],
                ),
              );
            },
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: [
                      _BalanceCard(summary: balance),
                      const SizedBox(height: 16),
                      Text(PridelDates.dayLabel(selectedDay),
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 10),
                      ...MealTypes.ordered.map((type) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _mealCard(type, _entry(type)),
                          )),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _mealCard(String type, MealEntry? entry) {
    if (entry == null || entry.snapshot == null) {
      return Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          leading: CircleAvatar(child: Icon(_mealIcon(type))),
          title: Text(MealTypes.label(type),
              style: Theme.of(context).textTheme.titleMedium),
          subtitle: const Text('Zatiaľ nenaplánované'),
          trailing: FilledButton.tonal(
              onPressed: () => _choose(type, null),
              child: const Text('Vybrať')),
        ),
      );
    }
    final recipe = entry.snapshot!;
    final eating = entry.servings.where((s) => s.eating).length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                    child: Icon(entry.isLeftover
                        ? Icons.takeout_dining
                        : _mealIcon(type))),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _openRecipe(entry),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(MealTypes.label(type),
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 3),
                          Text(recipe.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 5),
                          Text(
                              [
                                if (recipe.prepMin != null)
                                  '${recipe.prepMin} min',
                                '$eating ${eating == 1 ? 'osoba' : 'osoby'}',
                                if (entry.isLeftover) 'zo zvyškov',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ),
                if (entry.isDone)
                  const Padding(
                    padding: EdgeInsets.only(left: 8, top: 4),
                    child: Icon(Icons.check_circle, color: AppTheme.success),
                  ),
              ],
            ),
            if ((warnings[entry.id] ?? const []).isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        size: 18, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text((warnings[entry.id] ?? const []).join('\n'),
                            style: Theme.of(context).textTheme.bodySmall)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (!entry.isDone)
                  TextButton.icon(
                      onPressed: () => _choose(type, entry),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Vymeniť')),
                if (!entry.isDone)
                  TextButton.icon(
                      onPressed: () => _editServings(entry),
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: const Text('Porcie')),
                if (!entry.isDone)
                  TextButton.icon(
                      onPressed: () => _complete(entry),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Hotovo')),
                if (entry.isDone)
                  TextButton.icon(
                      onPressed: () => _undo(entry),
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Vrátiť Hotovo')),
                if (!entry.isDone && entry.isLeftover)
                  TextButton.icon(
                    onPressed: () => _discardPlannedLeftover(entry),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Vyhodiť zvyšok'),
                  )
                else if (!entry.isDone)
                  IconButton(
                      tooltip: 'Odstrániť z plánu',
                      onPressed: () => _clear(entry),
                      icon: const Icon(Icons.close, size: 19)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _mealIcon(String type) {
    switch (type) {
      case MealTypes.breakfast:
        return Icons.breakfast_dining;
      case MealTypes.snack:
        return Icons.eco_outlined;
      case MealTypes.soup:
        return Icons.soup_kitchen;
      case MealTypes.lunch:
        return Icons.lunch_dining;
      case MealTypes.afternoon:
        return Icons.bakery_dining;
      case MealTypes.dinner:
        return Icons.dinner_dining;
      default:
        return Icons.restaurant_outlined;
    }
  }

  static String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});
  final WeekBalanceSummary? summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.balance_outlined, size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Pestrosť týždňa',
                      style: Theme.of(context).textTheme.titleMedium)),
              Text('${s.targetsMet}/${s.targetCount}',
                  style: Theme.of(context).textTheme.labelLarge),
            ]),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: s.targetsMet / s.targetCount),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _metric('Ryba', '${s.fishMains}/${s.targetFishMains}×',
                    s.fishOnTarget),
                _metric(
                    'Bezmäsité',
                    '${s.vegetarianMains}/${s.targetVegetarianMains}×',
                    s.vegetarianOnTarget),
                _metric(
                    'Strukoviny',
                    '${s.legumeMains}/${s.targetLegumeMains}×',
                    s.legumesOnTarget),
                _metric(
                    'Ovocie',
                    '${s.fruitSnackDays}/${s.targetFruitDays} dní',
                    s.fruitOnTarget),
                _metric(
                    'Zelenina',
                    '${s.vegetableMainDays}/${s.targetVegetableDays} dní',
                    s.vegetablesOnTarget),
                _metric('Sladké hlavné', '${s.sweetMains} ≤ ${s.maxSweetMains}',
                    s.sweetOnTarget),
                _metric(
                    'Pestrosť hlavných',
                    '${(s.uniqueMainRatio * 100).round()} %',
                    s.varietyOnTarget),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              s.looksBalanced
                  ? 'Plán spĺňa väčšinu nastavených pravidiel pestrosti.'
                  : 'Niektoré pravidlá pestrosti ešte nie sú splnené. Generátor ich pri ďalších voľbách zvýhodní.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
                'Ide o kontrolu pestrosti, nie individuálne výživové alebo zdravotné odporúčanie.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: ok ? AppTheme.success.withValues(alpha: 0.08) : AppTheme.soft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(ok ? Icons.check_circle_outline : Icons.circle_outlined,
                size: 14, color: ok ? AppTheme.success : AppTheme.muted),
            const SizedBox(width: 5),
            Text('$label $value',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _ServingDraft {
  _ServingDraft(
      {required this.member, required this.eating, required this.portion});
  final HouseholdMember member;
  bool eating;
  double portion;
}

class _MealChoice {
  const _MealChoice._({this.recipe, this.leftover});
  final Recipe? recipe;
  final Leftover? leftover;
  factory _MealChoice.recipe(Recipe recipe) => _MealChoice._(recipe: recipe);
  factory _MealChoice.leftover(Leftover leftover) =>
      _MealChoice._(leftover: leftover);
}
