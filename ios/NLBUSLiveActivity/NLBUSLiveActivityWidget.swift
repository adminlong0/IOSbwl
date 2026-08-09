import ActivityKit
import SwiftUI
import WidgetKit

@main
struct NLBUSLiveActivityBundle: WidgetBundle {
  var body: some Widget { NLBUSLiveActivityWidget() }
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
