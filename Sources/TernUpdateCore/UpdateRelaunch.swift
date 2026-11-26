import Foundation

public enum UpdateRelaunch {
    public static let argument = "--background-update-relaunch"

    public static func isRequested(arguments: [String]) -> Bool {
        arguments.contains(argument)
    }

    public static func openArguments(for application: URL) -> [String] {
        ["-g", application.path, "--args", argument]
    }
}
