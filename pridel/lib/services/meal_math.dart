import '../models/meal_entry.dart';
import '../models/recipe.dart';
import '../utils/unit_math.dart';

class IngredientNeed {
  const IngredientNeed(
      {required this.name, required this.qty, required this.unit});
  final String name;
  final double qty;
  final String unit;
}

class MealMath {
  static List<IngredientNeed> requirements(
      Recipe recipe, List<MealServing> servings) {
    final totals = <String, IngredientNeed>{};
    for (final ingredient in recipe.ingredients) {
      double total = 0;
      for (final serving in servings) {
        if (!serving.eating || serving.portion <= 0) continue;
        final perPortion =
            serving.isChild ? ingredient.childQty : ingredient.adultQty;
        total += perPortion * serving.portion;
      }
      if (total <= 0) continue;
      final base = UnitMath.toBase(total, ingredient.unit);
      final current = totals[ingredient.ingredient];
      if (current == null) {
        totals[ingredient.ingredient] = IngredientNeed(
            name: ingredient.ingredient, qty: base.value, unit: base.unit);
      } else if (UnitMath.compatible(current.unit, base.unit)) {
        totals[ingredient.ingredient] = IngredientNeed(
            name: current.name,
            qty: current.qty + base.value,
            unit: current.unit);
      }
    }
    return totals.values.toList(growable: false);
  }

  static double estimatedKcal(Recipe recipe, List<MealServing> servings) {
    double total = 0;
    for (final serving in servings) {
      if (!serving.eating || serving.portion <= 0) continue;
      final kcal = serving.isChild ? recipe.childKcal : recipe.adultKcal;
      if (kcal != null) total += kcal * serving.portion;
    }
    return total;
  }
}
