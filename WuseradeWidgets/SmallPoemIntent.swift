// Minimum iOS 17.
//  The small widget's one setting: the short poem of the day (the default) or the day's poem. App Intents
//  metadata takes only literals, so the strings repeat `WidgetCopy.smallName`, `kindShort` and `kindDay`.

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
