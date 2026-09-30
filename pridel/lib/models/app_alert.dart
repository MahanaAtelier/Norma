class AppAlert {
  const AppAlert(
      {required this.key,
      required this.title,
      required this.body,
      required this.kind,
      this.actionLabel,
      this.actionTarget});
  final String key;
  final String title;
  final String body;
  final String kind;
  final String? actionLabel;
  final String? actionTarget;
}

class DashboardStats {
  const DashboardStats(
      {required this.doneMealsThisMonth,
      required this.availableLeftovers,
      required this.discardedLeftoversThisMonth,
      required this.pantryItems,
      required this.expiringItems});
  final int doneMealsThisMonth;
  final int availableLeftovers;
  final int discardedLeftoversThisMonth;
  final int pantryItems;
  final int expiringItems;
}

class StorageSummary {
  const StorageSummary(
      {required this.databaseBytes,
      required this.recipeCount,
      required this.pantryCount,
      required this.historyCount});
  final int databaseBytes;
  final int recipeCount;
  final int pantryCount;
  final int historyCount;
}
