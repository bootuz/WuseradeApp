// Minimum iOS 17.
//  The one-time invitation to the morning poem, under the day's page on Home: a line of text, turn on and not now.
//  Either answer puts it away for good, including a turn on that iOS permission then refuses (Settings explains).

import SwiftUI

struct MorningInvitationCard: View {
    @Environment(MorningPoemController.self) private var morning

    var body: some View {
        VStack(alignment: .leading, spacing: Space.four) {
            Text(OwnerCopy.morningInvitation)
                .serif(.prose)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Space.three) { buttons }
                VStack(alignment: .leading, spacing: Space.three) { buttons }
            }
        }
        .padding(Space.six)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cell, in: .rect(cornerRadius: Space.four))
    }

    @ViewBuilder private var buttons: some View {
        Button(OwnerCopy.turnOn) {
            answer("accepted")
            Task { await morning.setEnabled(true) }
        }
        .buttonStyle(.primaryCapsule)

        Button(OwnerCopy.notNow) {
            answer("dismissed")
        }
        .buttonStyle(.secondaryCapsule)
    }

    private func answer(_ answer: String) {
        var days = VisitDays()
        days.invitationDone = true
        AnalyticsManager.shared.invitation(answer)
    }
}
