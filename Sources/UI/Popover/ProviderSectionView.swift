import SwiftUI
import UsageCore

/// One service in the menu: name, plan, metrics and any problem that needs attention.
struct ProviderSectionView: View {
    let provider: ProviderID
    let status: ProviderStatus
    let refreshInterval: TimeInterval
    let perform: (ProblemDescription.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let snapshot = status.snapshot {
                content(snapshot)
            } else if status.error == nil {
                placeholder
            }

            if let error = status.error, !(status.snapshot != nil && error == .offline) {
                ProblemBanner(problem: ProblemDescription(error, provider: provider), perform: perform)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Label {
                Text(provider.displayName)
            } icon: {
                ProviderLogo(provider: provider)
            }
            .font(.headline)
            if let plan = status.snapshot?.planName {
                Text(plan)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            if let snapshot = status.snapshot, isStale(snapshot) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Label(Format.updated(snapshot.asOf, now: context.date), systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: ProviderSnapshot) -> some View {
        switch provider {
        case .openAI:
            OpenAISpendView(snapshot: snapshot)
        case .claude, .cursor:
            ForEach(snapshot.metrics) { metric in
                MetricRowView(metric: metric)
            }
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricRowView(metric: UsageMetric(id: "placeholder.1", role: .session, unit: .percent, used: 40))
            MetricRowView(metric: UsageMetric(id: "placeholder.2", role: .weekly, unit: .percent, used: 20))
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    /// Data older than a few polls is marked, so old numbers are never mistaken for current ones.
    private func isStale(_ snapshot: ProviderSnapshot) -> Bool {
        Date.now.timeIntervalSince(snapshot.asOf) > max(3 * refreshInterval, 15 * 60)
    }
}

struct ProblemBanner: View {
    let problem: ProblemDescription
    let perform: (ProblemDescription.Action) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: problem.isWarning ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(problem.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(problem.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let title = problem.actionTitle, let action = problem.action {
                Button(title) { perform(action) }
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
