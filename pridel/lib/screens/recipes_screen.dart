import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/planning.dart';
import '../models/recipe.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';
import 'recipe_detail_screen.dart';
import 'recipe_editor_screen.dart';

class RecipesScreen extends StatefulWidget {
  const RecipesScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends State<RecipesScreen> {
  List<Recipe> recipes = const [];
  Map<String, RecipePreference> preferences = const {};
  Set<String> recentIds = const {};
  Map<String, double> pantryTotals = const {};
  bool loading = true;
  int _loadToken = 0;
  String query = '';
  String category = 'Všetky';
  bool favoritesOnly = false;
  bool customOnly = false;
  bool pantryOnly = false;
  bool recentOnly = false;
  bool quickOnly = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_externalChange);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    super.dispose();
  }

  void _externalChange() {
    if (widget.controller.consumePantryRecipeFilterRequest()) pantryOnly = true;
    if (widget.controller.affects(AppArea.recipes)) _reload();
  }

  Future<void> _reload() async {
    final token = ++_loadToken;
    final results = await Future.wait([
      widget.controller.database.getRecipes(),
      widget.controller.database.getRecipePreferences(),
      widget.controller.database.getRecentRecipeIds(),
      widget.controller.database.pantryTotalsBase(),
    ]);
    if (!mounted || token != _loadToken) return;
    setState(() {
      recipes = results[0] as List<Recipe>;
      preferences = results[1] as Map<String, RecipePreference>;
      recentIds = results[2] as Set<String>;
      pantryTotals = results[3] as Map<String, double>;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = [
      'Všetky',
      ...{for (final r in recipes) r.category}.toList()..sort()
    ];
    final q = query.trim().toLowerCase();
    final filtered = recipes.where((r) {
      final pref = preferences[r.id];
      final categoryOk = category == 'Všetky' || r.category == category;
      final textOk = q.isEmpty ||
          r.name.toLowerCase().contains(q) ||
          r.ingredients.any((i) => i.ingredient.toLowerCase().contains(q));
      final favoriteOk = !favoritesOnly || pref?.favorite == true;
      final customOk = !customOnly || r.isCustom;
      final recentOk = !recentOnly || recentIds.contains(r.id);
      final quickOk = !quickOnly || (r.prepMin != null && r.prepMin! <= 30);
      final pantryMatches = r.ingredients
          .where((i) => (pantryTotals[i.ingredient] ?? 0) > 0.0001)
          .length;
      final pantryOk = !pantryOnly ||
          (r.ingredients.isNotEmpty &&
              pantryMatches / r.ingredients.length >= 0.7);
      return categoryOk &&
          textOk &&
          favoriteOk &&
          customOk &&
          recentOk &&
          quickOk &&
          pantryOk;
    }).toList(growable: false);

    return Column(
      children: [
        PageHeader(
          title: 'Recepty',
          subtitle: loading
              ? 'Načítavam…'
              : '${recipes.length} receptov · vlastné recepty zostávajú iba v zariadení',
          trailing: IconButton.filledTonal(
            tooltip: 'Pridať vlastný recept',
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                    builder: (_) =>
                        RecipeEditorScreen(controller: widget.controller)),
              );
              if (saved == true)
                widget.controller.dataChanged({AppArea.recipes});
            },
            icon: const Icon(Icons.add),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (value) => setState(() => query = value),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Hľadať recept alebo surovinu'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: categories.length + 5,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              if (i == 0) {
                return FilterChip(
                  label: const Text('Obľúbené'),
                  selected: favoritesOnly,
                  onSelected: (value) => setState(() => favoritesOnly = value),
                  avatar: const Icon(Icons.favorite_outline, size: 17),
                );
              }
              if (i == 1) {
                return FilterChip(
                    label: const Text('Moje'),
                    selected: customOnly,
                    onSelected: (value) => setState(() => customOnly = value),
                    avatar: const Icon(Icons.edit_note, size: 17));
              }
              if (i == 2) {
                return FilterChip(
                    label: const Text('Zo zásob'),
                    selected: pantryOnly,
                    onSelected: (value) => setState(() => pantryOnly = value),
                    avatar: const Icon(Icons.kitchen_outlined, size: 17));
              }
              if (i == 3) {
                return FilterChip(
                    label: const Text('Do 30 min'),
                    selected: quickOnly,
                    onSelected: (value) => setState(() => quickOnly = value),
                    avatar: const Icon(Icons.timer_outlined, size: 17));
              }
              if (i == 4) {
                return FilterChip(
                    label: const Text('Nedávno'),
                    selected: recentOnly,
                    onSelected: (value) => setState(() => recentOnly = value),
                    avatar: const Icon(Icons.history, size: 17));
              }
              final item = categories[i - 5];
              return ChoiceChip(
                  label: Text(item),
                  selected: item == category,
                  onSelected: (_) => setState(() => category = item));
            },
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_outlined,
                      title: 'Nič sme nenašli',
                      message:
                          'Skús iný názov, surovinu alebo zruš niektorý filter.')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final recipe = filtered[i];
                        final pref = preferences[recipe.id];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 9),
                            leading: CircleAvatar(
                                child: Icon(_categoryIcon(recipe.category))),
                            title: Text(recipe.name,
                                style: Theme.of(context).textTheme.titleMedium),
                            subtitle: Text([
                              recipe.category,
                              if (recipe.prepMin != null)
                                '${recipe.prepMin} min',
                              if (recipe.isCustom) 'vlastný',
                              if (pref?.blocked == true) 'neponúkať',
                            ].join(' · ')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pref?.favorite == true)
                                  const Icon(Icons.favorite, size: 18),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) => RecipeDetailScreen(
                                      controller: widget.controller,
                                      recipe: recipe)),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  IconData _categoryIcon(String category) {
    final text = category.toLowerCase();
    if (text.contains('raňaj')) return Icons.free_breakfast;
    if (text.contains('poliev')) return Icons.soup_kitchen;
    if (text.contains('večera')) return Icons.dinner_dining;
    if (text.contains('desiata') || text.contains('olovrant'))
      return Icons.local_cafe_outlined;
    return Icons.restaurant_menu;
  }
}
