import SwiftUI
import SFSafeSymbols

/// Shown over the whole app when `meta/content.minimumAppVersion` is above this build's version.
struct UpdateRequiredView: View {
    var body: some View {
        ContentUnavailableView {
            // TODO(owner): copy. Meaning: "Please update the app".
            Label("Усэрадэр зэхъуэкlын хуейщ", systemSymbol: SFSymbol.arrowDownAppFill)
        } description: {
            // TODO(owner): copy. Meaning: "This version is too old and no longer works. Update it in the App Store."
            Text("Мы версиэр иджыри къигъэсэбэпын хъункъым. App Store-м щызэхъуэкlыж.")
        } actions: {
            Link(destination: URL(string: "https://apple.co/3OWuu5b")!) {
                // TODO(owner): copy. Meaning: "Update".
                Text("Зэхъуэкlын")
                    .font(.headline)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.primary, in: Capsule())
            }
        }
        .background(Color(.systemBackground))
    }
}

#if DEBUG
#Preview {
    UpdateRequiredView()
}
#endif
