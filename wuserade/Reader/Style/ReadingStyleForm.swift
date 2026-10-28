// Minimum iOS 17.
//  The reading-style rows: size, line spacing, face, a heavier verse face, and a reset. Used by the Aa sheet
//  (and popover) and pushed from Settings. Every change shows at once in the poem behind it.

import SwiftUI

struct ReadingStyleForm: View {
    @AppStorage(ReadingStyle.Key.sizeStep) private var sizeStep = 0
    @AppStorage(ReadingStyle.Key.leading) private var leading: ReadingStyle.Leading = .book
    @AppStorage(ReadingStyle.Key.face) private var face: ReadingStyle.Face = .alegreya
    @AppStorage(ReadingStyle.Key.bold) private var bold = false

    var body: some View {
        Form {
            Section {
                StyleRow(label: String(localized: "Инагъыр")) {
                    TextSizeControl(step: $sizeStep)
                }
                StyleRow(label: OwnerCopy.lineSpacing) {
                    Picker(OwnerCopy.lineSpacing, selection: $leading) {
                        ForEach(ReadingStyle.Leading.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                StyleRow(label: String(localized: "Тхыпхъэр")) {
                    Picker("Тхыпхъэр", selection: $face) {
                        ForEach(ReadingStyle.Face.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle("ПӀащэу", isOn: $bold)
                    .tint(Palette.accent)
                    .foregroundStyle(Palette.ink)
                    .listRowBackground(Palette.cellElevated)
            }
            Section {
                Button("Зэрыщытам хуэгъэкӀуэжын", action: reset)
                    .foregroundStyle(Palette.ink)
                    .listRowBackground(Palette.cellElevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.pageElevated)
        .textCase(nil)
    }

    private func reset() {
        sizeStep = 0
        leading = .book
        face = .alegreya
        bold = false
    }
}

#Preview {
    ReadingStyleForm()
}
