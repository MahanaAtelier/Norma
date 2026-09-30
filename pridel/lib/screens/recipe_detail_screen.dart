import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/planning.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';
import '../utils/unit_math.dart';
import 'cooking_mode_screen.dart';
import 'recipe_editor_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  const RecipeDetailScreen({
    super.key,
    required this.controller,
    required this.recipe,
    this.snapshotOnly = false,
  });

  final AppController controller;
  final Recipe recipe;
  final bool snapshotOnly;

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  late Recipe recipe;
  RecipePreference preference =
      const RecipePreference(favorite: false, blocked: false);

  @override
  void initState() {
    super.initState();
    recipe = widget.recipe;
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final value =
        await widget.controller.database.getRecipePreference(recipe.id);
    if (mounted) setState(() => preference = value);
  }

  Future<void> _toggleFavorite() async {
    await widget.controller.database
        .setRecipeFavorite(recipe.id, !preference.favorite);
    widget.controller.dataChanged({AppArea.recipes});
    await _loadPreference();
  }

  Future<void> _toggleBlocked() async {
    await widget.controller.database
        .setRecipeBlocked(recipe.id, !preference.blocked);
    widget.controller.dataChanged({AppArea.recipes});
    await _loadPreference();
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => RecipeEditorScreen(
              controller: widget.controller, existing: recipe)),
    );
    if (saved == true) {
      final refreshed = await widget.controller.database.getRecipe(recipe.id);
      widget.controller.dataChanged({AppArea.recipes});
      if (refreshed != null && mounted) setState(() => recipe = refreshed);
    }
  }

  Future<void> _duplicate() async {
    try {
      final copy = await widget.controller.database.duplicateAsCustom(recipe);
      widget.controller.dataChanged({AppArea.recipes});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vytvorila sa vlastná kópia receptu.')));
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) =>
              RecipeDetailScreen(controller: widget.controller, recipe: copy)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vymazať vlastný recept?'),
        content: const Text(
            'Recept sa odstráni z ponuky. Staré naplánované alebo uvarené jedlá zostanú v histórii ako uložená kópia.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušiť')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Vymazať')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.controller.database.deleteCustomRecipe(recipe.id);
    widget.controller.dataChanged({AppArea.recipes});
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recept'),
        actions: [
          IconButton(
            tooltip: preference.favorite
                ? 'Odobrať z obľúbených'
                : 'Pridať medzi obľúbené',
            onPressed: _toggleFavorite,
            icon: Icon(
                preference.favorite ? Icons.favorite : Icons.favorite_border),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'block') _toggleBlocked();
              if (value == 'duplicate') _duplicate();
              if (value == 'edit') _edit();
              if (value == 'delete') _delete();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'block',
                  child: Text(preference.blocked
                      ? 'Znova ponúkať'
                      : 'Neponúkať automaticky')),
              const PopupMenuItem(
                  value: 'duplicate', child: Text('Vytvoriť vlastnú kópiu')),
              if (recipe.isCustom && !widget.snapshotOnly)
                const PopupMenuItem(value: 'edit', child: Text('Upraviť')),
              if (recipe.isCustom && !widget.snapshotOnly)
                const PopupMenuItem(value: 'delete', child: Text('Vymazať')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: AppTheme.soft, borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                const CircleAvatar(
                    radius: 26, child: Icon(Icons.restaurant_menu)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(recipe.name,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 7),
                      Text(
                          [
                            recipe.category,
                            if (recipe.prepMin != null) '${recipe.prepMin} min',
                            if (recipe.isCustom) 'vlastný recept',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (preference.blocked) ...[
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.visibility_off_outlined),
                title: Text('Tento recept sa nebude automaticky ponúkať'),
                subtitle:
                    Text('V zozname receptov zostáva a môžeš ho vybrať ručne.'),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('Suroviny', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          ...recipe.ingredients.map((item) => Card(
                child: ListTile(
                  title: Text(item.ingredient),
                  subtitle: Text(
                      'dospelý ${UnitMath.format(item.adultQty, item.unit)} · dieťa ${UnitMath.format(item.childQty, item.unit)}'),
                ),
              )),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: Text('Postup',
                    style: Theme.of(context).textTheme.headlineSmall)),
            if (recipe.step.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CookingModeScreen(recipe: recipe))),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Variť'),
              ),
          ]),
          const SizedBox(height: 9),
          Text(
              recipe.step.isEmpty
                  ? 'Postup zatiaľ nie je doplnený.'
                  : recipe.step,
              style: Theme.of(context).textTheme.bodyLarge),
          if (recipe.note.isNotEmpty) ...[
            const SizedBox(height: 18),
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(recipe.note))),
          ],
          if (recipe.adultKcal != null || recipe.childKcal != null) ...[
            const SizedBox(height: 22),
            Text('Orientačná energia porcie',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
                [
                  if (recipe.adultKcal != null)
                    'dospelý ${recipe.adultKcal!.round()} kcal',
                  if (recipe.childKcal != null)
                    'dieťa ${recipe.childKcal!.round()} kcal',
                ].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (recipe.allergens.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Alergény: ${recipe.allergens}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (recipe.sourceBasis.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('Podklad: ${recipe.sourceBasis}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
