import SwiftUI

/// One column of `NozirColumnChart`. `fraction` comes from `ChartMath.fractions`.
public struct NozirChartColumn: Identifiable, Equatable, Sendable {
    public let id: Int
    public let label: String
    /// Empty for a day still to come: "0d" over Friday on a Tuesday would be a lie.
    public let valueLabel: String
    public let fraction: Double
    public let isPeak: Bool

    public init(id: Int, label: String, valueLabel: String, fraction: Double, isPeak: Bool) {
        self.id = id
        self.label = label
        self.valueLabel = valueLabel
        self.fraction = fraction
        self.isPeak = isPeak
    }
}

/// Android `NozirColumnChart`: columns from a zero baseline, the peak in full
/// colour. VoiceOver reads `accessibilityLabel` (every figure as text) instead
/// of the bars.
public struct NozirColumnChart: View {
    private let columns: [NozirChartColumn]
    private let label: String
    private let height: CGFloat

    public init(columns: [NozirChartColumn], accessibilityLabel: String, height: CGFloat = 140) {
        self.columns = columns
        label = accessibilityLabel
        self.height = height
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: NozirSpacing.small) {
            ForEach(columns) { column in
                VStack(spacing: NozirSpacing.extraSmall) {
                    Text(column.valueLabel.isEmpty ? " " : column.valueLabel)
                        .nozirText(.label, color: column.isPeak ? NozirColor.primaryAccent : NozirColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(NozirColor.track)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(column.isPeak ? NozirColor.primary : NozirColor.primary.opacity(0.45))
                            .frame(height: barHeight(column.fraction))
                    }
                    .frame(height: height)
                    Text(column.label)
                        .nozirText(.label, color: NozirColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// A day with any use stays visible as a sliver.
    private func barHeight(_ fraction: Double) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(height * fraction, 4)
    }
}

public struct NozirChartSegment: Identifiable {
    public let id: Int
    public let fraction: Double
    public let color: Color

    public init(id: Int, fraction: Double, color: Color) {
        self.id = id
        self.fraction = fraction
        self.color = color
    }
}

/// Android `NozirStackedBar`: one bar split into each app's share. Decorative;
/// the screen gives the same figures as text.
public struct NozirStackedBar: View {
    private let segments: [NozirChartSegment]
    private let height: CGFloat
    private let gap: CGFloat = 2

    public init(segments: [NozirChartSegment], height: CGFloat = 14) {
        self.segments = segments
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let visible = segments.filter { $0.fraction > 0 }
            let usable = max(0, proxy.size.width - gap * CGFloat(max(visible.count - 1, 0)))
            HStack(spacing: gap) {
                ForEach(visible) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: usable * segment.fraction)
                }
            }
        }
        .frame(height: height)
        .background(NozirColor.track)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

public struct NozirLegendItem: Identifiable {
    public let id: Int
    public let color: Color
    public let label: String
    public let valueLabel: String

    public init(id: Int, color: Color, label: String, valueLabel: String) {
        self.id = id
        self.color = color
        self.label = label
        self.valueLabel = valueLabel
    }
}

/// A colour dot, a name and a figure per line.
public struct NozirLegend: View {
    private let items: [NozirLegendItem]

    public init(items: [NozirLegendItem]) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            ForEach(items) { item in
                HStack(spacing: NozirSpacing.small) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(item.label).nozirText(.bodySmall)
                    Spacer(minLength: NozirSpacing.small)
                    Text(item.valueLabel).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A thin track filled to `fraction` (0...1).
public struct NozirProgressBar: View {
    private let fraction: Double
    private let color: Color

    public init(fraction: Double, color: Color) {
        self.fraction = min(max(fraction, 0), 1)
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(NozirColor.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
