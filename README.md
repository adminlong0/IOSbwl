# NLBUS

NLBUS is a three-platform real-time bus app for Putian (`pt111601`). The stable iOS app remains native SwiftUI, while Android 13+ and Web share a Flutter presentation and business layer so their information architecture, visual hierarchy, and interactions remain consistent.

## Current Experience

- Home tab: nearby stations within 500 meters, live vehicle preview, fuzzy line/station search, search history
- Routes tab: all routes plus favorite routes pinned at the top
- Line details: favorite action, two-way direction switch, operation time, timetable hint, fare, next departure, route info, arrival analysis, mileage, remarks, stop list, live map
- Station details: passing routes, station vehicles, nearby stations
- Map tab: route/station/vehicle filtering with native MapKit annotations
- Settings tab: theme mode, accent color, local backup export/import, app info, developer `@奶龙`
- Global quick action button: Apple Wallet, Putian citizen card mini-program, arrival notification setup

Removed from the H5 reference intentionally:

- News/announcement pages
- Advertising and app-download promotion content
- Separate transfer and query bottom tabs

## Putian Citizen Card Link

The short link:

```text
https://wxmpurl.cn/vHnajJlAguq
```

returns an HTML bridge page for the WeChat mini-program `莆田市民卡`. The useful deep link exposed by that page is:

```text
weixin://dl/business/?t=vHnajJlAguq
```

## API

Reference page:

```text
https://h5.mygolbs.com/?areacode=pt111601
```

Endpoint:

```text
https://h5.mygolbs.com/ApiData.do
```

Core commands used:

- `CMD=205` city config
- `CMD=102` line/station search
- `CMD=119` all lines
- `CMD=106` nearby stations
- `CMD=115` station lines
- `CMD=103` line details
- `CMD=104` live vehicle data

## Platform Builds

- iOS: native SwiftUI, built with Xcode on macOS
- Android: Flutter, minimum Android 13 (`minSdk 33`)
- Web: Flutter responsive app, optimized for mobile and desktop browsers

The official API only returns readable JSON when requests carry its own H5 `Origin`. Native clients can reproduce that request context. Browsers cannot spoof `Origin`, so production Web deployments can pass a trusted same-origin proxy endpoint at build time:

```bash
flutter build web --release --dart-define=NLBUS_API_BASE=https://your-domain.example/api/transit
```

Without a proxy, the Web UI remains available and offers the official page as the realtime-data fallback. No public third-party proxy is used.

## Build With GitHub Actions

Open the repository on GitHub, go to `Actions`, run `Build NLBUS Multi-platform`, then download:

```text
nlbus-ios-unsigned-ipa
nlbus-android-apk
nlbus-web-zip
```

The artifacts contain:

```text
NLBUS-unsigned.ipa
app-release.apk
NLBUS-Web.zip
```

The IPA is unsigned and requires manual signing before normal iPhone installation. The APK uses the repository's development release signing configuration and is suitable for direct testing, not Play Store publication.
