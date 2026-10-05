import SwiftUI

/// P01 → P02. Both Welcome buttons lead to sign-in: on iOS there is no
/// sign-up separate from signing in through the bot.
struct SignedOutFlow: View {
    let environment: AppEnvironment
    @State private var showsSignIn = false

    var body: some View {
        NavigationStack {
            WelcomeView(onStart: { showsSignIn = true }, onSignIn: { showsSignIn = true })
                .navigationDestination(isPresented: $showsSignIn) {
                    SignInView(model: environment.makeSignInModel())
                }
        }
    }
}
