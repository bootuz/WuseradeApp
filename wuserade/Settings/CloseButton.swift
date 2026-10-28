// Minimum iOS 17.
//  Closes a sheet: the system close button from iOS 26, an xmark labelled in Kabardian before it.

import SwiftUI

struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if #available(iOS 26, *) {
            Button(role: .close) { dismiss() }
        } else {
            Button {
                dismiss()
            } label: {
                Label(OwnerCopy.close, systemImage: "xmark")
            }
        }
    }
}
