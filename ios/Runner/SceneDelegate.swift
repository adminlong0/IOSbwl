import CoreLocation
import SwiftUI
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = UIHostingController(rootView: NLBUSAppView())
    self.window = window
    window.makeKeyAndVisible()
  }
}

@MainActor
final class BusStore: NSObject, ObservableObject, CLLocationManagerDelegate {
  @Published var cityName = "莆田市"
  @Published var cityDisplayName = "莆田公交"
  @Published var searchText = ""
  @Published var searchResults: [SearchItem] = []
  @Published var allLines: [BusLine] = []
  @Published var nearbyStations: [NearbyStation] = []
  @Published var transferPlans: [TransferPlan] = []
  @Published var startText = ""
  @Published var endText = ""
  @Published var isLoading = false
  @Published var message: String?

  private let api = BusAPI()
  private let cityKey = "pt111601"
  private let locationManager = CLLocationManager()
  private var lastLocation: CLLocation?

  override init() {
    super.init()
    locationManager.delegate = self
    locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
  }

  func bootstrap() {
    Task {
      await loadCity()
      await loadAllLines()
      requestNearbyStations()
    }
  }

  func loadCity() async {
    do {
      let payload = try await api.request(["CMD": "205", "CITYKEY": cityKey])
      if let city = payload["city"] as? [String: Any] {
        cityName = city.string("cityname", fallback: cityName)
        let showName = city.string("showName", fallback: "")
        cityDisplayName = showName.isEmpty ? "\(cityName)公交" : showName
      }
    } catch {
      message = error.localizedDescription
    }
  }

  func search() async {
    let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !keyword.isEmpty else {
      searchResults = []
      return
    }
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "102",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "KEYWORD": keyword,
      ])
      var items: [SearchItem] = []
      for line in payload.array("buslines") {
        items.append(.line(BusLine(dictionary: line)))
      }
      for station in payload.array("busstations") {
        items.append(.station(BusStation(dictionary: station)))
      }
      searchResults = items
    } catch {
      message = error.localizedDescription
    }
  }

  func loadAllLines() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "119",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "KEY": "",
      ])
      allLines = payload.array("buslines").map(BusLine.init(dictionary:))
    } catch {
      message = error.localizedDescription
    }
  }

  func requestNearbyStations() {
    locationManager.requestWhenInUseAuthorization()
    locationManager.requestLocation()
  }

  func loadNearbyStations(lng: String = "", lat: String = "") async {
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "106",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "LNG": lng,
        "LAT": lat,
      ])
      nearbyStations = payload.array("data").map(NearbyStation.init(dictionary:))
    } catch {
      message = error.localizedDescription
    }
  }

  func searchTransfers() async {
    guard !startText.isEmpty, !endText.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await api.request([
        "CMD": "111",
        "CITYNAME": cityName,
        "CITYKEY": cityKey,
        "STARTNAME": startText,
        "ENDNAME": endText,
        "SLAT": "",
        "SLNG": "",
        "ELAT": "",
        "ELNG": "",
      ])
      transferPlans = payload.array("data").map(TransferPlan.init(dictionary:))
    } catch {
      message = error.localizedDescription
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    Task { @MainActor in
      lastLocation = location
      await loadNearbyStations(
        lng: "\(location.coordinate.longitude)",
        lat: "\(location.coordinate.latitude)"
      )
    }
  }

  nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    Task { @MainActor in
      await loadNearbyStations()
    }
  }
}

final class BusAPI {
  private let endpoint = URL(string: "https://h5.mygolbs.com/ApiData.do")!

  func request(_ parameters: [String: String]) async throws -> [String: Any] {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/javascript, */*; q=0.01", forHTTPHeaderField: "Accept")
    request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
    request.setValue("https://h5.mygolbs.com/?areacode=pt111601", forHTTPHeaderField: "Referer")
    request.setValue("https://h5.mygolbs.com", forHTTPHeaderField: "Origin")
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
      forHTTPHeaderField: "User-Agent"
    )
    request.httpBody = parameters
      .map { key, value in "\(key.urlEncoded)=\(value.urlEncoded)" }
      .joined(separator: "&")
      .data(using: .utf8)

    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw BusError.server
    }
    guard
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw BusError.invalidData
    }
    if object.int("status") == 1 || object["status"] == nil {
      return object
    }
    throw BusError.message(object.string("msg", fallback: "请求失败"))
  }
}

enum BusError: LocalizedError {
  case server
  case invalidData
  case message(String)

  var errorDescription: String? {
    switch self {
    case .server:
      return "公交服务暂时不可用"
    case .invalidData:
      return "无法解析公交数据"
    case .message(let text):
      return text
    }
  }
}

struct BusLine: Identifiable, Hashable {
  var id: String { "\(name)-\(direction)" }
  let name: String
  let direction: String
  let destination: String
  let beginTime: String
  let endTime: String

  init(dictionary: [String: Any]) {
    name = dictionary.string("lineName", fallback: dictionary.string("routeName", fallback: "未知线路"))
    direction = dictionary.string("upperOrDown", fallback: dictionary.string("uod", fallback: "1"))
    destination = dictionary.string("to", fallback: dictionary.string("endStation", fallback: ""))
    beginTime = dictionary.string("beginTime", fallback: "")
    endTime = dictionary.string("endTime", fallback: "")
  }
}

struct BusStation: Identifiable, Hashable {
  var id: String { name }
  let name: String
  let latitude: String
  let longitude: String

  init(dictionary: [String: Any]) {
    name = dictionary.string("stationName", fallback: dictionary.string("name", fallback: "未知站点"))
    latitude = dictionary.string("lat", fallback: "")
    longitude = dictionary.string("lon", fallback: dictionary.string("lng", fallback: ""))
  }
}

struct NearbyStation: Identifiable, Hashable {
  var id: String { "\(name)-\(latitude)-\(longitude)" }
  let name: String
  let distance: String
  let latitude: String
  let longitude: String

  init(dictionary: [String: Any]) {
    name = dictionary.string("name", fallback: dictionary.string("stationName", fallback: "未知站点"))
    distance = dictionary.string("dis", fallback: "")
    latitude = dictionary.string("lat", fallback: "")
    longitude = dictionary.string("lon", fallback: dictionary.string("lng", fallback: ""))
  }
}

struct RouteStop: Identifiable, Hashable {
  var id: Int { order }
  let order: Int
  let name: String
  let latitude: String
  let longitude: String

  init(index: Int, dictionary: [String: Any]) {
    order = dictionary.int("stationOrder", fallback: dictionary.int("order", fallback: index + 1))
    name = dictionary.string("stationName", fallback: dictionary.string("name", fallback: "站点"))
    latitude = dictionary.string("lat", fallback: "")
    longitude = dictionary.string("lon", fallback: dictionary.string("lng", fallback: ""))
  }
}

struct LiveBus: Identifiable, Hashable {
  var id: String { busName + "-\(stationOrder)-\(distance)" }
  let busName: String
  let stationOrder: Int
  let distance: String
  let speed: String

  init(index: Int, dictionary: [String: Any]) {
    busName = dictionary.string("busName", fallback: dictionary.string("name", fallback: "车辆 \(index + 1)"))
    stationOrder = dictionary.int("stationOrder", fallback: dictionary.int("order", fallback: 0))
    distance = dictionary.string("dis", fallback: dictionary.string("distance", fallback: ""))
    speed = dictionary.string("speed", fallback: "")
  }
}

struct TransferPlan: Identifiable, Hashable {
  let id = UUID()
  let startStation: String
  let endStation: String
  let firstLine: String
  let secondLine: String
  let summary: String

  init(dictionary: [String: Any]) {
    startStation = dictionary.string("startStation", fallback: dictionary.string("upStation", fallback: "起点"))
    endStation = dictionary.string("endStation", fallback: dictionary.string("downStation", fallback: "终点"))
    firstLine = dictionary.string("startLineName", fallback: dictionary.string("firstLine", fallback: ""))
    secondLine = dictionary.string("endLineName", fallback: dictionary.string("secondLine", fallback: ""))
    summary = dictionary.string("totalTime", fallback: dictionary.string("stationNum", fallback: ""))
  }
}

enum SearchItem: Identifiable, Hashable {
  case line(BusLine)
  case station(BusStation)

  var id: String {
    switch self {
    case .line(let line): return "line-\(line.id)"
    case .station(let station): return "station-\(station.id)"
    }
  }
}

struct NLBUSAppView: View {
  @StateObject private var store = BusStore()

  var body: some View {
    TabView {
      SearchView()
        .environmentObject(store)
        .tabItem { Label("查询", systemImage: "magnifyingglass") }
      NearbyView()
        .environmentObject(store)
        .tabItem { Label("附近", systemImage: "location") }
      AllLinesView()
        .environmentObject(store)
        .tabItem { Label("线路", systemImage: "bus") }
      TransferView()
        .environmentObject(store)
        .tabItem { Label("换乘", systemImage: "arrow.triangle.swap") }
    }
    .accentColor(.green)
    .task { store.bootstrap() }
    .alert("提示", isPresented: Binding(
      get: { store.message != nil },
      set: { if !$0 { store.message = nil } }
    )) {
      Button("好", role: .cancel) { store.message = nil }
    } message: {
      Text(store.message ?? "")
    }
  }
}

struct SearchView: View {
  @EnvironmentObject private var store: BusStore

  var body: some View {
    NavigationView {
      List {
        Section {
          TextField("输入线路或站点", text: $store.searchText)
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit { Task { await store.search() } }
          Button {
            Task { await store.search() }
          } label: {
            Label("搜索", systemImage: "magnifyingglass")
          }
        }

        if store.searchResults.isEmpty {
          EmptyStateView(
            symbol: "bus.doubledecker",
            title: "实时公交查询",
            message: "搜索线路、站点，查看车辆到站与站序信息。"
          )
        } else {
          Section("结果") {
            ForEach(store.searchResults) { item in
              switch item {
              case .line(let line):
                NavigationLink(destination: LineDetailView(line: line).environmentObject(store)) {
                  LineRow(line: line)
                }
              case .station(let station):
                NavigationLink(destination: StationLinesView(stationName: station.name).environmentObject(store)) {
                  Label(station.name, systemImage: "mappin.and.ellipse")
                }
              }
            }
          }
        }
      }
      .navigationTitle("NLBUS")
      .refreshable { await store.search() }
    }
  }
}

struct NearbyView: View {
  @EnvironmentObject private var store: BusStore

  var body: some View {
    NavigationView {
      List {
        Section {
          Button {
            store.requestNearbyStations()
          } label: {
            Label("重新定位附近站点", systemImage: "location.fill")
          }
        }
        if store.nearbyStations.isEmpty {
          EmptyStateView(symbol: "location.slash", title: "暂无附近站点", message: "允许定位后会显示附近公交站。")
        } else {
          Section("附近站点") {
            ForEach(store.nearbyStations) { station in
              NavigationLink(destination: StationLinesView(stationName: station.name).environmentObject(store)) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(station.name).font(.headline)
                  if !station.distance.isEmpty {
                    Text("\(station.distance)m").foregroundColor(.secondary)
                  }
                }
              }
            }
          }
        }
      }
      .navigationTitle("附近")
      .refreshable { store.requestNearbyStations() }
    }
  }
}

struct AllLinesView: View {
  @EnvironmentObject private var store: BusStore

  var body: some View {
    NavigationView {
      List {
        if store.allLines.isEmpty {
          EmptyStateView(symbol: "bus", title: "暂无线路", message: "下拉刷新线路列表。")
        } else {
          ForEach(store.allLines) { line in
            NavigationLink(destination: LineDetailView(line: line).environmentObject(store)) {
              LineRow(line: line)
            }
          }
        }
      }
      .navigationTitle("线路")
      .refreshable { await store.loadAllLines() }
    }
  }
}

struct TransferView: View {
  @EnvironmentObject private var store: BusStore

  var body: some View {
    NavigationView {
      List {
        Section {
          TextField("起点站", text: $store.startText)
          TextField("终点站", text: $store.endText)
          Button {
            Task { await store.searchTransfers() }
          } label: {
            Label("查询换乘方案", systemImage: "arrow.triangle.turn.up.right.diamond")
          }
        }
        if store.transferPlans.isEmpty {
          EmptyStateView(symbol: "arrow.triangle.swap", title: "换乘查询", message: "输入起点和终点站，获取公交换乘方案。")
        } else {
          Section("方案") {
            ForEach(store.transferPlans) { plan in
              VStack(alignment: .leading, spacing: 6) {
                Text(plan.firstLine.isEmpty ? "换乘方案" : plan.firstLine).font(.headline)
                if !plan.secondLine.isEmpty {
                  Text("换乘 \(plan.secondLine)").foregroundColor(.secondary)
                }
                Text("\(plan.startStation) → \(plan.endStation)").font(.subheadline)
                if !plan.summary.isEmpty {
                  Text(plan.summary).font(.caption).foregroundColor(.secondary)
                }
              }
              .padding(.vertical, 4)
            }
          }
        }
      }
      .navigationTitle("换乘")
    }
  }
}

struct LineDetailView: View {
  @EnvironmentObject private var store: BusStore
  let line: BusLine
  @State private var stops: [RouteStop] = []
  @State private var buses: [LiveBus] = []
  @State private var selectedOrder = 1
  @State private var planTime = ""
  @State private var isLoading = false

  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 8) {
          Text(line.name).font(.title2.bold())
          if !line.destination.isEmpty {
            Text("开往 \(line.destination)").foregroundColor(.secondary)
          }
          if !planTime.isEmpty {
            Label("起点预计发车 \(planTime)", systemImage: "clock")
              .foregroundColor(.orange)
          }
        }
      }

      Section("实时车辆") {
        if buses.isEmpty {
          Text("暂无实时车辆数据").foregroundColor(.secondary)
        } else {
          ForEach(buses) { bus in
            HStack {
              Image(systemName: "bus.fill").foregroundColor(.green)
              VStack(alignment: .leading) {
                Text(bus.busName)
                Text("约在第 \(bus.stationOrder) 站附近").font(.caption).foregroundColor(.secondary)
              }
              Spacer()
              if !bus.distance.isEmpty {
                Text(bus.distance).foregroundColor(.secondary)
              }
            }
          }
        }
      }

      Section("站点") {
        ForEach(stops) { stop in
          Button {
            selectedOrder = stop.order
            Task { await loadRealtime() }
          } label: {
            HStack {
              Text("\(stop.order)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
              Text(stop.name)
              Spacer()
              if selectedOrder == stop.order {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
              }
            }
          }
        }
      }
    }
    .navigationTitle(line.name)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      Button {
        Task { await loadAll() }
      } label: {
        Image(systemName: "arrow.clockwise")
      }
    }
    .task { await loadAll() }
    .refreshable { await loadAll() }
  }

  private func loadAll() async {
    await loadStops()
    await loadRealtime()
  }

  private func loadStops() async {
    isLoading = true
    defer { isLoading = false }
    do {
      let payload = try await BusAPI().request([
        "CMD": "103",
        "CITYNAME": store.cityName,
        "CITYKEY": "pt111601",
        "LINENAME": line.name,
        "DIRECTION": line.direction,
      ])
      stops = payload.array("data").enumerated().map { RouteStop(index: $0.offset, dictionary: $0.element) }
      if selectedOrder <= 0 {
        selectedOrder = stops.first?.order ?? 1
      }
    } catch {
      store.message = error.localizedDescription
    }
  }

  private func loadRealtime() async {
    do {
      let payload = try await BusAPI().request([
        "CMD": "104",
        "CITYNAME": store.cityName,
        "CITYKEY": "pt111601",
        "LINENAME": line.name,
        "DIRECTION": line.direction,
        "STATIONORDER": "\(selectedOrder)",
      ])
      planTime = payload.string("planTime", fallback: "")
      buses = payload.array("list").enumerated().map { LiveBus(index: $0.offset, dictionary: $0.element) }
    } catch {
      store.message = error.localizedDescription
    }
  }
}

struct StationLinesView: View {
  @EnvironmentObject private var store: BusStore
  let stationName: String
  @State private var lines: [BusLine] = []

  var body: some View {
    List {
      if lines.isEmpty {
        EmptyStateView(symbol: "mappin", title: stationName, message: "暂无经过线路。")
      } else {
        ForEach(lines) { line in
          NavigationLink(destination: LineDetailView(line: line).environmentObject(store)) {
            LineRow(line: line)
          }
        }
      }
    }
    .navigationTitle(stationName)
    .navigationBarTitleDisplayMode(.inline)
    .task { await load() }
    .refreshable { await load() }
  }

  private func load() async {
    do {
      let payload = try await BusAPI().request([
        "CMD": "115",
        "CITYNAME": store.cityName,
        "CITYKEY": "pt111601",
        "STATIONNAME": stationName,
        "MYLAT": "",
        "MYLNG": "",
        "ALL": "1",
      ])
      lines = payload.array("data").map(BusLine.init(dictionary:))
    } catch {
      store.message = error.localizedDescription
    }
  }
}

struct LineRow: View {
  let line: BusLine

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "bus")
        .foregroundColor(.green)
        .frame(width: 30, height: 30)
      VStack(alignment: .leading, spacing: 4) {
        Text(line.name).font(.headline)
        if !line.destination.isEmpty {
          Text("开往 \(line.destination)").foregroundColor(.secondary)
        }
      }
    }
    .padding(.vertical, 3)
  }
}

struct EmptyStateView: View {
  let symbol: String
  let title: String
  let message: String

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 42)).foregroundColor(.secondary)
      Text(title).font(.headline)
      Text(message).font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 50)
  }
}

extension Dictionary where Key == String, Value == Any {
  func string(_ key: String, fallback: String = "") -> String {
    if let value = self[key] as? String { return value }
    if let value = self[key] as? NSNumber { return value.stringValue }
    if let value = self[key] { return "\(value)" }
    return fallback
  }

  func int(_ key: String, fallback: Int = 0) -> Int {
    if let value = self[key] as? Int { return value }
    if let value = self[key] as? NSNumber { return value.intValue }
    if let value = self[key] as? String, let intValue = Int(value) { return intValue }
    return fallback
  }

  func array(_ key: String) -> [[String: Any]] {
    self[key] as? [[String: Any]] ?? []
  }
}

extension String {
  var urlEncoded: String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&+=?")
    return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
  }
}
