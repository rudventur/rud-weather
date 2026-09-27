# Rud Weather ☀️🌧️

A mobile-first, installable **Flutter web app** (PWA) with live weather, an interactive map,
animated rain radar, temperature/wind map layers and hourly-refreshed weather news.

**Live:** https://rudventur.github.io/rud-weather/

## Features

- **Weather** – current conditions (temperature, feels like, wind + gusts, humidity, precipitation,
  pressure, UV index, cloud cover, sunrise/sunset), **next 48 hours** and **7-day** forecast.
  Uses your location (browser geolocation) with a fallback to London; city search;
  saved/favourite places (stored locally); °C/°F and km/h/mph toggles; pull to refresh.
  US locations also show active National Weather Service alerts.
- **Map** – interactive OpenStreetMap map (`flutter_map`): tap anywhere for the weather at that point,
  search places, your location marker, open the full forecast for any point.
- **Weather maps** – toggleable overlays with legend and opacity control:
  - RainViewer **rain radar** with animated timeline (past ~2 h; nowcast frames are shown automatically if RainViewer provides them),
  - RainViewer **satellite infrared** (toggle becomes available only if RainViewer publishes IR frames – currently it does not),
  - **Temperature** and **wind** layers built live from an Open-Meteo grid sampled over the visible map area.
- **News** – current weather headlines (source, time, link) from several public RSS feeds, refreshed hourly
  by GitHub Actions into `news.json`, plus Met Office UK warnings when active.
- **PWA** – web manifest, maskable icons, apple-touch-icon, theme colour, service worker (offline app shell).

Deep links: `?tab=weather|map|news` and `?layers=radar,sat,temp,wind`, e.g.
`https://rudventur.github.io/rud-weather/?tab=map&layers=radar,temp`.

## Install on your phone

**Android (Chrome):** open the live URL → menu ⋮ → **Install app** / **Add to Home screen**.

**iPhone / iPad (Safari):** open the live URL → **Share** button → **Add to Home Screen** → Add.
The app then opens full-screen like a native app.

## Data sources (all key-free)

| What | Source |
| --- | --- |
| Forecast, map grid layers | [Open-Meteo](https://open-meteo.com/) forecast API (CC BY 4.0) |
| Forecast fallback (if Open-Meteo is unavailable/rate-limited) | [MET Norway Locationforecast](https://api.met.no/) (CC BY 4.0) |
| City search | Open-Meteo Geocoding API |
| Place names for map taps | OpenStreetMap [Nominatim](https://nominatim.org/) |
| Base map | © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors |
| Radar / satellite | [RainViewer](https://www.rainviewer.com/api.html) public API |
| US alerts | [api.weather.gov](https://www.weather.gov/documentation/services-web-api) |
| News | The Guardian (Weather), Severe Weather Europe, CBS News Weather, BBC News (filtered), NASA Earth Observatory, NOAA, National Weather Service, NHC (Atlantic & E. Pacific), Yale Climate Connections, NYT Climate (filtered), Sky News (filtered), EUMETSAT; Met Office UK warnings |

## Development

```bash
flutter pub get
flutter run -d chrome
# refresh news locally
(cd tools/news && npm ci && node fetch_news.mjs)
flutter build web --release --base-href /rud-weather/
```

Deployment: `.github/workflows/deploy.yml` builds with `subosito/flutter-action` and publishes to
GitHub Pages via `actions/deploy-pages` on every push to `main` and **hourly** (to refresh the news).
