// Minimum iOS 17.
//  Empty, offline and no-selection states: the doubled asterism (or a symbol), one complete sentence and a
//  prose body, set in the upper third of the screen and never centred vertically.

import SwiftUI

struct EmptyStateView<Action: View>: View {
    let title: String
    var message: String?
    var systemImage: String?
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: Space.four) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(Palette.inkSecondary)
                    .accessibilityHidden(true)
            } else {
                Lozenge(kind: .asterism, scale: 2)
            }
            VStack(spacing: Space.two) {
                Text(title)
                    .serif(.emptyTitle)
                    .foregroundStyle(Palette.ink)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .serif(.prose)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            action
                .padding(.top, Space.two)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.four)
        .padding(.top, Space.sixteen)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(title: String, message: String? = nil, systemImage: String? = nil) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}

#Preview {
    EmptyStateView(title: "Уигу ирихьа усэхэр мыбдеж къридзэнущ.", message: OwnerCopy.likedEmptyBody)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.page)
}
