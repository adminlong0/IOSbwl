import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NLBUSLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    NLBUSLiveActivityWidget()
    NLBUSStatusWidget()
  }
}

struct NLBUSStatusEntry: TimelineEntry {
  let date: Date
}

struct NLBUSStatusProvider: TimelineProvider {
  func placeholder(in context: Context) -> NLBUSStatusEntry { NLBUSStatusEntry(date: Date()) }
  func getSnapshot(in context: Context, completion: @escaping (NLBUSStatusEntry) -> Void) {
    completion(NLBUSStatusEntry(date: Date()))
  }
  func getTimeline(in context: Context, completion: @escaping (Timeline<NLBUSStatusEntry>) -> Void) {
    let entry = NLBUSStatusEntry(date: Date())
    completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
  }
}

struct NLBUSStatusWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "NLBUSStatus", provider: NLBUSStatusProvider()) { _ in
      VStack(alignment: .leading, spacing: 8) {
        Label("NLBUS", systemImage: "bus.fill").font(.headline)
        Text("打开查看附近站点与收藏线路")
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Text(Date(), style: .time).font(.caption2.monospacedDigit())
      }
      .padding()
      .background(Color(uiColor: .secondarySystemBackground))
    }
    .configurationDisplayName("公交状态")
    .description("快速进入 NLBUS 查看附近公交。")
    .supportedFamilies([.systemSmall, .systemMedium])
  }
}

struct NLBUSLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NLBUSActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Label(context.attributes.lineName, systemImage: "bus.fill")
            .font(.headline)
          Spacer()
          Text(context.state.distanceText).font(.subheadline.monospacedDigit())
        }
        Text("开往 \(context.state.destination)").font(.subheadline)
        HStack {
          Text("下一站 \(context.state.nextStation)")
          Spacer()
          Text("还有 \(context.state.remainingStops) 站")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      .padding()
      .activityBackgroundTint(.black.opacity(0.82))
      .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.attributes.lineName, systemImage: "bus.fill")
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.distanceText).monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(context.state.nextStation)
            Spacer()
            Text("\(context.state.remainingStops) 站")
          }
        }
      } compactLeading: {
        Image(systemName: "bus.fill")
      } compactTrailing: {
        Text("\(context.state.remainingStops)站")
      } minimal: {
        Image(systemName: "bus.fill")
      }
    }
  }
}
