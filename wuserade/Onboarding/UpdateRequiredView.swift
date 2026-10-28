// Minimum iOS 17.
//  A full-screen cover that cannot be dismissed, for when the back end's minimum version is above this build.
//  The app presents it when `meta/content.minimumAppVersion` is above this build.

import SwiftUI

struct UpdateRequiredView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(spacing: Space.four) {
                Lozenge(kind: .asterism, scale: 2)
                Text("Усэрадэр зэхъуэкӀын хуейщ")
                    .serif(.headerTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Мы версиэр иджыри къигъэсэбэпын хъункъым. App Store-м щызэхъуэкӀыж.")
                    .serif(.prose)
                    .foregroundStyle(Palette.inkSecondary)
                Button("ЗэхъуэкӀын") { openURL(AppLinks.appStore) }
                    .buttonStyle(.primaryCapsule)
                    .padding(.top, Space.two)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Space.readingMargin)
            .padding(.top, Space.sixteen)
        }
        .background(Palette.page)
        .interactiveDismissDisabled()
    }
}

#Preview {
    UpdateRequiredView()
}
