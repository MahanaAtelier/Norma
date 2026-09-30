import 'dart:convert';

class RecipeIngredient {
  const RecipeIngredient({
    required this.ingredient,
    required this.unit,
    required this.adultQty,
    required this.childQty,
  });

  final String ingredient;
  final String unit;
  final double adultQty;
  final double childQty;

  Map<String, dynamic> toJson() => {
        'ingredient': ingredient,
        'unit': unit,
        'adult_qty': adultQty,
        'child_qty': childQty,
      };

  factory RecipeIngredient.fromJson(Map<String, dynamic> map) =>
      RecipeIngredient(
        ingredient: (map['ingredient'] ?? '').toString(),
        unit: (map['unit'] ?? 'g').toString(),
        adultQty: (map['adult_qty'] as num?)?.toDouble() ?? 0,
        childQty: (map['child_qty'] as num?)?.toDouble() ?? 0,
      );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.mealUse,
    this.adultKcal,
    this.childKcal,
    required this.allergens,
    required this.step,
    required this.note,
    this.prepMin,
    required this.isCustom,
    required this.ingredients,
    this.tags = const [],
    this.sourceBasis = '',
    this.sourceUrl = '',
  });

  final String id;
  final String name;
  final String category;
  final String mealUse;
  final double? adultKcal;
  final double? childKcal;
  final String allergens;
  final String step;
  final String note;
  final int? prepMin;
  final bool isCustom;
  final List<RecipeIngredient> ingredients;
  final List<String> tags;
  final String sourceBasis;
  final String sourceUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'meal_use': mealUse,
        'adult_kcal': adultKcal,
        'child_kcal': childKcal,
        'allergens': allergens,
        'step': step,
        'note': note,
        'prep_min': prepMin,
        'is_custom': isCustom,
        'ingredients':
            ingredients.map((e) => e.toJson()).toList(growable: false),
        'tags': tags,
        'source_basis': sourceBasis,
        'source_url': sourceUrl,
      };

  String toSnapshotJson() => jsonEncode(toJson());

  factory Recipe.fromJson(Map<String, dynamic> map) => Recipe(
        id: (map['id'] ?? '').toString(),
        name: (map['name'] ?? '').toString(),
        category: (map['category'] ?? 'Ostatné').toString(),
        mealUse: (map['meal_use'] ?? '').toString(),
        adultKcal: (map['adult_kcal'] as num?)?.toDouble(),
        childKcal: (map['child_kcal'] as num?)?.toDouble(),
        allergens: (map['allergens'] ?? '').toString(),
        step: (map['step'] ?? '').toString(),
        note: (map['note'] ?? '').toString(),
        prepMin: (map['prep_min'] as num?)?.toInt(),
        isCustom: map['is_custom'] == true || map['is_custom'] == 1,
        ingredients: ((map['ingredients'] as List<dynamic>?) ?? const [])
            .map((e) =>
                RecipeIngredient.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(growable: false),
        tags: ((map['tags'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toList(growable: false),
        sourceBasis: (map['source_basis'] ?? '').toString(),
        sourceUrl: (map['source_url'] ?? '').toString(),
      );

  static Recipe? fromSnapshot(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return Recipe.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return null;
    }
  }

  Recipe copyWith({
    String? id,
    String? name,
    String? category,
    String? mealUse,
    double? adultKcal,
    double? childKcal,
    String? allergens,
    String? step,
    String? note,
    int? prepMin,
    bool? isCustom,
    List<RecipeIngredient>? ingredients,
    List<String>? tags,
    String? sourceBasis,
    String? sourceUrl,
  }) =>
      Recipe(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        mealUse: mealUse ?? this.mealUse,
        adultKcal: adultKcal ?? this.adultKcal,
        childKcal: childKcal ?? this.childKcal,
        allergens: allergens ?? this.allergens,
        step: step ?? this.step,
        note: note ?? this.note,
        prepMin: prepMin ?? this.prepMin,
        isCustom: isCustom ?? this.isCustom,
        ingredients: ingredients ?? this.ingredients,
        tags: tags ?? this.tags,
        sourceBasis: sourceBasis ?? this.sourceBasis,
        sourceUrl: sourceUrl ?? this.sourceUrl,
      );
}
