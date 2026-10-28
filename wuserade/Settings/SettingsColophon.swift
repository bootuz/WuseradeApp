// Minimum iOS 17.
//  The last thing in Settings, like a book's colophon: the wordmark, Адыгэбзэ Хасэ and the version.

import SwiftUI

struct SettingsColophon: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: Space.one) {
            Text("Усэрадэ")
                .serif(.wordmark)
                .foregroundStyle(Palette.ink)
            Text("Адыгэбзэ Хасэ")
                .serif(.authorLine)
                .foregroundStyle(Palette.inkSecondary)
            Text(version)
                .font(.caption)
                .foregroundStyle(Palette.inkTertiary)
                .padding(.top, Space.two)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.four)
        .accessibilityElement(children: .combine)
    }
}
