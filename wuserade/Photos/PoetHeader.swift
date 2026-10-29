// Minimum iOS 17.
//  A poet's page header: the round portrait, then the name, the count line and the send area, centred.
//  The portrait loads in the background; until it arrives, or if it never does, the initials show.

import SwiftUI

struct PoetHeader: View {
    let poet: Author
    /// Nil until the catalog has loaded.
    let count: Int?

    @Environment(Library.self) private var library
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The photo that has loaded, and the URL it came from.
    @State private var loaded: (url: URL, image: CGImage)?

    private var photoURL: URL? { library.photoURL(ofPoet: poet.id) }

    /// Never a photo that belongs to another URL than the poet's current one.
    private var image: CGImage? {
        guard let photoURL, let loaded, loaded.url == photoURL else { return nil }
        return loaded.image
    }

    var body: some View {
        VStack(spacing: 0) {
            portrait
            Text(poet.name)
                .serif(.headerTitle)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Space.six)
            if let count {
                Text("\(count) \(OwnerCopy.countNoun)")
                    .serif(.sectionLabel)
                    .foregroundStyle(Palette.inkSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Space.two)
            }
            SendPhotoArea(poet: poet, hasPhoto: photoURL != nil)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Space.two)
        .padding(.bottom, Space.three)
        .task(id: photoURL) {
            guard let photoURL, loaded?.url != photoURL,
                  let photo = try? await PortraitLoader.image(at: photoURL) else { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.25)) {
                loaded = (photoURL, photo)
            }
        }
    }

    /// A photo is one image to VoiceOver, with the report offered as an action. The initials say nothing the
    /// name below does not, so they are hidden.
    @ViewBuilder
    private var portrait: some View {
        let view = PoetPortrait(initials: PoetInitials.of(poet.name), image: image)
        if image != nil {
            view
                .accessibilityElement()
                .accessibilityLabel(OwnerCopy.photoOfPoet)
                .accessibilityAddTraits(.isImage)
                .contextMenu {
                    Button(OwnerCopy.reportPhoto, action: reportPhoto)
                }
                .accessibilityAction(named: OwnerCopy.reportPhoto, reportPhoto)
        } else {
            view.accessibilityHidden(true)
        }
    }

    private func reportPhoto() {
        openURL(AppLinks.photoReport(poetName: poet.name, poetID: poet.id))
    }
}
