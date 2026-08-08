# NLBUS

NLBUS is a native iOS real-time bus app for Putian (`pt111601`), rebuilt from the MyGoLBS H5 transit system as a SwiftUI app instead of an embedded webpage.

## Features

- Search bus lines and stations
- Browse all lines
- Show nearby stations with iOS location permission
- Show station-related lines
- Show line stops and live vehicle data
- Search transfer plans
- Removes news/announcement pages and advertising/download content

## Native iOS Design

The app uses Apple system components:

- `TabView`
- `NavigationView`
- `List`
- `Section`
- `TextField`
- `Button`
- `Label`
- `Alert`
- SF Symbols
- CoreLocation permission flow

## API

The app calls the same core API used by:

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
- `CMD=111` transfer search

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
