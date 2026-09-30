import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/app_alert.dart';
import '../models/ingredient.dart';
import '../models/leftover.dart';
import '../models/meal_entry.dart';
import '../models/pantry_item.dart';
import '../models/shopping_item.dart';
import '../services/planner_service.dart';
import '../services/shopping_calculator.dart';
import '../theme/app_theme.dart';
import '../utils/date_utils.dart';
import '../utils/meal_types.dart';
import '../widgets/page_header.dart';
import 'history_screen.dart';
import 'settings_screen.dart';

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen(
      {super.key, required this.controller, required this.onNavigate});
  final AppController controller;
  final void Function(int index, {bool pantryOnly}) onNavigate;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  List<MealEntry> todayMeals = const [];
  List<PantryItem> expiring = const [];
  List<Leftover> leftovers = const [];
  List<ShoppingItem> shopping = const [];
  DashboardStats? stats;
  Set<String> dismissed = const {};
  bool alertsEnabled = true;
  bool loading = true;
  int _token = 0;
  String? _bannerShownKey;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_change);
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_change);
    super.dispose();
  }

  void _change() => _load();

  Future<void> _load() async {
    final token = ++_token;
    final now = DateTime.now();
    final weekStart = PridelDates.startOfWeek(now);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final results = await Future.wait([
      widget.controller.database.getMealsForDay(now),
      widget.controller.database.getExpiringPantry(withinDays: 3),
      widget.controller.database.getLeftovers(status: 'available'),
      widget.controller.database.getDashboardStats(),
      widget.controller.database.getDismissedAlertKeys(),
      widget.controller.database.getInAppAlertsEnabled(),
      widget.controller.database.getMealEntries(weekStart, weekEnd),
      widget.controller.database.getIngredients(),
      widget.controller.database.getPantry(),
      widget.controller.database.getUsePantry(),
      widget.controller.database
          .getShoppingCheckRows(PridelDates.weekKey(weekStart)),
    ]);
    final raw = ShoppingCalculator.calculate(
      meals: results[6] as List<MealEntry>,
      definitions: results[7] as List<IngredientDefinition>,
      pantry: results[8] as List<PantryItem>,
      checks: const {},
      usePantry: results[9] as bool,
    );
    final checkedRows = {
      for (final row in results[10] as List<Map<String, Object?>>)
        row['ingredient_name'].toString(): (row['checked'] as int? ?? 0) == 1
    };
    final shop = raw
        .map((e) => e.copyWith(checked: checkedRows[e.ingredient] == true))
        .toList(growable: false);
    if (!mounted || token != _token) return;
    setState(() {
      todayMeals = results[0] as List<MealEntry>;
      expiring = results[1] as List<PantryItem>;
      leftovers = results[2] as List<Leftover>;
      stats = results[3] as DashboardStats;
      dismissed = results[4] as Set<String>;
      alertsEnabled = results[5] as bool;
      shopping = shop;
      loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showPriorityBanner());
  }

  void _showPriorityBanner() {
    if (!mounted) return;
    final list = _alerts();
    if (list.isEmpty) return;
    final alert = list.first;
    if (_bannerShownKey == alert.key) return;
    _bannerShownKey = alert.key;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentMaterialBanner();
    messenger.showMaterialBanner(MaterialBanner(
      leading: const Icon(Icons.notifications_active_outlined),
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        Text(alert.body),
      ]),
      actions: [
        if (alert.actionLabel != null)
          TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                _runAlertAction(alert);
              },
              child: Text(alert.actionLabel!)),
        TextButton(
            onPressed: () async {
              messenger.hideCurrentMaterialBanner();
              await _dismiss(alert);
            },
            child: const Text('Potvrdiť')),
      ],
    ));
  }

  void _runAlertAction(AppAlert alert) {
    if (alert.actionTarget == 'pantryRecipes')
      widget.onNavigate(2, pantryOnly: true);
    if (alert.actionTarget == 'plan') widget.onNavigate(1);
  }

  List<AppAlert> _alerts() {
    if (!alertsEnabled) return const [];
    final out = <AppAlert>[];
    for (final item in expiring.take(4)) {
      final key = 'expiry:${item.id}:${item.expiry?.toIso8601String() ?? ''}';
      if (dismissed.contains(key)) continue;
      out.add(AppAlert(
        key: key,
        kind: 'expiry',
        title: '${item.ingredientName} treba minúť',
        body: item.expiry == null
            ? 'Skontroluj zásobu.'
            : 'Spotrebovať do ${PridelDates.compactDay(item.expiry!)}.',
        actionLabel: 'Recepty',
        actionTarget: 'pantryRecipes',
      ));
    }
    final today = PridelDates.dateOnly(DateTime.now());
    for (final leftover in leftovers.take(3)) {
      if (leftover.useBy == null ||
          PridelDates.daysBetween(today, leftover.useBy!) > 1) continue;
      final key =
          'leftover:${leftover.id}:${leftover.useBy?.toIso8601String() ?? ''}';
      if (dismissed.contains(key)) continue;
      out.add(AppAlert(
          key: key,
          kind: 'leftover',
          title: 'Zvyšok: ${leftover.recipeName}',
          body:
              'Má ${leftover.portions.toStringAsFixed(leftover.portions % 1 == 0 ? 0 : 1)} porcie a treba ho čoskoro použiť.',
          actionLabel: 'Plán',
          actionTarget: 'plan'));
    }
    if (todayMeals.isEmpty) {
      final key = 'no-plan:${PridelDates.iso(today)}';
      if (!dismissed.contains(key))
        out.add(AppAlert(
            key: key,
            kind: 'plan',
            title: 'Dnes ešte nemáš plán',
            body: 'Môžeš vytvoriť alebo doplniť jedálniček.',
            actionLabel: 'Otvoriť plán',
            actionTarget: 'plan'));
    }
    return out;
  }

  Future<void> _dismiss(AppAlert alert) async {
    await widget.controller.database.dismissAlert(alert.key);
    HapticFeedback.selectionClick();
    await _load();
  }

  Future<void> _generateWeek() async {
    try {
      final horizon = await widget.controller.database.getPlanHorizonDays();
      final planner = PlannerService(widget.controller.database);
      final start = PridelDates.startOfWeek(DateTime.now());
      for (int i = 0; i < (horizon / 7).ceil(); i++) {
        await planner.generateWeek(start.add(Duration(days: i * 7)),
            onlyEmpty: true);
      }
      HapticFeedback.mediumImpact();
      widget.controller.dataChanged({AppArea.plan, AppArea.shopping});
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Plán je doplnený na $horizon dní.')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _alerts();
    final next = todayMeals.where((e) => !e.isDone).firstOrNull;
    final unchecked =
        shopping.where((e) => !e.checked && e.purchaseQty > 0).length;
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      children: [
        PageHeader(
          title: 'Dnes',
          subtitle: PridelDates.dayLabel(DateTime.now()),
          trailing: IconButton.filledTonal(
            tooltip: 'Nastavenia',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SettingsScreen(controller: widget.controller))),
          ),
        ),
        if (loading)
          const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()))
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Najbližšie',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(
                          next?.snapshot?.name ??
                              (todayMeals.isEmpty
                                  ? 'Dnes ešte nič nie je naplánované'
                                  : 'Všetko na dnes je hotové'),
                          style: Theme.of(context).textTheme.titleLarge),
                      if (next != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text(MealTypes.label(next.mealType))),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.icon(
                            onPressed: () => widget.onNavigate(1),
                            icon: const Icon(Icons.calendar_month),
                            label: const Text('Jedálniček')),
                        OutlinedButton.icon(
                            onPressed: _generateWeek,
                            icon: const Icon(Icons.auto_awesome),
                            label: const Text('Doplniť plán')),
                      ]),
                    ]),
              ),
            ),
          ),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 18),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Upozornenia',
                    style: Theme.of(context).textTheme.titleMedium)),
            const SizedBox(height: 8),
            ...alerts.map((alert) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Card(
                    child: ListTile(
                      leading: CircleAvatar(
                          backgroundColor: AppTheme.soft,
                          child: Icon(alert.kind == 'expiry'
                              ? Icons.schedule
                              : alert.kind == 'leftover'
                                  ? Icons.takeout_dining
                                  : Icons.calendar_today)),
                      title: Text(alert.title),
                      subtitle: Text(alert.body),
                      trailing: IconButton(
                          tooltip: 'Potvrdiť a skryť',
                          onPressed: () => _dismiss(alert),
                          icon: const Icon(Icons.check)),
                      onTap: () => _runAlertAction(alert),
                    ),
                  ),
                )),
          ],
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _quick(
                    context,
                    Icons.kitchen_outlined,
                    'Čo mám doma',
                    '${stats?.pantryItems ?? 0} položiek',
                    () => widget.onNavigate(3)),
                _quick(
                    context,
                    Icons.restaurant_menu,
                    'Uvariť zo zásob',
                    'nájsť recept',
                    () => widget.onNavigate(2, pantryOnly: true)),
                _quick(context, Icons.shopping_bag_outlined, 'Nákup',
                    '$unchecked chýba', () => widget.onNavigate(4)),
                _quick(
                    context,
                    Icons.history,
                    'História',
                    '${stats?.doneMealsThisMonth ?? 0} hotových tento mesiac',
                    () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) =>
                            HistoryScreen(controller: widget.controller)))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                      child: _metric(context,
                          '${stats?.doneMealsThisMonth ?? 0}', 'uvarených')),
                  Expanded(
                      child: _metric(context,
                          '${stats?.availableLeftovers ?? 0}', 'zvyškov')),
                  Expanded(
                      child: _metric(context, '${stats?.expiringItems ?? 0}',
                          'čoskoro minúť')),
                ]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _quick(BuildContext context, IconData icon, String title,
          String subtitle, VoidCallback onTap) =>
      SizedBox(
        width: MediaQuery.of(context).size.width >= 700
            ? 210
            : (MediaQuery.of(context).size.width - 50) / 2,
        child: Card(
            child: InkWell(
                onTap: onTap,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon),
                          const SizedBox(height: 18),
                          Text(title,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 2),
                          Text(subtitle,
                              style: Theme.of(context).textTheme.bodySmall)
                        ])))),
      );

  Widget _metric(BuildContext context, String value, String label) =>
      Column(children: [
        Text(value, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 2),
        Text(label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center)
      ]);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
