import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P03 → P03b → P04, full screen. P04 has no way back: the child exists by then.
struct AddChildFlow: View {
    enum Step: Hashable {
        case rules(ChildDraft)
        case pairing(UUID)
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

    var body: some View {
        NavigationStack(path: $path) {
            AddChildView(model: addModel) { draft in
                path.append(.rules(draft))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(l10n.contentDescriptionBack)
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .rules(let draft):
                    NewChildRulesView(model: model.makeRulesModel(draft)) { child in
                        path.append(.pairing(child.id))
                    }
                case .pairing(let id):
                    if let child = model.family.child(id) {
                        PairingView(model: model.makePairingModel(child), onFinished: onClose)
                            .navigationBarBackButtonHidden()
                    }
                }
            }
        }
    }
}
