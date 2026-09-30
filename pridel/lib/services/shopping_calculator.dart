import 'dart:math' as math;

import '../models/ingredient.dart';
import '../models/meal_entry.dart';
import '../models/pantry_item.dart';
import '../models/shopping_item.dart';
import '../utils/meal_types.dart';
import '../utils/unit_math.dart';
import 'meal_math.dart';

/// Pure shopping-list calculation.
///
/// The calculator walks planned meals chronologically and virtually consumes
/// pantry lots using FEFO (earliest expiry first). A pantry lot that expires
/// before a meal date is never used for that meal. This prevents two common
/// errors: counting the same pantry quantity twice and treating expired food as
/// available for a later recipe.
class ShoppingCalculator {
  static List<ShoppingItem> calculate({
    required List<MealEntry> meals,
    required List<IngredientDefinition> definitions,
    required List<PantryItem> pantry,
    required Map<String, bool> checks,
    required bool usePantry,
  }) {
    final defs = {for (final d in definitions) d.name: d};
    final totalNeeds = <String, IngredientNeed>{};
    final missingNeeds = <String, IngredientNeed>{};
    final lots = usePantry ? _pantryLots(pantry) : <_VirtualPantryLot>[];

    final orderedMeals = meals
        .where((m) => !m.isDone && !m.isLeftover && m.snapshot != null)
        .toList(growable: false)
      ..sort((a, b) {
        final date = a.date.compareTo(b.date);
        if (date != 0) return date;
        return MealTypes.ordered
            .indexOf(a.mealType)
            .compareTo(MealTypes.ordered.indexOf(b.mealType));
      });

    for (final meal in orderedMeals) {
      for (final need in MealMath.requirements(meal.snapshot!, meal.servings)) {
        _addNeed(totalNeeds, need);
        double remaining = need.qty;
        if (usePantry) {
          for (final lot in lots) {
            if (remaining <= 0.0001) break;
            if (lot.ingredient != need.name || lot.qty <= 0) continue;
            if (!UnitMath.compatible(lot.unit, need.unit)) continue;
            if (lot.expiry != null &&
                _dateOnly(lot.expiry!).isBefore(_dateOnly(meal.date))) continue;
            final taken = math.min(remaining, lot.qty);
            lot.qty -= taken;
            remaining -= taken;
          }
        }
        if (remaining > 0.0001) {
          _addNeed(missingNeeds,
              IngredientNeed(name: need.name, qty: remaining, unit: need.unit));
        }
      }
    }

    final result = <ShoppingItem>[];
    for (final entry in missingNeeds.entries) {
      final name = entry.key;
      final missingNeed = entry.value;
      final def = defs[name];
      if (def != null && !def.buy) continue;

      final totalNeed = totalNeeds[name] ?? missingNeed;
      final canonicalUnit =
          def == null ? missingNeed.unit : UnitMath.toBase(1, def.unit).unit;
      final missingCanonical = UnitMath.compatible(
              missingNeed.unit, canonicalUnit)
          ? UnitMath.convert(missingNeed.qty, missingNeed.unit, canonicalUnit)
          : missingNeed.qty;
      final totalCanonical = UnitMath.compatible(totalNeed.unit, canonicalUnit)
          ? UnitMath.convert(totalNeed.qty, totalNeed.unit, canonicalUnit)
          : totalNeed.qty;
      final packBase =
          def?.pack == null ? null : UnitMath.toBase(def!.pack!, def.unit);

      int packages = 0;
      double purchaseQty = missingCanonical;
      double? cost;
      if (packBase != null &&
          packBase.value > 0 &&
          UnitMath.compatible(packBase.unit, canonicalUnit)) {
        packages = (missingCanonical / packBase.value).ceil();
        purchaseQty = packages * packBase.value;
        if (def!.packPrice != null) cost = packages * def.packPrice!;
      }

      result.add(ShoppingItem(
        ingredient: name,
        category: def?.category ?? 'Ostatné',
        unit: canonicalUnit,
        neededQty: missingCanonical,
        pantryUsed: math.max(0, totalCanonical - missingCanonical),
        purchaseQty: purchaseQty,
        packages: packages,
        estimatedCost: cost,
        checked: checks[name] ?? false,
      ));
    }

    result.sort((a, b) {
      final c = a.category.compareTo(b.category);
      return c != 0
          ? c
          : a.ingredient.toLowerCase().compareTo(b.ingredient.toLowerCase());
    });
    return result;
  }

  static void _addNeed(Map<String, IngredientNeed> map, IngredientNeed need) {
    final current = map[need.name];
    if (current == null) {
      map[need.name] = need;
    } else if (UnitMath.compatible(current.unit, need.unit)) {
      map[need.name] = IngredientNeed(
          name: need.name, qty: current.qty + need.qty, unit: current.unit);
    }
  }

  static List<_VirtualPantryLot> _pantryLots(List<PantryItem> pantry) {
    final result = <_VirtualPantryLot>[];
    for (final item in pantry) {
      if (item.qty <= 0) continue;
      final base = UnitMath.toBase(item.qty, item.unit);
      result.add(_VirtualPantryLot(
        ingredient: item.ingredientName,
        qty: base.value,
        unit: base.unit,
        expiry: item.expiry,
        addedAt: item.addedAt,
      ));
    }
    result.sort((a, b) {
      final aExpiry = a.expiry ?? DateTime(9999);
      final bExpiry = b.expiry ?? DateTime(9999);
      final expiry = aExpiry.compareTo(bExpiry);
      if (expiry != 0) return expiry;
      return (a.addedAt ?? DateTime(9999))
          .compareTo(b.addedAt ?? DateTime(9999));
    });
    return result;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

class _VirtualPantryLot {
  _VirtualPantryLot({
    required this.ingredient,
    required this.qty,
    required this.unit,
    this.expiry,
    this.addedAt,
  });

  final String ingredient;
  double qty;
  final String unit;
  final DateTime? expiry;
  final DateTime? addedAt;
}
