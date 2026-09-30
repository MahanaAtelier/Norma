import 'package:flutter_test/flutter_test.dart';
import 'package:pridel/models/ingredient.dart';
import 'package:pridel/models/meal_entry.dart';
import 'package:pridel/models/pantry_item.dart';
import 'package:pridel/models/planning.dart';
import 'package:pridel/models/recipe.dart';
import 'package:pridel/services/meal_math.dart';
import 'package:pridel/services/shopping_calculator.dart';
import 'package:pridel/utils/unit_math.dart';

void main() {
  test('unit conversion normalizes mass and volume', () {
    expect(UnitMath.convert(1, 'kg', 'g'), 1000);
    expect(UnitMath.convert(1500, 'ml', 'l'), 1.5);
    expect(UnitMath.compatible('g', 'kg'), isTrue);
    expect(UnitMath.compatible('g', 'ml'), isFalse);
  });

  test('meal requirements respect adult and child portions', () {
    const recipe = Recipe(
      id: 'T1',
      name: 'Test',
      category: 'Obed',
      mealUse: 'obed',
      allergens: '',
      step: '',
      note: '',
      isCustom: false,
      ingredients: [
        RecipeIngredient(
            ingredient: 'Ryža', unit: 'g', adultQty: 100, childQty: 60)
      ],
    );
    const servings = [
      MealServing(
          memberId: 1, name: 'A', role: 'adult', portion: 1, eating: true),
      MealServing(
          memberId: 2, name: 'B', role: 'child', portion: 0.5, eating: true),
    ];
    final needs = MealMath.requirements(recipe, servings);
    expect(needs.single.qty, 130);
    expect(needs.single.unit, 'g');
  });

  test('shopping subtracts real pantry and rounds to whole packages', () {
    const recipe = Recipe(
      id: 'T2',
      name: 'Ryža',
      category: 'Obed',
      mealUse: 'obed',
      allergens: '',
      step: '',
      note: '',
      isCustom: false,
      ingredients: [
        RecipeIngredient(
            ingredient: 'Ryža', unit: 'g', adultQty: 730, childQty: 500)
      ],
    );
    final meal = MealEntry(
      id: 1,
      date: DateTime(2026, 9, 29),
      mealType: 'lunch',
      status: 'planned',
      snapshot: recipe,
      servings: const [
        MealServing(
            memberId: 1, name: 'A', role: 'adult', portion: 1, eating: true)
      ],
    );
    const def = IngredientDefinition(
      name: 'Ryža',
      unit: 'g',
      category: 'Trvanlivé',
      pack: 500,
      packPrice: 2,
      kcal: 3.5,
      allergens: '',
      buy: true,
    );
    final result = ShoppingCalculator.calculate(
      meals: [meal],
      definitions: const [def],
      pantry: const [
        PantryItem(id: 1, ingredientName: 'Ryža', qty: 200, unit: 'g')
      ],
      checks: const {},
      usePantry: true,
    );
    expect(result.single.neededQty, 530);
    expect(result.single.packages, 2);
    expect(result.single.purchaseQty, 1000);
    expect(result.single.estimatedCost, 4);
  });

  test('shopping ignores pantry when setting is disabled', () {
    const recipe = Recipe(
      id: 'T3',
      name: 'Ryža',
      category: 'Obed',
      mealUse: 'obed',
      allergens: '',
      step: '',
      note: '',
      isCustom: false,
      ingredients: [
        RecipeIngredient(
            ingredient: 'Ryža', unit: 'g', adultQty: 500, childQty: 300)
      ],
    );
    final meal = MealEntry(
      id: 1,
      date: DateTime(2026, 9, 29),
      mealType: 'lunch',
      status: 'planned',
      snapshot: recipe,
      servings: const [
        MealServing(
            memberId: 1, name: 'A', role: 'adult', portion: 1, eating: true)
      ],
    );
    const def = IngredientDefinition(
        name: 'Ryža',
        unit: 'g',
        category: 'Trvanlivé',
        pack: 500,
        packPrice: 2,
        kcal: 3.5,
        allergens: '',
        buy: true);
    final result = ShoppingCalculator.calculate(
      meals: [meal],
      definitions: const [def],
      pantry: const [
        PantryItem(id: 1, ingredientName: 'Ryža', qty: 500, unit: 'g')
      ],
      checks: const {},
      usePantry: false,
    );
    expect(result.single.neededQty, 500);
  });

  test('shopping does not use pantry after its expiry date', () {
    const recipe = Recipe(
      id: 'T4',
      name: 'Ryža neskôr',
      category: 'Obed',
      mealUse: 'obed',
      allergens: '',
      step: '',
      note: '',
      isCustom: false,
      ingredients: [
        RecipeIngredient(
            ingredient: 'Ryža', unit: 'g', adultQty: 300, childQty: 200)
      ],
    );
    final meal = MealEntry(
      id: 1,
      date: DateTime(2026, 10, 10),
      mealType: 'lunch',
      status: 'planned',
      snapshot: recipe,
      servings: const [
        MealServing(
            memberId: 1, name: 'A', role: 'adult', portion: 1, eating: true)
      ],
    );
    const def = IngredientDefinition(
        name: 'Ryža',
        unit: 'g',
        category: 'Trvanlivé',
        pack: 500,
        packPrice: 2,
        kcal: 3.5,
        allergens: '',
        buy: true);
    final result = ShoppingCalculator.calculate(
      meals: [meal],
      definitions: const [def],
      pantry: [
        PantryItem(
            id: 1,
            ingredientName: 'Ryža',
            qty: 500,
            unit: 'g',
            expiry: DateTime(2026, 10, 5))
      ],
      checks: const {},
      usePantry: true,
    );
    expect(result.single.neededQty, 300);
  });

  test('shopping consumes the same pantry lot only once across meals', () {
    const recipe = Recipe(
      id: 'T5',
      name: 'Ryža dvakrát',
      category: 'Obed',
      mealUse: 'obed',
      allergens: '',
      step: '',
      note: '',
      isCustom: false,
      ingredients: [
        RecipeIngredient(
            ingredient: 'Ryža', unit: 'g', adultQty: 300, childQty: 200)
      ],
    );
    final meals = [
      MealEntry(
          id: 1,
          date: DateTime(2026, 10, 5),
          mealType: 'lunch',
          status: 'planned',
          snapshot: recipe,
          servings: const [
            MealServing(
                memberId: 1, name: 'A', role: 'adult', portion: 1, eating: true)
          ]),
      MealEntry(
          id: 2,
          date: DateTime(2026, 10, 6),
          mealType: 'lunch',
          status: 'planned',
          snapshot: recipe,
          servings: const [
            MealServing(
                memberId: 1, name: 'A', role: 'adult', portion: 1, eating: true)
          ]),
    ];
    const def = IngredientDefinition(
        name: 'Ryža',
        unit: 'g',
        category: 'Trvanlivé',
        pack: 500,
        packPrice: 2,
        kcal: 3.5,
        allergens: '',
        buy: true);
    final result = ShoppingCalculator.calculate(
      meals: meals,
      definitions: const [def],
      pantry: const [
        PantryItem(id: 1, ingredientName: 'Ryža', qty: 400, unit: 'g')
      ],
      checks: const {},
      usePantry: true,
    );
    expect(result.single.neededQty, 200);
    expect(result.single.packages, 1);
  });

  test('week balance summary reports targets consistently', () {
    const summary = WeekBalanceSummary(
      fishMains: 1,
      vegetarianMains: 2,
      legumeMains: 1,
      sweetMains: 1,
      fruitSnackDays: 5,
      vegetableMainDays: 5,
      uniqueMainRatio: 0.9,
      targetFishMains: 1,
      targetVegetarianMains: 2,
      targetLegumeMains: 1,
      maxSweetMains: 1,
      targetFruitDays: 5,
      targetVegetableDays: 5,
    );
    expect(summary.looksBalanced, isTrue);
    expect(summary.targetsMet, summary.targetCount);
  });
}
