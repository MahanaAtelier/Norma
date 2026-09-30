import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/app_controller.dart';
import '../models/ingredient.dart';
import '../models/meal_entry.dart';
import '../models/pantry_item.dart';
import '../models/shopping_item.dart';
import '../services/shopping_calculator.dart';
import '../utils/date_utils.dart';
import '../utils/unit_math.dart';
import '../widgets/empty_state.dart';
import '../widgets/page_header.dart';

class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key, required this.controller});
  final AppController controller;

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  late DateTime weekStart;
  List<ShoppingItem> items = const [];
  List<Map<String, Object?>> manual = const [];
  bool usePantry = true;
  bool loading = true;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    weekStart = PridelDates.startOfWeek(DateTime.now());
    widget.controller.addListener(_externalChange);
    _reload();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_externalChange);
    super.dispose();
  }

  void _externalChange() {
    if (widget.controller.affects(AppArea.shopping)) _reload();
  }

  Future<void> _reload() async {
    final token = ++_loadToken;
    final end = weekStart.add(const Duration(days: 6));
    final weekKey = PridelDates.weekKey(weekStart);
    final results = await Future.wait([
      widget.controller.database.getMealEntries(weekStart, end),
      widget.controller.database.getIngredients(),
      widget.controller.database.getPantry(),
      widget.controller.database.getShoppingCheckRows(weekKey),
      widget.controller.database.getUsePantry(),
      widget.controller.database.getManualShopping(weekKey),
    ]);
    final rawCalculated = ShoppingCalculator.calculate(
      meals: results[0] as List<MealEntry>,
      definitions: results[1] as List<IngredientDefinition>,
      pantry: results[2] as List<PantryItem>,
      checks: const {},
      usePantry: results[4] as bool,
    );
    final checkRows = results[3] as List<Map<String, Object?>>;
    final storedChecks = {
      for (final row in checkRows) row['ingredient_name'] as String: row
    };
    final calculated = rawCalculated.map((item) {
      final row = storedChecks[item.ingredient];
      if (row == null || (row['checked'] as int? ?? 0) != 1) return item;
      final storedQty = (row['qty'] as num?)?.toDouble() ?? 0;
      final storedUnit = (row['unit'] as String?) ?? '';
      final enough = storedUnit.isNotEmpty &&
          UnitMath.compatible(storedUnit, item.unit) &&
          UnitMath.convert(storedQty, storedUnit, item.unit) + 0.0001 >=
              item.purchaseQty;
      return enough ? item.copyWith(checked: true) : item;
    }).toList(growable: false);
    if (!mounted || token != _loadToken) return;
    setState(() {
      items = calculated;
      usePantry = results[4] as bool;
      manual = (results[5] as List<Map<String, Object?>>);
      loading = false;
    });
  }

  void _moveWeek(int delta) {
    setState(() {
      weekStart = weekStart.add(Duration(days: delta * 7));
      loading = true;
    });
    _reload();
  }

  Future<void> _toggle(ShoppingItem item, bool checked) async {
    await widget.controller.database.setShoppingChecked(
        PridelDates.weekKey(weekStart), item.ingredient, checked,
        qty: item.purchaseQty, unit: item.unit);
    HapticFeedback.selectionClick();
    await _reload();
  }

  Future<void> _addManual() async {
    final name = TextEditingController();
    final qty = TextEditingController(text: '1');
    final unit = TextEditingController(text: 'ks');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pridať do nákupu',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 14),
            TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Položka')),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: qty,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Množstvo'))),
              const SizedBox(width: 8),
              SizedBox(
                  width: 90,
                  child: TextField(
                      controller: unit,
                      decoration: const InputDecoration(labelText: 'Jedn.'))),
            ]),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Pridať')),
          ],
        ),
      ),
    );
    if (ok == true) {
      try {
        await widget.controller.database.addManualShopping(
          PridelDates.weekKey(weekStart),
          name: name.text,
          qty: double.tryParse(qty.text.replaceAll(',', '.')) ?? 1,
          unit: unit.text,
        );
        await _reload();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
    name.dispose();
    qty.dispose();
    unit.dispose();
  }

  Future<void> _addCheckedToPantry() async {
    final checked = items
        .where((e) => e.checked && e.purchaseQty > 0)
        .toList(growable: false);
    if (checked.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Najprv označ kúpené potraviny fajkou.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pridať kúpené do skladu?'),
        content: Text(
            'Do skladu sa pridá ${checked.length} položiek v množstve kúpených balení. Spotreba sa odpočíta až po označení jedla ako Hotovo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Zrušiť')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pridať')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.controller.database.addPurchasedItemsToPantry([
        for (final item in checked)
          (name: item.ingredient, qty: item.purchaseQty, unit: item.unit),
      ]);
      for (final item in checked) {
        await widget.controller.database.setShoppingChecked(
            PridelDates.weekKey(weekStart), item.ingredient, false);
      }
      widget.controller.dataChanged({AppArea.shopping, AppArea.pantry});
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _editPrice(ShoppingItem item) async {
    final def = await widget.controller.database.getIngredient(item.ingredient);
    if (def == null || !mounted) return;
    final pack = TextEditingController(text: def.pack?.toString() ?? '');
    final price =
        TextEditingController(text: def.packPrice?.toStringAsFixed(2) ?? '');
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Cena: ${item.ingredient}',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(
                'Ide o tvoju orientačnú cenu balenia. Ak ju nezmeníš, PRÍDEL používa cenu z databázy.'),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: pack,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Veľkosť balenia (${def.unit})'))),
              const SizedBox(width: 8),
              Expanded(
                  child: TextField(
                      controller: price,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration:
                          const InputDecoration(labelText: 'Cena balenia €'))),
            ]),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Uložiť cenu')),
          ],
        ),
      ),
    );
    if (saved == true) {
      await widget.controller.database.setIngredientPrice(
        item.ingredient,
        pack: double.tryParse(pack.text.replaceAll(',', '.')),
        packPrice: double.tryParse(price.text.replaceAll(',', '.')),
      );
      widget.controller.dataChanged({AppArea.shopping, AppArea.pantry});
    }
    pack.dispose();
    price.dispose();
  }

  Future<void> _copyList() async {
    final buffer =
        StringBuffer('PRÍDEL – nákup ${PridelDates.weekRange(weekStart)}\n');
    for (final item in items.where((e) => !e.checked && e.purchaseQty > 0)) {
      buffer.writeln(
          '☐ ${item.ingredient} – ${UnitMath.format(item.purchaseQty, item.unit)}');
    }
    for (final row in manual.where((e) => (e['checked'] as int? ?? 0) != 1)) {
      buffer.writeln(
          '☐ ${row['name']} – ${UnitMath.format((row['qty'] as num?)?.toDouble() ?? 1, row['unit']?.toString() ?? 'ks')}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Nákupný zoznam je skopírovaný. Môžeš ho poslať komukoľvek.')));
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<ShoppingItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.category, () => []).add(item);
    }
    final categories = groups.keys.toList()..sort();
    final estimated =
        items.fold<double>(0, (sum, e) => sum + (e.estimatedCost ?? 0));
    final checkedCount = items.where((e) => e.checked).length;

    return Column(children: [
      PageHeader(
        title: 'Nákup',
        subtitle: PridelDates.weekRange(weekStart),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton.filledTonal(
              onPressed: _copyList,
              icon: const Icon(Icons.ios_share_outlined),
              tooltip: 'Skopírovať / zdieľať zoznam'),
          const SizedBox(width: 6),
          IconButton.filledTonal(
              onPressed: _addManual,
              icon: const Icon(Icons.add),
              tooltip: 'Pridať ručne'),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: [
          Row(children: [
            IconButton(
                onPressed: () => _moveWeek(-1),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Center(
                    child: Text(
                        'Odhad spolu: ${estimated.toStringAsFixed(2)} €',
                        style: Theme.of(context).textTheme.titleMedium))),
            IconButton(
                onPressed: () => _moveWeek(1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          if (!usePantry)
            const Card(
              child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Zásoby sa pri nákupe neodpočítavajú'),
                subtitle: Text(
                    'Toto je nastavené zámerne. Zmeniť sa to dá v Nastaveniach.'),
              ),
            ),
          if (usePantry && checkedCount > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  onPressed: _addCheckedToPantry,
                  icon: const Icon(Icons.kitchen_outlined),
                  label: Text('Pridať kúpené do skladu ($checkedCount)')),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty && manual.isEmpty
                ? const EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: 'Nákup je prázdny',
                    message:
                        'Keď naplánuješ jedlá, PRÍDEL zlúči rovnaké suroviny, odpočíta sklad a vypočíta potrebné balenia.',
                  )
                : RefreshIndicator(
                    onRefresh: _reload,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      children: [
                        ...categories.map((category) => Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                        padding: const EdgeInsets.only(
                                            left: 4, bottom: 8),
                                        child: Text(category,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium)),
                                    Card(
                                      child: Column(children: [
                                        for (int i = 0;
                                            i < groups[category]!.length;
                                            i++) ...[
                                          _itemTile(groups[category]![i]),
                                          if (i < groups[category]!.length - 1)
                                            const Divider(indent: 58),
                                        ]
                                      ]),
                                    ),
                                  ]),
                            )),
                        if (manual.isNotEmpty) ...[
                          Text('Ručne pridané',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Card(
                            child: Column(children: [
                              for (int i = 0; i < manual.length; i++) ...[
                                _manualTile(manual[i]),
                                if (i < manual.length - 1)
                                  const Divider(indent: 58),
                              ]
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    ]);
  }

  Widget _itemTile(ShoppingItem item) {
    final purchase = item.packages > 0
        ? '${item.packages}× balenie · ${UnitMath.format(item.purchaseQty, item.unit)}'
        : UnitMath.format(item.purchaseQty, item.unit);
    final price = item.estimatedCost == null
        ? 'cena nezadaná'
        : '~${item.estimatedCost!.toStringAsFixed(2)} €';
    return ListTile(
      contentPadding:
          const EdgeInsets.only(left: 6, right: 4, top: 5, bottom: 5),
      leading: Checkbox(
          value: item.checked,
          onChanged: (value) => _toggle(item, value ?? false)),
      title: Text(item.ingredient,
          style: TextStyle(
              decoration: item.checked ? TextDecoration.lineThrough : null)),
      subtitle: Text(
          'potreba ${UnitMath.format(item.neededQty, item.unit)} · kúpiť $purchase · $price'),
      trailing: IconButton(
          tooltip: 'Upraviť cenu balenia',
          onPressed: () => _editPrice(item),
          icon: const Icon(Icons.euro, size: 20)),
    );
  }

  Widget _manualTile(Map<String, Object?> row) {
    final id = row['id'] as int;
    final checked = (row['checked'] as int? ?? 0) == 1;
    final qty = (row['qty'] as num).toDouble();
    final unit = row['unit'] as String;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 6, right: 4),
      leading: Checkbox(
        value: checked,
        onChanged: (value) async {
          await widget.controller.database
              .setManualShoppingChecked(id, value ?? false);
          await _reload();
        },
      ),
      title: Text(row['name'] as String,
          style: TextStyle(
              decoration: checked ? TextDecoration.lineThrough : null)),
      subtitle: Text(UnitMath.format(qty, unit)),
      trailing: IconButton(
        onPressed: () async {
          await widget.controller.database.deleteManualShopping(id);
          await _reload();
        },
        icon: const Icon(Icons.close),
      ),
    );
  }
}
