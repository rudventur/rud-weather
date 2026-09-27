import 'package:flutter/material.dart';

import 'pages/map_page.dart';
import 'pages/news_page.dart';
import 'pages/weather_page.dart';
import 'services/app_state.dart';

void main() {
  final state = AppState();
  runApp(RudWeatherApp(state: state));
  state.init();
}

/// Makes [AppState] available to the widget tree and rebuilds dependents on change.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);
  static AppState of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
  static AppState read(BuildContext context) => context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}

class RudWeatherApp extends StatelessWidget {
  final AppState state;
  const RudWeatherApp({super.key, required this.state});

  ThemeData _theme(Brightness b) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0), brightness: b);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(elevation: 0, color: scheme.surfaceContainerLow, margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Rud Weather',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _dest = [
    (Icons.wb_sunny_outlined, Icons.wb_sunny, 'Weather'),
    (Icons.map_outlined, Icons.map, 'Map'),
    (Icons.newspaper_outlined, Icons.newspaper, 'News'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(
      index: s.tab,
      children: const [WeatherPage(), MapPage(), NewsPage()],
    );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: s.tab,
            onDestinationSelected: s.goTab,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(Icons.cloud_rounded, size: 36, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: [for (final d in _dest) NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3))],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: s.tab,
        onDestinationSelected: s.goTab,
        height: 64,
        destinations: [for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3)],
      ),
    );
  }
}
