import SwiftUI
import UsageCore

/// A metric with its value, a capacity gauge and the time until it resets.
struct MetricRowView: View {
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.role.title)
                Spacer()
                Text(Format.value(metric))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(metric.level.tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary))
            }
            .font(.callout)

            if let fraction = metric.fraction {
                Gauge(value: min(max(fraction, 0), 1)) {
                    EmptyView()
                }
                .gaugeStyle(.linearCapacity)
                .tint(metric.level.tint ?? Color(nsColor: .controlAccentColor))
                .labelsHidden()
            }

            if metric.role == .session && metric.resetsAt == nil {
                Text("Starts when you send a message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if metric.resetsAt != nil {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    if let reset = Format.reset(metric.resetsAt, now: context.date) {
                        Text(reset)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
