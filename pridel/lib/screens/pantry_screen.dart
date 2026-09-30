import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/ingredient.dart';
import '../models/pantry_item.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/unit_math.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import 'leftovers_screen.dart';
import 'recipe_detail_screen.dart';

class PantryScreen extends StatefulWidget {
  const PantryScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<PantryScreen> createState() => _PantryScreenState();
}

class _PantryScreenState extends State<PantryScreen> {
  static const categoryOrder = [
    'Koreniny',
    'Mäso',
    'Ryby',
    'Zelenina',
    'Ovocie',
    'Mliečne',
    'Vajcia',
    'Pečivo',
    'Pečivo a prílohy',
    'Trvanlivé',
    'Mrazené/konzervy',
    'Chladené',
    'Nápoje',
    'Dochucovadlá',
    'Voda',
    'Ostatné'
  ];
  List<PantryItem> items = const [];
  List<IngredientDefinition> definitions = const [];
  int leftoverCount = 0;
  bool usePantry = true;
  bool loading = true;
  int _loadToken = 0;
  String query = '';
  String location = 'all';
  final quick = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_externalChange);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    quick.dispose();
    super.dispose();
  }

  void _externalChange() {
    if (widget.controller.affects(AppArea.pantry)) _reload();
  }

  Future<void> _reload() async {
    final token = ++_loadToken;
    final results = await Future.wait([
      widget.controller.database.getPantry(),
      widget.controller.database.getIngredients(),
      widget.controller.database.getLeftovers(status: 'available'),
      widget.controller.database.getUsePantry()
    ]);
    if (!mounted || token != _loadToken) return;
    setState(() {
      items = results[0] as List<PantryItem>;
      definitions = results[1] as List<IngredientDefinition>;
      leftoverCount = (results[2] as List).length;
      usePantry = results[3] as bool;
      loading = false;
    });
  }

  IngredientDefinition? _definition(String name) {
    for (final d in definitions) {
      if (d.name.toLowerCase() == name.toLowerCase()) return d;
    }
    return null;
  }

  String _categoryFor(String name) => _definition(name)?.category ?? 'Ostatné';
  String _locationLabel(String value) => switch (value) {
        'fridge' => 'Chladnička',
        'freezer' => 'Mraznička',
        'pantry' => 'Špajza',
        _ => 'Všetko'
      };
  IconData _locationIcon(String value) => switch (value) {
        'fridge' => Icons.kitchen_outlined,
        'freezer' => Icons.ac_unit,
        'pantry' => Icons.inventory_2_outlined,
        _ => Icons.apps
      };

  Future<void> _quickAdd() async {
    final text = quick.text.trim();
    if (text.isEmpty) return;
    final match = RegExp(
            r'^(.+?)\s+(\d+(?:[\.,]\d+)?)\s*([a-zA-ZáäčďéíĺľňóôŕšťúýžÁÄČĎÉÍĹĽŇÓÔŔŠŤÚÝŽ]+)?$')
        .firstMatch(text);
    String name = text;
    double qty = 1;
    String? unit;
    if (match != null) {
      name = match.group(1)!.trim();
      qty = double.tryParse(match.group(2)!.replaceAll(',', '.')) ?? 1;
      unit = match.group(3)?.trim();
    }
    final def = _definition(name) ??
        definitions
            .where((d) => d.name.toLowerCase().startsWith(name.toLowerCase()))
            .firstOrNull;
    if (def != null) {
      name = def.name;
      unit ??= def.unit;
    }
    unit ??= 'ks';
    try {
      await widget.controller.database.addPantryItem(
          name: name,
          qty: qty,
          unit: unit,
          location: location == 'all' ? null : location);
      quick.clear();
      HapticFeedback.selectionClick();
      widget.controller.dataChanged({AppArea.pantry, AppArea.shopping});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Nedá sa pridať: $e')));
    }
  }

  Future<void> _add() async {
    IngredientDefinition? selected;
    final name = TextEditingController();
    final qty = TextEditingController();
    final unit = TextEditingController(text: 'g');
    DateTime? expiry;
    String targetLocation = location == 'all' ? 'pantry' : location;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
          builder: (context, setSheetState) => Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
                child: SingleChildScrollView(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Text('Pridať do zásob',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: name,
                                decoration: const InputDecoration(
                                    labelText: 'Potravina'))),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                            onPressed: () async {
                              final pick =
                                  await showSearch<IngredientDefinition?>(
                                      context: context,
                                      delegate:
                                          _PantryIngredientSearch(definitions));
                              if (pick == null) return;
                              setSheetState(() {
                                selected = pick;
                                name.text = pick.name;
                                unit.text = pick.unit;
                                targetLocation = widget.controller.database
                                    .defaultStorageLocation(pick, pick.name);
                              });
                            },
                            icon: const Icon(Icons.search))
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                controller: qty,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                decoration: const InputDecoration(
                                    labelText: 'Množstvo'))),
                        const SizedBox(width: 8),
                        SizedBox(
                            width: 92,
                            child: TextField(
                                controller: unit,
                                enabled: selected == null,
                                decoration:
                                    const InputDecoration(labelText: 'Jedn.')))
                      ]),
                      const SizedBox(height: 10),
                      SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                                value: 'fridge', label: Text('Chladnička')),
                            ButtonSegment(
                                value: 'pantry', label: Text('Špajza')),
                            ButtonSegment(
                                value: 'freezer', label: Text('Mraznička'))
                          ],
                          selected: {
                            targetLocation
                          },
                          onSelectionChanged: (v) =>
                              setSheetState(() => targetLocation = v.first)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                                context: context,
                                firstDate: DateTime.now()
                                    .subtract(const Duration(days: 1)),
                                lastDate: DateTime.now()
                                    .add(const Duration(days: 3650)),
                                initialDate: expiry ??
                                    DateTime.now()
                                        .add(const Duration(days: 7)));
                            if (picked != null)
                              setSheetState(() => expiry = picked);
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text(expiry == null
                              ? 'Pridať dátum spotreby'
                              : 'Spotrebovať do ${PridelDates.compactDay(expiry!)}')),
                      if (expiry != null)
                        TextButton(
                            onPressed: () => setSheetState(() => expiry = null),
                            child: const Text('Bez dátumu spotreby')),
                      const SizedBox(height: 10),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Pridať')),
                    ])),
              )),
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      try {
        await widget.controller.database.addPantryItem(
            name: name.text.trim(),
            qty: double.tryParse(qty.text.replaceAll(',', '.')) ?? 0,
            unit: unit.text.trim().isEmpty ? 'g' : unit.text.trim(),
            expiry: expiry,
            location: targetLocation);
        HapticFeedback.selectionClick();
        widget.controller.dataChanged({AppArea.pantry, AppArea.shopping});
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    name.dispose();
    qty.dispose();
    unit.dispose();
  }

  Future<void> _edit(PantryItem item) async {
    final qty = TextEditingController(
        text: item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 1));
    DateTime? expiry = item.expiry;
    String targetLocation = item.location;
    final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) => Padding(
                  padding: EdgeInsets.fromLTRB(
                      20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(item.ingredientName,
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 14),
                        TextField(
                            controller: qty,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: 'Množstvo (${item.unit})')),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                  value: 'fridge', label: Text('Chladnička')),
                              ButtonSegment(
                                  value: 'pantry', label: Text('Špajza')),
                              ButtonSegment(
                                  value: 'freezer', label: Text('Mraznička'))
                            ],
                            selected: {
                              targetLocation
                            },
                            onSelectionChanged: (v) =>
                                setSheetState(() => targetLocation = v.first)),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                  context: context,
                                  firstDate: DateTime.now()
                                      .subtract(const Duration(days: 365)),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 3650)),
                                  initialDate: expiry ??
                                      DateTime.now()
                                          .add(const Duration(days: 7)));
                              if (picked != null)
                                setSheetState(() => expiry = picked);
                            },
                            icon: const Icon(Icons.event_outlined),
                            label: Text(expiry == null
                                ? 'Pridať dátum spotreby'
                                : 'Spotrebovať do ${PridelDates.compactDay(expiry!)}')),
                        if (expiry != null)
                          TextButton(
                              onPressed: () =>
                                  setSheetState(() => expiry = null),
                              child: const Text('Odstrániť dátum')),
                        const SizedBox(height: 10),
                        FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Uložiť')),
                      ]),
                )));
    if (saved == true) {
      try {
        await widget.controller.database.updatePantryItem(item,
            qty: double.tryParse(qty.text.replaceAll(',', '.')) ?? item.qty,
            expiry: expiry,
            location: targetLocation);
        widget.controller.dataChanged({AppArea.pantry, AppArea.shopping});
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    qty.dispose();
  }

  Future<void> _recipesFor(PantryItem item) async {
    final recipes = await widget.controller.database
        .getRecipesContainingIngredient(item.ingredientName);
    if (!mounted) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: .7,
            minChildSize: .4,
            maxChildSize: .92,
            builder: (context, scrollController) => ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    children: [
                      Text('Recepty s: ${item.ingredientName}',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 12),
                      if (recipes.isEmpty)
                        const Text('Zatiaľ nie je recept s touto surovinou.'),
                      ...recipes.map((r) => Card(
                          child: ListTile(
                              title: Text(r.name),
                              subtitle: Text(r.category),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.of(this.context).push(
                                    MaterialPageRoute(
                                        builder: (_) => RecipeDetailScreen(
                                            controller: widget.controller,
                                            recipe: r)));
                              })))
                    ])));
  }

  @override
  Widget build(BuildContext context) {
    final q = query.trim().toLowerCase();
    final visible = items
        .where((item) =>
            (location == 'all' || item.location == location) &&
            (q.isEmpty || item.ingredientName.toLowerCase().contains(q)))
        .toList(growable: false);
    final groups = <String, List<PantryItem>>{};
    for (final item in visible) {
      groups.putIfAbsent(_categoryFor(item.ingredientName), () => []).add(item);
    }
    final categories = groups.keys.toList()
      ..sort((a, b) {
        final ai = categoryOrder.indexOf(a), bi = categoryOrder.indexOf(b);
        return (ai < 0 ? 999 : ai).compareTo(bi < 0 ? 999 : bi);
      });
    return Column(children: [
      PageHeader(
          title: 'Zásoby',
          subtitle: usePantry
              ? 'Chladnička · Špajza · Mraznička'
              : 'Zásoby si vedieš ručne, plánovanie ich ignoruje.',
          trailing: IconButton.filledTonal(
              onPressed: _add,
              icon: const Icon(Icons.add),
              tooltip: 'Pridať zásobu')),
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(children: [
            if (!usePantry)
              const Card(
                  child: ListTile(
                      leading: Icon(Icons.visibility_off_outlined),
                      title: Text('Využívanie zásob je vypnuté'),
                      subtitle: Text(
                          'Nákup ani odporúčania zásoby neodpočítavajú.'))),
            SegmentedButton<String>(segments: [
              for (final v in ['all', 'fridge', 'pantry', 'freezer'])
                ButtonSegment(
                    value: v,
                    icon: Icon(_locationIcon(v)),
                    label: Text(_locationLabel(v)))
            ], selected: {
              location
            }, onSelectionChanged: (v) => setState(() => location = v.first)),
            const SizedBox(height: 10),
            TextField(
                controller: quick,
                onSubmitted: (_) => _quickAdd(),
                decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.flash_on_outlined),
                    hintText: 'Rýchlo pridať, napr. Mlieko 2 l',
                    suffixIcon: IconButton(
                        onPressed: _quickAdd,
                        icon: const Icon(Icons.add_circle_outline)))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      onChanged: (v) => setState(() => query = v),
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Hľadať v zásobách'))),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          LeftoversScreen(controller: widget.controller))),
                  icon: Badge(
                      isLabelVisible: leftoverCount > 0,
                      label: Text('$leftoverCount'),
                      child: const Icon(Icons.takeout_dining)),
                  tooltip: 'Zvyšky')
            ]),
          ])),
      const SizedBox(height: 12),
      Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : categories.isEmpty
                  ? EmptyState(
                      icon: _locationIcon(location),
                      title: q.isEmpty
                          ? '${_locationLabel(location)} je prázdna'
                          : 'Nič sme nenašli',
                      message: q.isEmpty
                          ? 'Pridaj potraviny ručne alebo po nákupe jedným tlačidlom.'
                          : 'Skús iný názov.',
                      action: q.isEmpty
                          ? FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add),
                              label: const Text('Pridať potravinu'))
                          : null)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        return Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.only(
                                          left: 4, bottom: 8),
                                      child: Text(category,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium)),
                                  Card(
                                      child: Column(children: [
                                    for (int i = 0;
                                        i < groups[category]!.length;
                                        i++) ...[
                                      _pantryTile(groups[category]![i]),
                                      if (i < groups[category]!.length - 1)
                                        const Divider(indent: 64)
                                    ]
                                  ]))
                                ]));
                      })),
    ]);
  }

  Widget _pantryTile(PantryItem item) {
    final days = item.expiry == null
        ? null
        : PridelDates.daysBetween(DateTime.now(), item.expiry!);
    final expired = days != null && days < 0;
    final urgent = days != null && days >= 0 && days <= 3;
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: CircleAvatar(
            backgroundColor: expired
                ? AppTheme.danger.withValues(alpha: .08)
                : urgent
                    ? AppTheme.warning.withValues(alpha: .10)
                    : AppTheme.soft,
            child: Icon(expired
                ? Icons.error_outline
                : urgent
                    ? Icons.schedule_outlined
                    : _locationIcon(item.location))),
        title: Text(item.ingredientName),
        subtitle: Text([
          UnitMath.format(item.qty, item.unit),
          _locationLabel(item.location),
          if (item.expiry != null)
            expired
                ? 'po dátume ${PridelDates.compactDay(item.expiry!)}'
                : 'do ${PridelDates.compactDay(item.expiry!)}'
        ].join(' · ')),
        onTap: () => _edit(item),
        trailing: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'recipes') await _recipesFor(item);
              if (value == 'edit') await _edit(item);
              if (value == 'delete') {
                await widget.controller.database.deletePantryItem(item.id);
                widget.controller
                    .dataChanged({AppArea.pantry, AppArea.shopping});
              }
            },
            itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'recipes',
                      child: Text('Navrhni jedlo z tejto suroviny')),
                  PopupMenuItem(value: 'edit', child: Text('Upraviť')),
                  PopupMenuItem(value: 'delete', child: Text('Odstrániť'))
                ]));
  }
}

class _PantryIngredientSearch extends SearchDelegate<IngredientDefinition?> {
  _PantryIngredientSearch(this.items);
  final List<IngredientDefinition> items;
  @override
  String get searchFieldLabel => 'Potravina';
  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(onPressed: () => query = '', icon: const Icon(Icons.clear))
      ];
  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back));
  @override
  Widget buildResults(BuildContext context) => _body(context);
  @override
  Widget buildSuggestions(BuildContext context) => _body(context);
  Widget _body(BuildContext context) {
    final q = query.trim().toLowerCase();
    final filtered = items
        .where((i) => q.isEmpty || i.name.toLowerCase().contains(q))
        .take(100)
        .toList(growable: false);
    return ListView.builder(
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final item = filtered[index];
          return ListTile(
              title: Text(item.name),
              subtitle: Text('${item.category} · ${item.unit}'),
              onTap: () => close(context, item));
        });
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
