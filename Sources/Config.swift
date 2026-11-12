import Foundation

enum HotKeyModifier: String {
    case option, control
}

enum ScreenChoice: String {
    case mouse, focused
}

/// User settings read from ~/.config/simple-task-switcher/config.
/// Ghostty-style format: `key = value` lines, `#` comments, lists by repeating the key.
struct Config {
    var hotKeyModifier: HotKeyModifier = .option
    var screen: ScreenChoice = .mouse
    var showHiddenApps = true
    var showWindowlessApps = true
    var exclude: Set<String> = []
    var launchAtLogin = false
    var fontSize = 15

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/simple-task-switcher/config")

    /// Missing file means defaults; it is not an error.
    static func load() -> Config {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return Config() }
        return parse(text)
    }

    /// Invalid lines are skipped and logged with their line number; they never abort parsing.
    static func parse(_ text: String) -> Config {
        var config = Config()
        // isNewline also matches "\r\n", which Swift treats as a single Character.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let equals = line.firstIndex(of: "=") else {
                log("config line \(index + 1): missing '='")
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let problem = config.apply(key: key, value: value) {
                log("config line \(index + 1): \(problem)")
            }
        }
        return config
    }

    /// Returns a description of the problem, or nil if the line was applied.
    private mutating func apply(key: String, value: String) -> String? {
        let invalid = "invalid value '\(value)' for '\(key)'"
        switch key {
        case "hotkey-modifier":
            guard let modifier = HotKeyModifier(rawValue: value) else { return invalid }
            hotKeyModifier = modifier
        case "screen":
            guard let choice = ScreenChoice(rawValue: value) else { return invalid }
            screen = choice
        case "show-hidden-apps":
            guard let flag = Self.bool(value) else { return invalid }
            showHiddenApps = flag
        case "show-windowless-apps":
            guard let flag = Self.bool(value) else { return invalid }
            showWindowlessApps = flag
        case "exclude":
            guard !value.isEmpty else { return invalid }
            exclude.insert(value)
        case "launch-at-login":
            guard let flag = Self.bool(value) else { return invalid }
            launchAtLogin = flag
        case "font-size":
            guard let size = Int(value), (10...40).contains(size) else { return invalid }
            fontSize = size
        default:
            return "unknown key '\(key)'"
        }
        return nil
    }

    private static func bool(_ value: String) -> Bool? {
        switch value {
        case "true": return true
        case "false": return false
        default: return nil
        }
    }

    /// Written by "Open Config" when the file does not exist yet.
    static let template = """
        # Simple Task Switcher configuration.
        # Format: `key = value`. Lines starting with # are comments.
        # Every key is optional; the values below are the defaults.
        # After editing, use "Reload Config" in the menu bar icon.

        # Modifier held with Tab to open the switcher: option or control.
        # hotkey-modifier = option

        # Screen where the panel appears: mouse (pointer) or focused (frontmost window).
        # screen = mouse

        # Show apps hidden with Cmd+H.
        # show-hidden-apps = true

        # Show apps that have no windows (e.g. Finder with every window closed).
        # show-windowless-apps = true

        # Never list these apps (bundle IDs). Repeat the key for each one.
        # exclude = com.apple.finder
        # exclude = com.apple.systempreferences

        # Start at login. Only applies when the app runs from /Applications.
        # launch-at-login = false

        # Font size of the list (10-40).
        # font-size = 15

        """
}
