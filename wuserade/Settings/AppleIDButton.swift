// Minimum iOS 17.
//  The system "Sign in with Apple" button, so it looks the way Apple requires.

import AuthenticationServices
import SwiftUI

/// Its tap goes to `action` instead of starting a request of its own: `AppleSignInCoordinator` runs the request,
/// which SwiftUI's `SignInWithAppleButton` cannot hand over.
struct AppleIDButton: UIViewRepresentable {
    static let cornerRadius: CGFloat = 25

    let style: ASAuthorizationAppleIDButton.Style
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: style)
        button.cornerRadius = Self.cornerRadius
        let coordinator = context.coordinator
        button.addAction(UIAction { _ in coordinator.action() }, for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
    }

    /// Fills the width it is offered, which the UIKit button would not do by itself.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ASAuthorizationAppleIDButton, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 280, height: Space.signinHeight))
    }

    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }
    }
}
