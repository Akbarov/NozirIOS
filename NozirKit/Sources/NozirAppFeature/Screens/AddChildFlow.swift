import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P03 → P03b → P04, full screen. P04 has no way back, only out: the child exists by then.
struct AddChildFlow: View {
    enum Step: Hashable {
        case rules(ChildDraft)
        case pairing(Child)
    }

    private let model: SignedInModel
    private let onClose: () -> Void
    @State private var path: [Step] = []
    @State private var addModel: AddChildModel
    @Environment(\.l10n) private var l10n

    init(model: SignedInModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _addModel = State(initialValue: model.makeAddChildModel())
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .accessibilityLabel(l10n.contentDescriptionBack)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            AddChildView(model: addModel) { draft in
                path.append(.rules(draft))
            }
            .toolbar { closeButton }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .rules(let draft):
                    NewChildRulesView(model: model.makeRulesModel(draft)) { child in
                        path.append(.pairing(child))
                    }
                    .toolbar { closeButton }
                case .pairing(let child):
                    PairingView(model: model.makePairingModel(child), onFinished: onClose)
                        .navigationBarBackButtonHidden()
                        .toolbar { closeButton }
                }
            }
        }
    }
}
