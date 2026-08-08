# NLBUS

NLBUS is a native iOS real-time bus app for Putian (`pt111601`). It rebuilds the MyGoLBS H5 transit experience as a SwiftUI app with Apple system controls instead of embedding the website.

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

## Build IPA With GitHub Actions

Open the repository on GitHub, go to `Actions`, run `Build iOS IPA`, then download:

```text
nlbus-unsigned-ipa
```

The generated file is:

```text
NLBUS-unsigned.ipa
```

Unsigned IPA files require manual signing before normal iPhone installation.
