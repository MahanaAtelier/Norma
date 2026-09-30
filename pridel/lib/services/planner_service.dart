import 'dart:math' as math;

import '../data/app_database.dart';
import '../models/household_member.dart';
import '../models/ingredient.dart';
import '../models/leftover.dart';
import '../models/meal_entry.dart';
import '../models/pantry_item.dart';
import '../models/planning.dart';
import '../models/recipe.dart';
import '../utils/date_utils.dart';
import '../utils/meal_types.dart';
import '../utils/unit_math.dart';
import 'meal_math.dart';

class PlannerService {
  PlannerService(this.database);
  final AppDatabase database;

  Future<void> generateWeek(DateTime anyDay, {bool onlyEmpty = true}) async {
    final weekStart = PridelDates.startOfWeek(anyDay);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final recipes = await database.getRecipes();
    final definitions = await database.getIngredients();
    final household = await database.getHousehold(activeOnly: true);
    final servings = await database.defaultServings();
    final prefs = await database.getPlanningPreferences();
    final recipePrefs = await database.getRecipePreferences();
    final pantry = await database.getPantry();
    final usePantry = await database.getUsePantry();
    final historyStart = weekStart
        .subtract(Duration(days: math.max(35, prefs.avoidRepeatDays + 7)));
    final history = await database.getMealEntries(historyStart, weekEnd);
    final current = history
        .where((e) => !e.date.isBefore(weekStart) && !e.date.isAfter(weekEnd))
        .toList();
    final planned = <_PlannedRef>[
      for (final e in history)
        if (e.snapshot != null)
          _PlannedRef(e.date, e.mealType, e.snapshot!, e.id),
    ];
    final leftovers =
        (await database.getLeftovers(status: 'available')).toList();

    final defs = {for (final d in definitions) d.name: d};
    final projectedConsumed = <String, double>{};

    for (int d = 0; d < 7; d++) {
      final date = weekStart.add(Duration(days: d));
      for (final mealType in MealTypes.ordered) {
        final existing = current
            .where((e) =>
                PridelDates.iso(e.date) == PridelDates.iso(date) &&
                e.mealType == mealType)
            .firstOrNull;
        if (onlyEmpty && existing != null) {
          if (!existing.isDone &&
              !existing.isLeftover &&
              existing.snapshot != null) {
            _addProjectedConsumption(
                projectedConsumed, existing.snapshot!, existing.servings);
          }
          continue;
        }
        if (existing?.isDone == true) continue;

        final leftover = _bestLeftover(leftovers, date, mealType, servings);
        if (leftover != null) {
          await database.assignLeftover(
              date: date,
              mealType: mealType,
              leftover: leftover,
              servings: servings);
          leftovers.removeWhere((x) => x.id == leftover.id);
          if (leftover.snapshot != null)
            planned.add(
                _PlannedRef(date, mealType, leftover.snapshot!, -leftover.id));
          continue;
        }

        final recommendations = _rank(
          recipes: recipes,
          definitions: defs,
          household: household,
          servings: servings,
          preferences: prefs,
          recipePreferences: recipePrefs,
          pantryTotals: _afterProjected(
              _pantryTotals(pantry, asOf: date), projectedConsumed),
          urgentPantry: _urgentPantry(pantry, date),
          usePantry: usePantry,
          planned: planned,
          date: date,
          mealType: mealType,
          replacingEntryId: existing?.id,
          limit: 1,
        );
        if (recommendations.isEmpty) continue;
        final chosen = recommendations.first.recipe;
        final id = await database.savePlannedMeal(
            date: date, mealType: mealType, recipe: chosen, servings: servings);
        planned.add(_PlannedRef(date, mealType, chosen, id));
        _addProjectedConsumption(projectedConsumed, chosen, servings);
      }
    }
  }

  Future<List<PlannerRecommendation>> recommend({
    required DateTime date,
    required String mealType,
    int? replacingEntryId,
    int limit = 8,
  }) async {
    final recipes = await database.getRecipes();
    final definitions = await database.getIngredients();
    final household = await database.getHousehold(activeOnly: true);
    final servings = replacingEntryId == null
        ? await database.defaultServings()
        : (await database.getMealEntries(date, date))
                .where((e) => e.id == replacingEntryId)
                .firstOrNull
                ?.servings ??
            await database.defaultServings();
    final prefs = await database.getPlanningPreferences();
    final recipePrefs = await database.getRecipePreferences();
    final pantry = await database.getPantry();
    final usePantry = await database.getUsePantry();
    final historyStart =
        date.subtract(Duration(days: math.max(35, prefs.avoidRepeatDays + 7)));
    final weekStart = PridelDates.startOfWeek(date);
    final history = await database.getMealEntries(
        historyStart, weekStart.add(const Duration(days: 6)));
    final planned = <_PlannedRef>[
      for (final e in history)
        if (e.snapshot != null && e.id != replacingEntryId)
          _PlannedRef(e.date, e.mealType, e.snapshot!, e.id),
    ];
    return _rank(
      recipes: recipes,
      definitions: {for (final d in definitions) d.name: d},
      household: household,
      servings: servings,
      preferences: prefs,
      recipePreferences: recipePrefs,
      pantryTotals: _pantryTotals(pantry, asOf: date),
      urgentPantry: _urgentPantry(pantry, date),
      usePantry: usePantry,
      planned: planned,
      date: date,
      mealType: mealType,
      replacingEntryId: replacingEntryId,
      limit: limit,
    );
  }

  Future<List<Leftover>> compatibleLeftovers(
      DateTime date, String mealType) async {
    final leftovers = await database.getLeftovers(status: 'available');
    return leftovers.where((l) {
      if (l.snapshot == null) return false;
      if (l.createdAt.isAfter(date)) return false;
      if (l.useBy != null &&
          PridelDates.dateOnly(l.useBy!).isBefore(PridelDates.dateOnly(date)))
        return false;
      return _compatible(l.snapshot!, mealType);
    }).toList(growable: false);
  }

  Future<Map<int, List<String>>> validateWeek(DateTime anyDay) async {
    final start = PridelDates.startOfWeek(anyDay);
    final end = start.add(const Duration(days: 6));
    final entries = await database.getMealEntries(start, end);
    final household = {for (final m in await database.getHousehold()) m.id: m};
    final leftovers = {for (final l in await database.getLeftovers()) l.id: l};
    final warnings = <int, List<String>>{};

    for (final entry in entries) {
      final issues = <String>[];
      final recipe = entry.snapshot;
      final eating = entry.servings
          .where((s) => s.eating && s.portion > 0)
          .toList(growable: false);
      if (eating.isEmpty)
        issues.add('Pri jedle nie je označený žiadny stravník.');
      if (recipe != null) {
        for (final serving in eating) {
          final member = household[serving.memberId];
          if (member == null) continue;
          final conflict = _firstConflict(recipe, member);
          if (conflict != null) {
            issues.add('${member.name}: konflikt „$conflict“');
          }
        }
      }
      if (entry.leftoverId != null) {
        final leftover = leftovers[entry.leftoverId!];
        if (leftover == null) {
          issues.add('Naplánovaný zvyšok už neexistuje.');
        } else if (leftover.useBy != null &&
            PridelDates.dateOnly(leftover.useBy!)
                .isBefore(PridelDates.dateOnly(entry.date))) {
          issues.add('Zvyšok je naplánovaný po dátume spotreby.');
        }
      }
      if (!entry.isDone &&
          entry.date.isBefore(PridelDates.dateOnly(DateTime.now()))) {
        issues.add('Jedlo je v minulosti a nie je označené ako hotové.');
      }
      if (issues.isNotEmpty) warnings[entry.id] = issues;
    }
    return warnings;
  }

  Future<WeekBalanceSummary> summarizeWeek(DateTime anyDay) async {
    final start = PridelDates.startOfWeek(anyDay);
    final entries = await database.getMealEntries(
        start, start.add(const Duration(days: 6)));
    final definitions = {
      for (final d in await database.getIngredients()) d.name: d
    };
    final preferences = await database.getPlanningPreferences();
    final mains = entries
        .where((e) => MealTypes.isMain(e.mealType) && e.snapshot != null)
        .toList();
    int fish = 0,
        vegetarian = 0,
        legumes = 0,
        sweet = 0,
        fruitDays = 0,
        vegDays = 0;
    final mainIds = <String>{};
    final fruitDates = <String>{};
    final vegDates = <String>{};
    for (final e in entries) {
      final recipe = e.snapshot;
      if (recipe == null) continue;
      if (_hasCategory(recipe, definitions, 'Ovocie') &&
          (e.mealType == MealTypes.snack ||
              e.mealType == MealTypes.afternoon ||
              e.mealType == MealTypes.breakfast)) {
        fruitDates.add(PridelDates.iso(e.date));
      }
      if (_hasCategory(recipe, definitions, 'Zelenina') &&
          MealTypes.isMain(e.mealType)) vegDates.add(PridelDates.iso(e.date));
      if (MealTypes.isMain(e.mealType)) {
        mainIds.add(recipe.id);
        final protein = _protein(recipe, definitions);
        if (protein == 'fish') fish++;
        if (_isVegetarian(recipe, definitions)) vegetarian++;
        if (_isLegume(recipe)) legumes++;
        if (_isSweet(recipe)) sweet++;
      }
    }
    fruitDays = fruitDates.length;
    vegDays = vegDates.length;
    return WeekBalanceSummary(
      fishMains: fish,
      vegetarianMains: vegetarian,
      legumeMains: legumes,
      sweetMains: sweet,
      fruitSnackDays: fruitDays,
      vegetableMainDays: vegDays,
      uniqueMainRatio: mains.isEmpty ? 1 : mainIds.length / mains.length,
      targetFishMains: preferences.fishPerWeek,
      targetVegetarianMains: preferences.vegetarianMainsPerWeek,
      targetLegumeMains: preferences.legumeMainsPerWeek,
      maxSweetMains: preferences.maxSweetMainsPerWeek,
      targetFruitDays: preferences.minFruitDaysPerWeek,
      targetVegetableDays: preferences.minVegetableMainDaysPerWeek,
    );
  }

  List<PlannerRecommendation> _rank({
    required List<Recipe> recipes,
    required Map<String, IngredientDefinition> definitions,
    required List<HouseholdMember> household,
    required List<MealServing> servings,
    required PlanningPreferences preferences,
    required Map<String, RecipePreference> recipePreferences,
    required Map<String, double> pantryTotals,
    required Set<String> urgentPantry,
    required bool usePantry,
    required List<_PlannedRef> planned,
    required DateTime date,
    required String mealType,
    required int? replacingEntryId,
    required int limit,
  }) {
    final weekStart = PridelDates.startOfWeek(date);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final week = planned
        .where((e) =>
            !e.date.isBefore(weekStart) &&
            !e.date.isAfter(weekEnd) &&
            e.id != replacingEntryId)
        .toList();
    final weekMains = week.where((e) => MealTypes.isMain(e.mealType)).toList();
    final fishCount = weekMains
        .where((e) => _protein(e.recipe, definitions) == 'fish')
        .length;
    final vegCount =
        weekMains.where((e) => _isVegetarian(e.recipe, definitions)).length;
    final legumeCount = weekMains.where((e) => _isLegume(e.recipe)).length;
    final sweetCount = weekMains.where((e) => _isSweet(e.recipe)).length;
    final fruitDates = week
        .where((e) => _hasCategory(e.recipe, definitions, 'Ovocie'))
        .map((e) => PridelDates.iso(e.date))
        .toSet();
    final vegetableDates = weekMains
        .where((e) => _hasCategory(e.recipe, definitions, 'Zelenina'))
        .map((e) => PridelDates.iso(e.date))
        .toSet();
    final sameDay = week
        .where((e) => PridelDates.iso(e.date) == PridelDates.iso(date))
        .toList(growable: false);
    final dayHasFruit =
        sameDay.any((e) => _hasCategory(e.recipe, definitions, 'Ovocie'));
    final dayHasVegetable =
        sameDay.any((e) => _hasCategory(e.recipe, definitions, 'Zelenina'));
    final weekProgress = math.max(0.0, math.min(1.0, date.weekday / 7.0));

    final recommendations = <PlannerRecommendation>[];
    for (final recipe in recipes) {
      if (!_compatible(recipe, mealType)) continue;
      final pref = recipePreferences[recipe.id] ??
          const RecipePreference(favorite: false, blocked: false);
      if (pref.blocked) continue;
      if (pref.cooldownUntil != null && !pref.cooldownUntil!.isBefore(date))
        continue;
      final eatingIds =
          servings.where((s) => s.eating).map((s) => s.memberId).toSet();
      final eatingHousehold = household
          .where((m) => eatingIds.contains(m.id))
          .toList(growable: false);
      if (_conflictsWithHousehold(recipe, eatingHousehold)) continue;
      if (MealTypes.isMain(mealType) &&
          _isSweet(recipe) &&
          sweetCount >= preferences.maxSweetMainsPerWeek) continue;

      double score = 100;
      final reasons = <String>[];
      final sameWeek = week.where((e) => e.recipe.id == recipe.id).length;
      if (sameWeek > 0) score -= 240;

      final previousUses = planned
          .where((e) => e.recipe.id == recipe.id && e.date.isBefore(date))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      if (previousUses.isNotEmpty) {
        final days = PridelDates.daysBetween(previousUses.first.date, date);
        if (days <= 7) {
          score -= 170;
        } else if (days < preferences.avoidRepeatDays) {
          score -= 38 *
              (preferences.avoidRepeatDays - days) /
              math.max(1, preferences.avoidRepeatDays);
        }
      }

      if (pref.favorite) {
        score += 25;
        reasons.add('obľúbené jedlo');
      }

      final protein = _protein(recipe, definitions);
      if (MealTypes.isMain(mealType)) {
        if (protein == 'fish' && fishCount < preferences.fishPerWeek) {
          score += 24 + 24 * weekProgress;
          reasons.add('ryba pre pestrosť týždňa');
        }
        if (_isVegetarian(recipe, definitions) &&
            vegCount < preferences.vegetarianMainsPerWeek) {
          score += 18 + 16 * weekProgress;
          reasons.add('bezmäsité pre pestrosť');
        }
        if (_isLegume(recipe) && legumeCount < preferences.legumeMainsPerWeek) {
          score += 16 + 14 * weekProgress;
          reasons.add('strukoviny pre pestrosť');
        }
        if (_hasCategory(recipe, definitions, 'Zelenina')) {
          final missingVegetableDays = math.max(0,
              preferences.minVegetableMainDaysPerWeek - vegetableDates.length);
          final urgency =
              missingVegetableDays == 0 ? 0.0 : 8.0 + 12.0 * weekProgress;
          score += dayHasVegetable ? 4 : 12 + urgency;
          reasons.add(
              dayHasVegetable ? 'obsahuje zeleninu' : 'doplní zeleninu v dni');
        } else if (!dayHasVegetable &&
            vegetableDates.length < preferences.minVegetableMainDaysPerWeek &&
            weekProgress > 0.55) {
          score -= 10;
        }

        if (protein.isNotEmpty) {
          final streak =
              _proteinStreakBeforeDate(weekMains, date, protein, definitions);
          if (streak >= preferences.maxSameProteinStreak) {
            score -= 34;
          } else if (streak > 0) {
            score -= 10 * streak;
          }
        }
      }

      if (mealType == MealTypes.snack ||
          mealType == MealTypes.afternoon ||
          mealType == MealTypes.breakfast) {
        final hasFruit = _hasCategory(recipe, definitions, 'Ovocie');
        final missingFruitDays =
            math.max(0, preferences.minFruitDaysPerWeek - fruitDates.length);
        if (hasFruit) {
          final urgency =
              missingFruitDays == 0 ? 0.0 : 7.0 + 12.0 * weekProgress;
          score += dayHasFruit ? 5 : 14 + urgency;
          reasons.add(dayHasFruit ? 'obsahuje ovocie' : 'doplní ovocie v dni');
        } else if (!dayHasFruit && missingFruitDays > 0 && weekProgress > 0.6) {
          score -= 8;
        }
      }

      final kcalDelta = _kcalDelta(recipe, servings, mealType);
      score -= math.min(22, kcalDelta / 28);
      if (kcalDelta < 90) reasons.add('primeraná energia porcie');

      if (preferences.preferQuickWeekdays && date.weekday <= DateTime.friday) {
        final prep = recipe.prepMin;
        if (prep != null && prep <= 30) {
          score += 8;
          reasons.add('rýchle na pracovný deň');
        } else if (prep != null && prep >= 70) {
          score -= 8;
        }
      }

      if (usePantry) {
        final coverage = _pantryCoverage(recipe, servings, pantryTotals);
        score += coverage * 22;
        if (coverage >= 0.98) {
          reasons.add('bez nových surovín zo skladu');
        } else if (coverage >= 0.45) {
          reasons.add('využije zásoby doma');
        }
        if (recipe.ingredients
            .any((i) => urgentPantry.contains(i.ingredient))) {
          score += 15;
          reasons.add('využije zásobu s blízkou spotrebou');
        }
        final extraCost =
            _estimatedMissingCost(recipe, servings, definitions, pantryTotals);
        score -= math.min(14, extraCost / 2.2);
      }

      score += _stableJitter(recipe.id, date, mealType);
      recommendations.add(PlannerRecommendation(
          recipe: recipe,
          score: score,
          reasons: reasons.take(3).toList(growable: false)));
    }
    recommendations.sort((a, b) => b.score.compareTo(a.score));
    return recommendations.take(limit).toList(growable: false);
  }

  Leftover? _bestLeftover(List<Leftover> leftovers, DateTime date,
      String mealType, List<MealServing> servings) {
    final neededPortions = servings
        .where((s) => s.eating)
        .fold<double>(0, (sum, s) => sum + s.portion);
    final candidates = leftovers.where((l) {
      if (l.snapshot == null || !_compatible(l.snapshot!, mealType))
        return false;
      if (l.createdAt.isAfter(date)) return false;
      if (l.useBy != null &&
          PridelDates.dateOnly(l.useBy!).isBefore(PridelDates.dateOnly(date)))
        return false;
      return l.portions + 0.001 >= neededPortions;
    }).toList();
    candidates.sort((a, b) {
      final ad = a.useBy ?? DateTime(9999);
      final bd = b.useBy ?? DateTime(9999);
      return ad.compareTo(bd);
    });
    return candidates.firstOrNull;
  }

  bool _compatible(Recipe recipe, String mealType) {
    final category = recipe.category.toLowerCase();
    final use = recipe.mealUse.toLowerCase();
    switch (mealType) {
      case MealTypes.breakfast:
        return category.contains('raňaj') || use.contains('raňaj');
      case MealTypes.snack:
        return category.contains('desiata') || use.contains('desiata');
      case MealTypes.soup:
        return category.contains('poliev') || use.contains('poliev');
      case MealTypes.lunch:
        return (category == 'obed' ||
                category.contains('rozpočt') ||
                use == 'obed') &&
            !category.contains('poliev');
      case MealTypes.afternoon:
        return category.contains('olovrant') || use.contains('olovrant');
      case MealTypes.dinner:
        return category.contains('večera') ||
            category.contains('jednoduché jedlo') ||
            use.contains('večera');
      default:
        return false;
    }
  }

  bool _conflictsWithHousehold(Recipe recipe, List<HouseholdMember> household) {
    final recipeText =
        '${recipe.name} ${recipe.allergens} ${recipe.ingredients.map((e) => e.ingredient).join(' ')}'
            .toLowerCase();
    for (final member in household) {
      for (final raw in [
        ..._splitTerms(member.allergens),
        ..._splitTerms(member.dislikes)
      ]) {
        if (raw.length >= 3 && recipeText.contains(raw)) return true;
      }
    }
    return false;
  }

  String? _firstConflict(Recipe recipe, HouseholdMember member) {
    final recipeText =
        '${recipe.name} ${recipe.allergens} ${recipe.ingredients.map((e) => e.ingredient).join(' ')}'
            .toLowerCase();
    for (final raw in [
      ..._splitTerms(member.allergens),
      ..._splitTerms(member.dislikes)
    ]) {
      if (raw.length >= 3 && recipeText.contains(raw)) return raw;
    }
    return null;
  }

  List<String> _splitTerms(String value) => value
      .toLowerCase()
      .split(RegExp(r'[,;/\n]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  String _protein(Recipe recipe, Map<String, IngredientDefinition> defs) {
    for (final tag in recipe.tags) {
      if (tag.startsWith('protein:')) return tag.substring('protein:'.length);
    }
    if (recipe.tags.contains('fish')) return 'fish';
    final categories = recipe.ingredients
        .map((e) => defs[e.ingredient]?.category ?? '')
        .toSet();
    if (categories.contains('Ryby')) return 'fish';
    if (categories.contains('Mäso')) {
      final text =
          recipe.ingredients.map((e) => e.ingredient.toLowerCase()).join(' ');
      if (text.contains('kurac') || text.contains('morčac')) return 'chicken';
      if (text.contains('bravč')) return 'pork';
      if (text.contains('hovädz')) return 'beef';
      return 'meat';
    }
    if (categories.contains('Vajcia')) return 'egg';
    return _isVegetarian(recipe, defs) ? 'veg' : '';
  }

  bool _isVegetarian(Recipe recipe, Map<String, IngredientDefinition> defs) {
    if (recipe.tags.contains('vegetarian') ||
        recipe.tags.contains('protein:veg')) return true;
    return !recipe.ingredients.any((e) {
      final c = defs[e.ingredient]?.category ?? '';
      return c == 'Mäso' || c == 'Ryby';
    });
  }

  bool _isLegume(Recipe recipe) {
    if (recipe.tags.any((t) => t == 'legume' || t == 'protein:legume'))
      return true;
    final text =
        '${recipe.name} ${recipe.ingredients.map((e) => e.ingredient).join(' ')}'
            .toLowerCase();
    return text.contains('šošovic') ||
        text.contains('fazuľ') ||
        text.contains('cícer') ||
        text.contains('hrach') ||
        text.contains('strukovin');
  }

  bool _isSweet(Recipe recipe) {
    final tags = recipe.tags.toSet();
    if (tags.contains('sweet') || tags.contains('style:sweet')) return true;
    final text = recipe.name.toLowerCase();
    return text.contains('buchti') ||
        text.contains('palac') ||
        text.contains('lievanc') ||
        text.contains('žemľov') ||
        text.contains('ryžový nákyp');
  }

  bool _hasCategory(Recipe recipe, Map<String, IngredientDefinition> defs,
          String category) =>
      recipe.ingredients.any((i) => defs[i.ingredient]?.category == category);

  int _proteinStreakBeforeDate(
    List<_PlannedRef> weekMains,
    DateTime date,
    String protein,
    Map<String, IngredientDefinition> definitions,
  ) {
    int streak = 0;
    var cursor = PridelDates.dateOnly(date).subtract(const Duration(days: 1));
    while (streak < 7) {
      final dayProteins = weekMains
          .where((e) => PridelDates.iso(e.date) == PridelDates.iso(cursor))
          .map((e) => _protein(e.recipe, definitions))
          .where((e) => e.isNotEmpty)
          .toSet();
      if (dayProteins.isEmpty || !dayProteins.contains(protein)) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  double _kcalDelta(
      Recipe recipe, List<MealServing> servings, String mealType) {
    double totalDelta = 0;
    int count = 0;
    for (final serving in servings) {
      if (!serving.eating) continue;
      final actual = (serving.isChild ? recipe.childKcal : recipe.adultKcal);
      if (actual == null) continue;
      final target = _targetKcal(serving.isChild, mealType);
      totalDelta += (actual * serving.portion - target * serving.portion).abs();
      count++;
    }
    return count == 0 ? 0 : totalDelta / count;
  }

  double _targetKcal(bool child, String mealType) {
    final adult = switch (mealType) {
      MealTypes.breakfast => 400.0,
      MealTypes.snack => 180.0,
      MealTypes.soup => 130.0,
      MealTypes.lunch => 600.0,
      MealTypes.afternoon => 180.0,
      MealTypes.dinner => 480.0,
      _ => 300.0,
    };
    return child ? adult * 0.75 : adult;
  }

  Map<String, double> _pantryTotals(List<PantryItem> pantry, {DateTime? asOf}) {
    final result = <String, double>{};
    final date = asOf == null ? null : PridelDates.dateOnly(asOf);
    for (final item in pantry) {
      if (item.qty <= 0) continue;
      if (date != null &&
          item.expiry != null &&
          PridelDates.dateOnly(item.expiry!).isBefore(date)) continue;
      final base = UnitMath.toBase(item.qty, item.unit);
      result[item.ingredientName] =
          (result[item.ingredientName] ?? 0) + base.value;
    }
    return result;
  }

  Map<String, double> _afterProjected(
      Map<String, double> available, Map<String, double> consumed) {
    return {
      for (final entry in available.entries)
        entry.key: math.max(0.0, entry.value - (consumed[entry.key] ?? 0)),
    };
  }

  void _addProjectedConsumption(
      Map<String, double> consumed, Recipe recipe, List<MealServing> servings) {
    for (final need in MealMath.requirements(recipe, servings)) {
      consumed[need.name] = (consumed[need.name] ?? 0) + need.qty;
    }
  }

  Set<String> _urgentPantry(List<PantryItem> pantry, DateTime now) {
    return pantry
        .where((p) =>
            p.expiry != null &&
            PridelDates.daysBetween(now, p.expiry!) >= 0 &&
            PridelDates.daysBetween(now, p.expiry!) <= 3)
        .map((e) => e.ingredientName)
        .toSet();
  }

  double _pantryCoverage(Recipe recipe, List<MealServing> servings,
      Map<String, double> pantryTotals) {
    final needs = MealMath.requirements(recipe, servings);
    if (needs.isEmpty) return 0;
    double fractions = 0;
    for (final need in needs) {
      final available = pantryTotals[need.name] ?? 0;
      fractions += need.qty <= 0 ? 0 : math.min(1.0, available / need.qty);
    }
    return fractions / needs.length;
  }

  double _estimatedMissingCost(
      Recipe recipe,
      List<MealServing> servings,
      Map<String, IngredientDefinition> defs,
      Map<String, double> pantryTotals) {
    double total = 0;
    for (final need in MealMath.requirements(recipe, servings)) {
      final def = defs[need.name];
      if (def == null ||
          def.pack == null ||
          def.packPrice == null ||
          def.pack! <= 0) continue;
      final missing = math.max(0.0, need.qty - (pantryTotals[need.name] ?? 0));
      final pack = UnitMath.toBase(def.pack!, def.unit);
      if (!UnitMath.compatible(pack.unit, need.unit) || pack.value <= 0)
        continue;
      total += (missing / pack.value).ceil() * def.packPrice!;
    }
    return total;
  }

  double _stableJitter(String id, DateTime date, String mealType) {
    int value = date.year * 17 + date.month * 31 + date.day * 13;
    for (final c in '$id$mealType'.codeUnits) {
      value = (value * 33 + c) & 0x7fffffff;
    }
    return (value % 100) / 100.0;
  }
}

class _PlannedRef {
  const _PlannedRef(this.date, this.mealType, this.recipe, this.id);
  final DateTime date;
  final String mealType;
  final Recipe recipe;
  final int id;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
