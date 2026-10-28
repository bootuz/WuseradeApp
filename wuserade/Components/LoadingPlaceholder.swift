// Minimum iOS 17.
//  A first load: square hairline bars shaped like the content, not `.redacted` (which rounds them),
//  and no spinner over content. The bars do not animate.

import SwiftUI

struct LoadingPlaceholder: View {
    enum Kind { case poemRows, nameRows, reader }

    var kind: Kind = .poemRows
    var count = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch kind {
            case .poemRows, .nameRows:
                ForEach(0..<count, id: \.self) { index in
                    VStack(alignment: .leading, spacing: Space.two) {
                        bar(width: [0.55, 0.42, 0.62, 0.38, 0.5, 0.46][index % 6])
                        if kind == .poemRows {
                            bar(width: 0.34, height: 10)
                        }
                    }
                    .padding(.vertical, Space.three)
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
            case .reader:
                bar(width: 0.45, height: 18)
                bar(width: 0.35).padding(.top, Space.two)
                VStack(alignment: .leading, spacing: Space.three) {
                    ForEach(0..<8, id: \.self) { index in
                        bar(width: [0.8, 0.66, 0.86, 0.6, 0.74, 0.7, 0.82, 0.58][index])
                    }
                }
                .padding(.top, Space.eight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func bar(width fraction: CGFloat, height: CGFloat = 12) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(Palette.hairline)
                .frame(width: proxy.size.width * fraction, height: height)
        }
        .frame(height: height)
    }
}

#Preview {
    LoadingPlaceholder()
        .padding(.horizontal, Space.readingMargin)
        .background(Palette.page)
}
