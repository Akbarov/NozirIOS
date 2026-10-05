import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// The signed-in app: Home (P05 comes in 2b) and Profile. Statistics and
/// Location tabs arrive with their slices.
struct SignedInView: View {
    enum ProfileStep: Hashable {
        case child(Child)
        case pairing(Child)
    }

    @State private var model: SignedInModel
    @State private var profilePath: [ProfileStep] = []
    @Environment(\.l10n) private var l10n
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    init(model: SignedInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack {
                HomePlaceholderView()
            }
            .tabItem { Label(l10n.tabHome, systemImage: "house") }
            .tag(SignedInModel.Tab.home)

            NavigationStack(path: $profilePath) {
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0)) },
                    onPair: { profilePath.append(.pairing($0)) }
                )
                .navigationDestination(for: ProfileStep.self) { step in
                    switch step {
                    case .child(let child):
                        ChildDetailsView(model: model.makeDetailsModel(child), onRemoved: { profilePath.removeAll() })
                    case .pairing(let child):
                        PairingView(model: model.makePairingModel(child), onFinished: { profilePath.removeAll() })
                    }
                }
            }
            .tabItem { Label(l10n.tabProfile, systemImage: "person.crop.circle") }
            .tag(SignedInModel.Tab.profile)
        }
        .tint(NozirColor.primary)
        .fullScreenCover(isPresented: $model.isAddingChild) {
            AddChildFlow(model: model, onClose: {
                profilePath.removeAll()
                model.finishAddChild()
            })
                // Said again for the cover, so it cannot fall back to the defaults.
                .environment(\.l10n, l10n)
                .environment(\.locale, locale)
        }
        .task(id: scenePhase == .active) { if scenePhase == .active { await model.start() } }
    }
}
