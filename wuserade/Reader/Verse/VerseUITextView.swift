// Minimum iOS 17.
//  The verse's text view. Copying a selection plays the success haptic and VoiceOver announces it; the menu
//  closing is the only other confirmation.

import UIKit

final class VerseUITextView: UITextView {
    private let feedback = UINotificationFeedbackGenerator()

    override func copy(_ sender: Any?) {
        super.copy(sender)
        feedback.notificationOccurred(.success)
        UIAccessibility.post(notification: .announcement, argument: "Копие тепхащ")
    }
}
