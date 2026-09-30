import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';

class RecipeEditorScreen extends StatefulWidget {
  const RecipeEditorScreen(
      {super.key, required this.controller, this.existing});
  final AppController controller;
  final Recipe? existing;

  @override
  State<RecipeEditorScreen> createState() => _RecipeEditorScreenState();
}

class _IngredientDraft {
  _IngredientDraft(
      {String name = '', String unit = 'g', double adult = 0, double child = 0})
      : name = TextEditingController(text: name),
        unit = TextEditingController(text: unit),
        adult = TextEditingController(text: adult == 0 ? '' : adult.toString()),
        child = TextEditingController(text: child == 0 ? '' : child.toString());
  final TextEditingController name;
  final TextEditingController unit;
  final TextEditingController adult;
  final TextEditingController child;
  void dispose() {
    name.dispose();
    unit.dispose();
    adult.dispose();
    child.dispose();
  }
}

class _RecipeEditorScreenState extends State<RecipeEditorScreen> {
  static const categories = [
    'Raňajky',
    'Desiata',
    'Olovrant',
    'Polievka',
    'Obed',
    'Večera',
    'Rozpočtové jedlá',
    'Jednoduchá večera',
    'Jednoduché jedlo',
    'Ostatné'
  ];

  late final TextEditingController name;
  late final TextEditingController prep;
  late final TextEditingController step;
  late final TextEditingController allergens;
  late final TextEditingController adultKcal;
  late final TextEditingController childKcal;
  late String category;
  late final List<_IngredientDraft> ingredients;
  List<IngredientDefinition> definitions = const [];
  bool loading = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    name = TextEditingController(text: r?.name ?? '');
    prep = TextEditingController(text: r?.prepMin?.toString() ?? '');
    step = TextEditingController(text: r?.step ?? '');
    allergens = TextEditingController(text: r?.allergens ?? '');
    adultKcal =
        TextEditingController(text: r?.adultKcal?.round().toString() ?? '');
    childKcal =
        TextEditingController(text: r?.childKcal?.round().toString() ?? '');
    category = categories.contains(r?.category)
        ? r!.category
        : (r?.category ?? 'Obed');
    ingredients = (r?.ingredients ?? const <RecipeIngredient>[])
        .map((i) => _IngredientDraft(
            name: i.ingredient,
            unit: i.unit,
            adult: i.adultQty,
            child: i.childQty))
        .toList();
    if (ingredients.isEmpty) ingredients.add(_IngredientDraft());
    _load();
  }

  Future<void> _load() async {
    final value = await widget.controller.database.getIngredients();
    if (mounted) {
      setState(() {
        definitions = value;
        loading = false;
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    prep.dispose();
    step.dispose();
    allergens.dispose();
    adultKcal.dispose();
    childKcal.dispose();
    for (final i in ingredients) {
      i.dispose();
    }
    super.dispose();
  }

  Future<void> _pickIngredient(_IngredientDraft draft) async {
    final selected = await showSearch<IngredientDefinition?>(
      context: context,
      delegate: _IngredientSearchDelegate(definitions),
    );
    if (selected == null) return;
    setState(() {
      draft.name.text = selected.name;
      draft.unit.text = selected.unit;
    });
  }

  String _mealUseFor(String category) {
    switch (category) {
      case 'Raňajky':
        return 'raňajky';
      case 'Desiata':
        return 'desiata';
      case 'Olovrant':
        return 'olovrant';
      case 'Polievka':
        return 'polievka';
      case 'Obed':
      case 'Rozpočtové jedlá':
        return 'obed';
      case 'Večera':
      case 'Jednoduchá večera':
      case 'Jednoduché jedlo':
        return 'večera';
      default:
        return '';
    }
  }

  Future<void> _save() async {
    if (name.text.trim().length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Napíš názov receptu.')));
      return;
    }
    final items = <RecipeIngredient>[];
    for (final draft in ingredients) {
      final ingredientName = draft.name.text.trim();
      if (ingredientName.isEmpty) continue;
      final adult = double.tryParse(draft.adult.text.replaceAll(',', '.')) ?? 0;
      final child = double.tryParse(draft.child.text.replaceAll(',', '.')) ?? 0;
      if (adult <= 0 && child <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Doplň množstvo pre surovinu $ingredientName.')));
        return;
      }
      items.add(RecipeIngredient(
        ingredient: ingredientName,
        unit: draft.unit.text.trim().isEmpty ? 'g' : draft.unit.text.trim(),
        adultQty: adult,
        childQty: child,
      ));
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pridaj aspoň jednu surovinu.')));
      return;
    }
    setState(() => saving = true);
    final old = widget.existing;
    final recipe = Recipe(
      id: old?.id ?? 'U${DateTime.now().microsecondsSinceEpoch}',
      name: name.text.trim(),
      category: category,
      mealUse: _mealUseFor(category),
      adultKcal: double.tryParse(adultKcal.text.replaceAll(',', '.')),
      childKcal: double.tryParse(childKcal.text.replaceAll(',', '.')),
      allergens: allergens.text.trim(),
      step: step.text.trim(),
      note: old?.note ?? '',
      prepMin: int.tryParse(prep.text.trim()),
      isCustom: true,
      ingredients: items,
      tags: old?.tags ?? const ['home'],
    );
    try {
      await widget.controller.database.saveCustomRecipe(recipe);
      widget.controller.dataChanged({AppArea.recipes});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.existing == null ? 'Vlastný recept' : 'Upraviť recept')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                TextField(
                    controller: name,
                    decoration:
                        const InputDecoration(labelText: 'Názov receptu')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: const InputDecoration(labelText: 'Kategória'),
                  items: categories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(growable: false),
                  onChanged: (value) =>
                      setState(() => category = value ?? category),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: prep,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Čas prípravy v minútach')),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: adultKcal,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'kcal dospelý'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: TextField(
                          controller: childKcal,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'kcal dieťa'))),
                ]),
                const SizedBox(height: 10),
                TextField(
                    controller: allergens,
                    decoration: const InputDecoration(
                        labelText: 'Alergény',
                        hintText: 'napr. mlieko, vajcia')),
                const SizedBox(height: 22),
                Row(children: [
                  Expanded(
                      child: Text('Suroviny',
                          style: Theme.of(context).textTheme.headlineSmall)),
                  IconButton.filledTonal(
                      onPressed: () =>
                          setState(() => ingredients.add(_IngredientDraft())),
                      icon: const Icon(Icons.add)),
                ]),
                const SizedBox(height: 8),
                ...List.generate(ingredients.length, (index) {
                  final item = ingredients[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(children: [
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: item.name,
                                    decoration: const InputDecoration(
                                        labelText: 'Surovina'))),
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                                tooltip: 'Vybrať zo zoznamu',
                                onPressed: () => _pickIngredient(item),
                                icon: const Icon(Icons.search)),
                            const SizedBox(width: 4),
                            SizedBox(
                                width: 78,
                                child: TextField(
                                    controller: item.unit,
                                    decoration: const InputDecoration(
                                        labelText: 'Jedn.'))),
                          ]),
                          const SizedBox(height: 8),
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    controller: item.adult,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Dospelý'))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: TextField(
                                    controller: item.child,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    decoration: const InputDecoration(
                                        labelText: 'Dieťa'))),
                            if (ingredients.length > 1)
                              IconButton(
                                tooltip: 'Odstrániť surovinu',
                                onPressed: () => setState(() {
                                  final removed = ingredients.removeAt(index);
                                  removed.dispose();
                                }),
                                icon: const Icon(Icons.close),
                              ),
                          ]),
                        ]),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 14),
                TextField(
                    controller: step,
                    minLines: 5,
                    maxLines: 12,
                    decoration: const InputDecoration(
                        labelText: 'Postup', alignLabelWithHint: true)),
                const SizedBox(height: 20),
                FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: const Icon(Icons.check),
                    label: Text(saving ? 'Ukladám…' : 'Uložiť recept')),
              ],
            ),
    );
  }
}

class _IngredientSearchDelegate extends SearchDelegate<IngredientDefinition?> {
  _IngredientSearchDelegate(this.items);
  final List<IngredientDefinition> items;

  @override
  String get searchFieldLabel => 'Hľadať surovinu';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              onPressed: () => query = '', icon: const Icon(Icons.clear)),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back));

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final q = query.trim().toLowerCase();
    final filtered = items
        .where((i) => q.isEmpty || i.name.toLowerCase().contains(q))
        .take(80)
        .toList(growable: false);
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return ListTile(
          title: Text(item.name),
          subtitle: Text('${item.category} · ${item.unit}'),
          onTap: () => close(context, item),
        );
      },
    );
  }
}
