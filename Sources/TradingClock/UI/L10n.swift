import Foundation

/// Localized UI strings (menu titles etc.), following the system language.
/// Resolution order: main bundle (bundled .app, .lproj copied into
/// Contents/Resources) → module bundle (bare `swift run`).
enum L10n {
    static func t(_ key: String) -> String {
        let fromMain = NSLocalizedString(
            key, tableName: "Localizable", bundle: .main, value: "", comment: "")
        if !fromMain.isEmpty && fromMain != key {
            return fromMain
        }
        #if SWIFT_PACKAGE
        let fromModule = NSLocalizedString(
            key, tableName: "Localizable", bundle: .module, value: "", comment: "")
        if !fromModule.isEmpty && fromModule != key {
            return fromModule
        }
        #endif
        return key
    }
}
