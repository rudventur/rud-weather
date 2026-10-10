import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pages/map_page.dart';
import 'pages/three_days_page.dart';
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

  ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(seedColor: Rv.green, brightness: Brightness.dark).copyWith(
      primary: Rv.green,
      onPrimary: Colors.black,
      primaryContainer: const Color(0xFF003311),
      onPrimaryContainer: Rv.green,
      secondary: Rv.green2,
      onSecondary: Colors.black,
      secondaryContainer: const Color(0xFF0F2A18),
      onSecondaryContainer: const Color(0xFFB8FFD0),
      tertiary: const Color(0xFF00E5FF),
      surface: Rv.bg,
      onSurface: Rv.text,
      onSurfaceVariant: const Color(0xFFB0B0B0),
      surfaceContainerLowest: const Color(0xFF050505),
      surfaceContainerLow: Rv.card,
      surfaceContainer: const Color(0xFF151515),
      surfaceContainerHigh: const Color(0xFF1C1C1C),
      surfaceContainerHighest: const Color(0xFF242424),
      outline: const Color(0xFF555555),
      outlineVariant: const Color(0xFF333333),
    );
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: Brightness.dark);
    final TextTheme text = base.textTheme.apply(fontFamily: GoogleFonts.syne().fontFamily, bodyColor: Rv.text, displayColor: Rv.text);
    final mono = GoogleFonts.dmMono();
    return base.copyWith(
      scaffoldBackgroundColor: Rv.bg,
      textTheme: text.copyWith(
        bodyMedium: text.bodyMedium?.merge(GoogleFonts.dmSans()),
        bodySmall: text.bodySmall?.merge(GoogleFonts.dmSans()),
        bodyLarge: text.bodyLarge?.merge(GoogleFonts.dmSans()),
        labelSmall: text.labelSmall?.merge(mono),
        labelMedium: text.labelMedium?.merge(mono),
      ),
      cardTheme: CardThemeData(elevation: 0, color: Rv.card, margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFF2A2A2A)))),
      appBarTheme: AppBarTheme(backgroundColor: Rv.bg, foregroundColor: Rv.text, surfaceTintColor: Colors.transparent,
          titleTextStyle: GoogleFonts.syne(fontSize: 22, fontWeight: FontWeight.w800, color: Rv.green)),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.black,
        indicatorColor: const Color(0xFF003311),
        selectedIconTheme: const IconThemeData(color: Rv.green),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF9E9E9E)),
        selectedLabelTextStyle: GoogleFonts.dmMono(color: Rv.green, fontSize: 12, fontWeight: FontWeight.w500),
        unselectedLabelTextStyle: GoogleFonts.dmMono(color: const Color(0xFF9E9E9E), fontSize: 12),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.black,
        indicatorColor: const Color(0xFF003311),
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith((st) => IconThemeData(color: st.contains(WidgetState.selected) ? Rv.green : const Color(0xFF9E9E9E))),
        labelTextStyle: WidgetStateProperty.resolveWith((st) => GoogleFonts.dmMono(fontSize: 12, color: st.contains(WidgetState.selected) ? Rv.green : const Color(0xFF9E9E9E))),
      ),
      dividerTheme: const DividerThemeData(color: Color(0xFF2A2A2A)),
      chipTheme: ChipThemeData(backgroundColor: Rv.card, selectedColor: const Color(0xFF003311), side: const BorderSide(color: Color(0xFF333333)),
          labelStyle: GoogleFonts.dmMono(color: Rv.text, fontSize: 12), checkmarkColor: Rv.green),
      sliderTheme: const SliderThemeData(activeTrackColor: Rv.green, thumbColor: Rv.green, inactiveTrackColor: Color(0xFF1F3A26)),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: Rv.green, foregroundColor: Colors.black)),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: Rv.green, foregroundColor: Colors.black),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: Rv.green),
      tooltipTheme: TooltipThemeData(decoration: BoxDecoration(color: const Color(0xFF111111), border: Border.all(color: Rv.green), borderRadius: BorderRadius.circular(6)),
          textStyle: GoogleFonts.dmMono(color: Rv.green, fontSize: 12)),
      snackBarTheme: const SnackBarThemeData(backgroundColor: Color(0xFF111111), contentTextStyle: TextStyle(color: Rv.text)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'Rud Weather',
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        themeMode: ThemeMode.dark,
        home: const HomeShell(),
      ),
    );
  }
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const _dest = [
    (Icons.view_week_outlined, Icons.view_week, '3 days'),
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
      children: const [ThreeDaysPage(), WeatherPage(), MapPage(), NewsPage()],
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
            trailing: const Expanded(child: _ProjectRail()),
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
        onDestinationSelected: (i) => i == _dest.length ? showProjectsSheet(context) : s.goTab(i),
        height: 64,
        destinations: [
          for (final d in _dest) NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
          const NavigationDestination(icon: Icon(Icons.apps_rounded), label: 'Projects', tooltip: 'More projects'),
        ],
      ),
    );
  }
}

/// RudVentur.com palette (from rudventur/RudVentur.com index.html CSS variables).
class Rv {
  static const green = Color(0xFF00FF41); // --map
  static const green2 = Color(0xFF00FF88); // --chem
  static const bg = Color(0xFF0A0A0A); // --bg
  static const card = Color(0xFF1A1A1A);
  static const text = Color(0xFFF5F5F5); // --index
}

const projects = [
  (Icons.luggage_rounded, 'rudTrip20', 'https://rudventur.github.io/rudTrip20/'),
  (Icons.home_rounded, 'RudVentur.com', 'https://rudventur.com/'),
  (Icons.science_rounded, 'ChemVentur Multi v118', 'https://rudventur.github.io/ChemVentur-Multi-v118/'),
  (Icons.shuffle_rounded, 'Trip Randomiser', 'https://rudventur.github.io/trip-randomiser/'),
  (Icons.layers_rounded, 'Map Merger Venti', 'https://rudventur.github.io/map-merger-venti/'),
  (Icons.desktop_windows_rounded, 'LuxWin13', 'https://rudventur.github.io/LuxWin13/'),
  (Icons.auto_awesome_rounded, 'Cheese Ouija Empire', 'https://rudventur.github.io/cheese-ouiji-empire/'),
];

void openProject(String url) => launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');

class _ProjectRail extends StatelessWidget {
  const _ProjectRail();
  @override
  Widget build(BuildContext context) => Column(children: [
        const SizedBox(height: 8),
        const SizedBox(width: 48, child: Divider()),
        Text('PROJECTS', style: GoogleFonts.dmMono(fontSize: 9, color: Rv.green, letterSpacing: 1)),
        Expanded(
          child: SingleChildScrollView(
            child: Column(children: [
              for (final p in projects)
                IconButton(tooltip: p.$2, icon: Icon(p.$1, color: const Color(0xFFB0B0B0)), hoverColor: const Color(0xFF003311), onPressed: () => openProject(p.$3)),
            ]),
          ),
        ),
      ]);
}

void showProjectsSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('More projects', style: GoogleFonts.syne(fontSize: 20, fontWeight: FontWeight.w800, color: Rv.green)),
          ),
          for (final p in projects)
            ListTile(
              leading: Icon(p.$1, color: Rv.green),
              title: Text(p.$2),
              subtitle: Text(p.$3.replaceFirst('https://', ''), style: GoogleFonts.dmMono(fontSize: 11, color: const Color(0xFF888888))),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                openProject(p.$3);
              },
            ),
        ]),
      ),
    );
