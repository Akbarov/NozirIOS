import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// How a server status level looks and reads.
extension StatusLevel {
    var designLevel: NozirStatusLevel {
        switch self {
        case .good: .good
        case .attention: .attention
        case .action: .action
        case .critical: .critical
        }
    }

    func label(_ l10n: L10n) -> String {
        switch self {
        case .good: l10n.statusLabelGood
        case .attention: l10n.statusLabelAttention
        case .action: l10n.statusLabelAction
        case .critical: l10n.statusLabelCritical
        }
    }

    func glyph(_ l10n: L10n) -> String {
        switch self {
        case .good: l10n.statusGlyphGood
        case .attention: l10n.statusGlyphAttention
        case .action: l10n.statusGlyphAction
        case .critical: l10n.statusGlyphCritical
        }
    }

    var content: Color {
        switch self {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        case .critical: NozirColor.criticalContent
        }
    }

    var container: Color {
        switch self {
        case .good: NozirColor.goodContainer
        case .attention: NozirColor.attentionContainer
        case .action: NozirColor.actionContainer
        case .critical: NozirColor.criticalContainer
        }
    }
}
