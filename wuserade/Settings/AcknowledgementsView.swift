// Minimum iOS 17.
//  The licence of the bundled typeface, as the SIL Open Font License asks.

import SwiftUI

struct AcknowledgementsView: View {
    private let licence: String = {
        guard let url = Bundle.main.url(forResource: "Alegreya-OFL", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    var body: some View {
        ScrollView {
            Text(licence)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.four)
        }
        .background(Palette.pageElevated)
        .navigationTitle("Alegreya")
        .navigationBarTitleDisplayMode(.inline)
    }
}
