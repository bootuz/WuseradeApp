// Minimum iOS 17.
//  The morning poem in Settings: a toggle, and the time while it is on. Turning it on asks for notification
//  permission. When iOS does not allow Wuserade's notifications, a line says so and a row opens iOS Settings.

import SwiftUI

struct MorningPoemSection: View {
    @Environment(MorningPoemController.self) private var morning
    @Environment(\.openURL) private var openURL
    /// True from the tap until the permission prompt is answered, so the toggle shows the tap rather than
    /// flicking back while the prompt is up.
    @State private var isTurningOn = false

    var body: some View {
        Section {
            Toggle(isOn: isOn) {
                Text(OwnerCopy.morningPoem).foregroundStyle(Palette.ink)
            }
            .tint(Palette.accent)
            .disabled(isTurningOn)

            if morning.enabled {
                DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                    Text(OwnerCopy.morningPoemTime).foregroundStyle(Palette.ink)
                }
            }

            if morning.permissionDenied {
                Text(OwnerCopy.notificationsOff)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkSecondary)
                Button {
                    if let settings = URL(string: UIApplication.openSettingsURLString) {
                        openURL(settings)
                    }
                } label: {
                    SettingsRowLabel(title: OwnerCopy.openSettings, systemImage: "bell.slash", leavesApp: true)
                }
            }
        }
    }

    private var isOn: Binding<Bool> {
        Binding {
            isTurningOn || morning.enabled
        } set: { on in
            if on { isTurningOn = true }
            Task {
                await morning.setEnabled(on)
                isTurningOn = false
                AnalyticsManager.shared.morningPoem(enabled: morning.enabled)
            }
        }
    }

    /// The stored "HH:MM" as today's date at that time, and back.
    private var time: Binding<Date> {
        Binding {
            let (hour, minute) = MorningSchedule.parse(morning.notifyAt) ?? (8, 0)
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let hhmm = String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
            Task { await morning.setTime(hhmm) }
        }
    }
}
