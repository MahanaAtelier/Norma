import 'dart:convert';

import 'recipe.dart';

class MealServing {
  const MealServing({
    required this.memberId,
    required this.name,
    required this.role,
    required this.portion,
    required this.eating,
  });

  final int memberId;
  final String name;
  final String role;
  final double portion;
  final bool eating;

  bool get isChild => role == 'child';

  Map<String, dynamic> toJson() => {
        'member_id': memberId,
        'name': name,
        'role': role,
        'portion': portion,
        'eating': eating,
      };

  factory MealServing.fromJson(Map<String, dynamic> map) => MealServing(
        memberId: (map['member_id'] as num?)?.toInt() ?? 0,
        name: (map['name'] ?? '').toString(),
        role: (map['role'] ?? 'adult').toString(),
        portion: (map['portion'] as num?)?.toDouble() ?? 1,
        eating: map['eating'] != false,
      );
}

class PantryDeduction {
  const PantryDeduction({
    required this.pantryId,
    required this.ingredient,
    required this.qty,
    required this.unit,
    this.expiry,
    this.addedAt,
  });

  final int pantryId;
  final String ingredient;
  final double qty;
  final String unit;
  final String? expiry;
  final String? addedAt;

  Map<String, dynamic> toJson() => {
        'pantry_id': pantryId,
        'ingredient': ingredient,
        'qty': qty,
        'unit': unit,
        'expiry': expiry,
        'added_at': addedAt,
      };

  factory PantryDeduction.fromJson(Map<String, dynamic> map) => PantryDeduction(
        pantryId: (map['pantry_id'] as num?)?.toInt() ?? 0,
        ingredient: (map['ingredient'] ?? '').toString(),
        qty: (map['qty'] as num?)?.toDouble() ?? 0,
        unit: (map['unit'] ?? 'g').toString(),
        expiry: map['expiry']?.toString(),
        addedAt: map['added_at']?.toString(),
      );
}

class MealEntry {
  const MealEntry({
    required this.id,
    required this.date,
    required this.mealType,
    this.recipeId,
    required this.status,
    this.snapshot,
    this.servings = const [],
    this.consumption = const [],
    this.leftoverId,
  });

  final int id;
  final DateTime date;
  final String mealType;
  final String? recipeId;
  final String status;
  final Recipe? snapshot;
  final List<MealServing> servings;
  final List<PantryDeduction> consumption;
  final int? leftoverId;

  bool get isDone => status == 'done';
  bool get isLeftover => leftoverId != null;

  factory MealEntry.fromMap(Map<String, Object?> map) {
    List<MealServing> servings = const [];
    List<PantryDeduction> consumption = const [];
    try {
      servings = ((jsonDecode((map['servings_json'] as String?) ?? '[]')
              as List<dynamic>))
          .map((e) => MealServing.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {}
    try {
      consumption = ((jsonDecode((map['consumption_json'] as String?) ?? '[]')
              as List<dynamic>))
          .map((e) =>
              PantryDeduction.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
    } catch (_) {}
    return MealEntry(
      id: map['id'] as int,
      date: DateTime.parse(map['date'] as String),
      mealType: map['meal_type'] as String,
      recipeId: map['recipe_id'] as String?,
      status: (map['status'] as String?) ?? 'planned',
      snapshot: Recipe.fromSnapshot(map['snapshot_json'] as String?),
      servings: servings,
      consumption: consumption,
      leftoverId: (map['leftover_id'] as num?)?.toInt(),
    );
  }
}
