import 'recipe.dart';

class PlanningPreferences {
  const PlanningPreferences({
    this.fishPerWeek = 1,
    this.vegetarianMainsPerWeek = 2,
    this.legumeMainsPerWeek = 1,
    this.maxSweetMainsPerWeek = 1,
    this.minFruitDaysPerWeek = 5,
    this.minVegetableMainDaysPerWeek = 5,
    this.maxSameProteinStreak = 2,
    this.avoidRepeatDays = 21,
    this.preferQuickWeekdays = true,
  });

  final int fishPerWeek;
  final int vegetarianMainsPerWeek;
  final int legumeMainsPerWeek;
  final int maxSweetMainsPerWeek;
  final int minFruitDaysPerWeek;
  final int minVegetableMainDaysPerWeek;
  final int maxSameProteinStreak;
  final int avoidRepeatDays;
  final bool preferQuickWeekdays;

  PlanningPreferences copyWith({
    int? fishPerWeek,
    int? vegetarianMainsPerWeek,
    int? legumeMainsPerWeek,
    int? maxSweetMainsPerWeek,
    int? minFruitDaysPerWeek,
    int? minVegetableMainDaysPerWeek,
    int? maxSameProteinStreak,
    int? avoidRepeatDays,
    bool? preferQuickWeekdays,
  }) =>
      PlanningPreferences(
        fishPerWeek: fishPerWeek ?? this.fishPerWeek,
        vegetarianMainsPerWeek:
            vegetarianMainsPerWeek ?? this.vegetarianMainsPerWeek,
        legumeMainsPerWeek: legumeMainsPerWeek ?? this.legumeMainsPerWeek,
        maxSweetMainsPerWeek: maxSweetMainsPerWeek ?? this.maxSweetMainsPerWeek,
        minFruitDaysPerWeek: minFruitDaysPerWeek ?? this.minFruitDaysPerWeek,
        minVegetableMainDaysPerWeek:
            minVegetableMainDaysPerWeek ?? this.minVegetableMainDaysPerWeek,
        maxSameProteinStreak: maxSameProteinStreak ?? this.maxSameProteinStreak,
        avoidRepeatDays: avoidRepeatDays ?? this.avoidRepeatDays,
        preferQuickWeekdays: preferQuickWeekdays ?? this.preferQuickWeekdays,
      );
}

class RecipePreference {
  const RecipePreference(
      {required this.favorite, required this.blocked, this.cooldownUntil});
  final bool favorite;
  final bool blocked;
  final DateTime? cooldownUntil;
}

class PlannerRecommendation {
  const PlannerRecommendation(
      {required this.recipe, required this.score, required this.reasons});
  final Recipe recipe;
  final double score;
  final List<String> reasons;
}

class WeekBalanceSummary {
  const WeekBalanceSummary({
    required this.fishMains,
    required this.vegetarianMains,
    required this.legumeMains,
    required this.sweetMains,
    required this.fruitSnackDays,
    required this.vegetableMainDays,
    required this.uniqueMainRatio,
    required this.targetFishMains,
    required this.targetVegetarianMains,
    required this.targetLegumeMains,
    required this.maxSweetMains,
    required this.targetFruitDays,
    required this.targetVegetableDays,
  });

  final int fishMains;
  final int vegetarianMains;
  final int legumeMains;
  final int sweetMains;
  final int fruitSnackDays;
  final int vegetableMainDays;
  final double uniqueMainRatio;

  final int targetFishMains;
  final int targetVegetarianMains;
  final int targetLegumeMains;
  final int maxSweetMains;
  final int targetFruitDays;
  final int targetVegetableDays;

  bool get fishOnTarget => fishMains >= targetFishMains;
  bool get vegetarianOnTarget => vegetarianMains >= targetVegetarianMains;
  bool get legumesOnTarget => legumeMains >= targetLegumeMains;
  bool get sweetOnTarget => sweetMains <= maxSweetMains;
  bool get fruitOnTarget => fruitSnackDays >= targetFruitDays;
  bool get vegetablesOnTarget => vegetableMainDays >= targetVegetableDays;
  bool get varietyOnTarget => uniqueMainRatio >= 0.75;

  int get targetsMet => [
        fishOnTarget,
        vegetarianOnTarget,
        legumesOnTarget,
        sweetOnTarget,
        fruitOnTarget,
        vegetablesOnTarget,
        varietyOnTarget,
      ].where((value) => value).length;

  int get targetCount => 7;
  bool get looksBalanced => targetsMet >= 6;
}

class CompletionPreview {
  const CompletionPreview({required this.shortages});
  final Map<String, double> shortages;
  bool get hasShortages => shortages.values.any((v) => v > 0.0001);
}
