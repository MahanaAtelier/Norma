import 'recipe.dart';

class Leftover {
  const Leftover({
    required this.id,
    this.sourceMealId,
    this.recipeId,
    required this.recipeName,
    required this.portions,
    required this.createdAt,
    this.useBy,
    required this.status,
    this.snapshot,
  });

  final int id;
  final int? sourceMealId;
  final String? recipeId;
  final String recipeName;
  final double portions;
  final DateTime createdAt;
  final DateTime? useBy;
  final String status;
  final Recipe? snapshot;

  bool get isAvailable => status == 'available';
  bool get isReserved => status == 'reserved';

  factory Leftover.fromMap(Map<String, Object?> map) => Leftover(
        id: map['id'] as int,
        sourceMealId: (map['source_meal_id'] as num?)?.toInt(),
        recipeId: map['recipe_id'] as String?,
        recipeName: map['recipe_name'] as String,
        portions: (map['portions'] as num).toDouble(),
        createdAt: DateTime.parse(map['created_at'] as String),
        useBy: map['use_by'] == null
            ? null
            : DateTime.tryParse(map['use_by'] as String),
        status: (map['status'] as String?) ?? 'available',
        snapshot: Recipe.fromSnapshot(map['snapshot_json'] as String?),
      );
}
