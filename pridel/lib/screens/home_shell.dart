import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import 'home_dashboard_screen.dart';
import 'pantry_screen.dart';
import 'plan_screen.dart';
import 'recipes_screen.dart';
import 'shopping_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  late final List<Widget> screens;

  @override
  void initState() {
    super.initState();
    screens = [
      HomeDashboardScreen(controller: widget.controller, onNavigate: _navigate),
      PlanScreen(controller: widget.controller),
      RecipesScreen(controller: widget.controller),
      PantryScreen(controller: widget.controller),
      ShoppingScreen(controller: widget.controller),
    ];
  }

  void _navigate(int value, {bool pantryOnly = false}) {
    if (pantryOnly) widget.controller.requestPantryRecipeFilter();
    if (mounted) setState(() => index = value);
  }

  static const destinations = [
    NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'Domov'),
    NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Plán'),
    NavigationDestination(
        icon: Icon(Icons.menu_book_outlined),
        selectedIcon: Icon(Icons.menu_book),
        label: 'Recepty'),
    NavigationDestination(
        icon: Icon(Icons.kitchen_outlined),
        selectedIcon: Icon(Icons.kitchen),
        label: 'Zásoby'),
    NavigationDestination(
        icon: Icon(Icons.shopping_bag_outlined),
        selectedIcon: Icon(Icons.shopping_bag),
        label: 'Nákup'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        if (wide) {
          return Scaffold(
            body: SafeArea(
              child: Row(
                children: [
                  NavigationRail(
                    selectedIndex: index,
                    onDestinationSelected: (value) =>
                        setState(() => index = value),
                    labelType: NavigationRailLabelType.all,
                    groupAlignment: -0.75,
                    destinations: const [
                      NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: Text('Domov')),
                      NavigationRailDestination(
                          icon: Icon(Icons.calendar_month_outlined),
                          selectedIcon: Icon(Icons.calendar_month),
                          label: Text('Plán')),
                      NavigationRailDestination(
                          icon: Icon(Icons.menu_book_outlined),
                          selectedIcon: Icon(Icons.menu_book),
                          label: Text('Recepty')),
                      NavigationRailDestination(
                          icon: Icon(Icons.kitchen_outlined),
                          selectedIcon: Icon(Icons.kitchen),
                          label: Text('Zásoby')),
                      NavigationRailDestination(
                          icon: Icon(Icons.shopping_bag_outlined),
                          selectedIcon: Icon(Icons.shopping_bag),
                          label: Text('Nákup')),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                      child: IndexedStack(index: index, children: screens)),
                ],
              ),
            ),
          );
        }
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: index, children: screens)),
          bottomNavigationBar: NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (value) => setState(() => index = value),
              destinations: destinations),
        );
      },
    );
  }
}
