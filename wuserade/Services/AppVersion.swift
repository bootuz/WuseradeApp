import Foundation

/// This build's version and the minimum-version check behind the "please update" screen.
enum AppVersion {
    /// The version shown in the App Store, e.g. "1.4".
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Whether `current` is at least `minimum`, comparing dot-separated numbers part by part
    /// ("1.10" is above "1.5"; a missing part counts as 0, so "1.5" equals "1.5.0").
    ///
    /// No minimum, or one that is blank or not made of numbers (a typo in Firestore), means supported:
    /// a bad value must never lock everyone out of the app.
    static func isSupported(current: String, minimum: String?) -> Bool {
        guard let required = numbers(in: minimum), let installed = numbers(in: current) else { return true }
        for index in 0 ..< max(required.count, installed.count) {
            let have = index < installed.count ? installed[index] : 0
            let need = index < required.count ? required[index] : 0
            if have != need { return have > need }
        }
        return true
    }

    /// "1.10.2" becomes [1, 10, 2]. Nil when the string is blank or any part is not a plain number.
    private static func numbers(in version: String?) -> [Int]? {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty else { return nil }
        var numbers: [Int] = []
        for part in version.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        return numbers
    }
}
