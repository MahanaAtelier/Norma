class ShoppingItem {
  const ShoppingItem({
    required this.ingredient,
    required this.category,
    required this.unit,
    required this.neededQty,
    required this.pantryUsed,
    required this.purchaseQty,
    required this.packages,
    this.estimatedCost,
    required this.checked,
    this.manual = false,
    this.manualId,
  });

  final String ingredient;
  final String category;
  final String unit;
  final double neededQty;
  final double pantryUsed;
  final double purchaseQty;
  final int packages;
  final double? estimatedCost;
  final bool checked;
  final bool manual;
  final int? manualId;

  ShoppingItem copyWith({bool? checked}) => ShoppingItem(
        ingredient: ingredient,
        category: category,
        unit: unit,
        neededQty: neededQty,
        pantryUsed: pantryUsed,
        purchaseQty: purchaseQty,
        packages: packages,
        estimatedCost: estimatedCost,
        checked: checked ?? this.checked,
        manual: manual,
        manualId: manualId,
      );
}
