// Minimum iOS 17.
//  The small widget's one setting: the short poem of the day (the default) or the day's poem. App Intents
//  metadata takes only literals, so this file is the one place for these owner-copy slots. The widget's name,
//  '[owner copy: widget: a short poem]', also appears as `WidgetCopy.smallName`: change both together.

import AppIntents

struct SmallPoemIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "[owner copy: widget: a short poem]"

    @Parameter(title: "[owner copy: widget: a short poem]", default: .shortPoem)
    var kind: Kind

    enum Kind: String, AppEnum {
        case shortPoem, daysPoem

        static let typeDisplayRepresentation: TypeDisplayRepresentation = "[owner copy: widget: a short poem]"
        static let caseDisplayRepresentations: [Kind: DisplayRepresentation] = [
            .shortPoem: "[owner copy: short poem]",
            .daysPoem: "[owner copy: day’s poem]",
        ]

        var smallPoem: DailyEntry.SmallPoem {
            switch self {
            case .shortPoem: .shortPoem
            case .daysPoem: .daysPoem
            }
        }
    }
}
