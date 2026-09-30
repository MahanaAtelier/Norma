class PantryItem {
  const PantryItem(
      {required this.id,
      required this.ingredientName,
      required this.qty,
      required this.unit,
      this.location = 'pantry',
      this.expiry,
      this.addedAt});
  final int id;
  final String ingredientName;
  final double qty;
  final String unit;
  final String location;
  final DateTime? expiry;
  final DateTime? addedAt;

  PantryItem copyWith({double? qty, DateTime? expiry, String? location}) =>
      PantryItem(
        id: id,
        ingredientName: ingredientName,
        qty: qty ?? this.qty,
        unit: unit,
        location: location ?? this.location,
        expiry: expiry ?? this.expiry,
        addedAt: addedAt,
      );

  factory PantryItem.fromMap(Map<String, Object?> map) => PantryItem(
        id: map['id'] as int,
        ingredientName: map['ingredient_name'] as String,
        qty: (map['qty'] as num).toDouble(),
        unit: (map['unit'] as String?) ?? 'g',
        location: (map['location'] as String?) ?? 'pantry',
        expiry: map['expiry'] == null
            ? null
            : DateTime.tryParse(map['expiry'].toString()),
        addedAt: map['added_at'] == null
            ? null
            : DateTime.tryParse(map['added_at'].toString()),
      );
}
