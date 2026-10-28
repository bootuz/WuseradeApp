// Minimum iOS 17.
//  What Share hands to the share sheet: the share image, rendered only when a destination asks for it,
//  and the plain text (title, poet, a blank line, the verse).

import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct PoemShare: Transferable {
    let poem: Poem
    var dark = false

    var text: String {
        let summary = PoemSummary(poem)
        let title = summary.isUntitled ? summary.firstLine + "…" : summary.title
        return "\(title)\n\(summary.author.name)\n\n\(poem.content.kbd)"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { share in
            try await share.pngData()
        }
        ProxyRepresentation(exporting: \.text)
    }

    @MainActor
    private func pngData() throws -> Data {
        let card = PoemShareCard(poem: poem)
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = card.scale
        guard let image = renderer.uiImage, let data = image.pngData() else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}
