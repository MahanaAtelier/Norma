import 'dart:convert';

class IngredientDefinition {
  const IngredientDefinition({
    required this.name,
    required this.unit,
    required this.category,
    this.pack,
    this.packPrice,
    this.kcal,
    required this.allergens,
    required this.buy,
    this.tags = const [],
  });

  final String name;
  final String unit;
  final String category;
  final double? pack;
  final double? packPrice;
  final double? kcal;
  final String allergens;
  final bool buy;
  final List<String> tags;

  factory IngredientDefinition.fromMap(Map<String, Object?> map) =>
      IngredientDefinition(
        name: map['name'] as String,
        unit: (map['unit'] as String?) ?? 'g',
        category: (map['category'] as String?) ?? 'Ostatné',
        pack: (map['pack'] as num?)?.toDouble(),
        packPrice: (map['pack_price'] as num?)?.toDouble(),
        kcal: (map['kcal'] as num?)?.toDouble(),
        allergens: (map['allergens'] as String?) ?? '',
        buy: ((map['buy'] as int?) ?? 1) == 1,
        tags: _decodeList(map['tags_json'] as String?),
      );

  static List<String> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List<dynamic>)
          .map((e) => e.toString())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
