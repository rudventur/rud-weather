{{flutter_js}}
{{flutter_build_config}}

// Our own service worker (web/sw.js) is registered in index.html, so do not pass
// serviceWorkerSettings here. CanvasKit is loaded from the app itself so it can be
// cached for offline use.
_flutter.loader.load({
  config: { canvasKitBaseUrl: 'canvaskit/' },
});
