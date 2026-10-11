import Charts
import SwiftUI
import UsageCore

/// OpenAI spend: today and this month, a 30-day chart and the most expensive models.
struct OpenAISpendView: View {
    let snapshot: ProviderSnapshot

    private var code: String { snapshot.currencyCode ?? "USD" }
    private var month: UsageMetric? { snapshot.metrics.first { $0.role == .spendMonth } }
    private var today: UsageMetric? { snapshot.metrics.first { $0.role == .spendToday } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                amount(today)
                Spacer()
                amount(month, alignment: .trailing)
            }

            if let month, month.limit != nil {
                MetricRowView(metric: month)
            }

            if snapshot.history.contains(where: { $0.amount > 0 }) {
                SpendChartView(history: snapshot.history, currencyCode: code)
                    .frame(height: 36)
            }

            if !snapshot.breakdown.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(snapshot.breakdown) { item in
                        HStack {
                            Text(item.label ?? String(localized: "Other"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(Format.currency(item.amount, code: code))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func amount(_ metric: UsageMetric?, alignment: HorizontalAlignment = .leading) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(metric?.role.title ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.currency(metric?.used ?? 0, code: code))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .accessibilityElement(children: .combine)
    }
}

struct SpendChartView: View {
    let history: [DailyPoint]
    let currencyCode: String

    var body: some View {
        Chart(history) { point in
            BarMark(
                x: .value("Day", point.day, unit: .day),
                y: .value("Spend", point.amount)
            )
            .foregroundStyle(Color(nsColor: .controlAccentColor).gradient)
            .cornerRadius(1.5)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel(String(localized: "Daily spend, last 30 days"))
    }
}
