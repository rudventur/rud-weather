import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web/web.dart' as web;

/// Tracks PWA install availability (beforeinstallprompt captured in web/index.html).
class InstallState extends ChangeNotifier {
  InstallState._() {
    web.window.addEventListener(
      'rw-install-change',
      ((web.Event _) => notifyListeners()).toJS,
    );
  }
  static final instance = InstallState._();

  bool get standalone {
    final f = globalContext['rwIsStandalone'];
    if (f == null) return false;
    return ((f as JSFunction).callAsFunction() as JSBoolean?)?.toDart ?? false;
  }

  bool get installed =>
      standalone ||
      ((globalContext['rwInstalled'] as JSBoolean?)?.toDart ?? false);
  bool get canPrompt =>
      globalContext['rwInstallPrompt'] != null &&
      !globalContext['rwInstallPrompt'].isUndefinedOrNull;
  bool get showButton => !installed;

  String get _ua => web.window.navigator.userAgent.toLowerCase();
  bool get isIos =>
      _ua.contains('iphone') ||
      _ua.contains('ipad') ||
      _ua.contains('ipod') ||
      (_ua.contains('macintosh') && web.window.navigator.maxTouchPoints > 1);
  bool get isMobile =>
      isIos || _ua.contains('android') || _ua.contains('mobile');

  Future<void> install(BuildContext context) async {
    if (canPrompt) {
      final p =
          (globalContext['rwPromptInstall'] as JSFunction).callAsFunction()
              as JSPromise<JSAny?>;
      await p.toDart;
      notifyListeners();
      return;
    }
    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => isIos ? const _IosDialog() : const _OtherDialog(),
    );
  }

  static const _bannerKey = 'rw_install_banner_dismissed';
  bool get bannerDismissed =>
      web.window.localStorage.getItem(_bannerKey) != null;
  void dismissBanner() {
    web.window.localStorage.setItem(_bannerKey, '1');
    notifyListeners();
  }
}

const _green = Color(0xFF00FF41);

Widget _step(int n, IconData icon, String text) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 8),
  child: Row(
    children: [
      CircleAvatar(
        radius: 13,
        backgroundColor: _green,
        child: Text(
          '$n',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      const SizedBox(width: 12),
      Icon(icon, color: _green),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  ),
);

Widget _title(String t) => Row(
  children: [
    const Icon(Icons.download_rounded, color: _green),
    const SizedBox(width: 8),
    Flexible(
      child: Text(
        t,
        style: GoogleFonts.syne(fontWeight: FontWeight.w800, color: _green),
      ),
    ),
  ],
);

class _IosDialog extends StatelessWidget {
  const _IosDialog();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: _title('Install on iPhone / iPad'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Open this page in Safari, then:'),
        const SizedBox(height: 8),
        _step(1, Icons.ios_share, 'Tap the Share button in the toolbar'),
        _step(
          2,
          Icons.add_box_outlined,
          'Scroll down and tap "Add to Home Screen"',
        ),
        _step(
          3,
          Icons.check_circle_outline,
          'Tap "Add" — Rud Weather appears on your Home Screen',
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Got it'),
      ),
    ],
  );
}

class _OtherDialog extends StatelessWidget {
  const _OtherDialog();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: _title('Install Rud Weather'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Your browser didn't offer a one-tap install here. You can still install it:",
        ),
        const SizedBox(height: 8),
        _step(1, Icons.more_vert, 'Open the browser menu (⋮ or ⋯)'),
        _step(
          2,
          Icons.install_mobile,
          'Choose "Install app" or "Add to Home screen"',
        ),
        _step(
          3,
          Icons.check_circle_outline,
          'Confirm — it opens like a normal app',
        ),
        const SizedBox(height: 8),
        Text(
          'Best support: Chrome or Edge (Android, Windows, Mac), Safari on iPhone.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Got it'),
      ),
    ],
  );
}

/// Rail button for wide screens.
class InstallRailButton extends StatelessWidget {
  const InstallRailButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: InstallState.instance,
    builder: (context, _) {
      final s = InstallState.instance;
      if (!s.showButton) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Tooltip(
          message: 'Install Rud Weather as an app',
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => s.install(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: _green),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.download_rounded, color: _green),
                  Text(
                    'Install',
                    style: GoogleFonts.dmMono(fontSize: 10, color: _green),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Small floating install icon for phones (top-right).
class InstallFab extends StatelessWidget {
  const InstallFab({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: InstallState.instance,
    builder: (context, _) {
      final s = InstallState.instance;
      if (!s.showButton) return const SizedBox.shrink();
      return Material(
        color: Colors.black,
        shape: const StadiumBorder(side: BorderSide(color: _green)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => s.install(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.download_rounded, color: _green, size: 18),
                const SizedBox(width: 4),
                Text(
                  'Install',
                  style: GoogleFonts.dmMono(
                    fontSize: 11,
                    color: _green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// One-time dismissible banner on mobile.
class InstallBanner extends StatelessWidget {
  const InstallBanner({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: InstallState.instance,
    builder: (context, _) {
      final s = InstallState.instance;
      if (!s.showButton || !s.isMobile || s.bannerDismissed) {
        return const SizedBox.shrink();
      }
      return Material(
        color: const Color(0xFF003311),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.install_mobile, color: _green),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Get Rud Weather on your home screen',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    s.dismissBanner();
                    s.install(context);
                  },
                  child: const Text('Install'),
                ),
                IconButton(
                  tooltip: 'Dismiss',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: s.dismissBanner,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
