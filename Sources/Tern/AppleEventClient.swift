import AppKit
import Carbon

protocol AppleEventClient: Sendable {
    func perform(_ arguments: [String]) async throws -> [String]
}

/// A fixed script with data-only Apple Event arguments. The queue also serializes
/// tab creation and focus, and keeps retry receipts alive in the script instance.
final class DiaAppleEventClient: AppleEventClient, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.dominikbura.tern.dia")
    private var script: NSAppleScript?

    func perform(_ arguments: [String]) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if script == nil { script = NSAppleScript(source: Self.source) }
                    guard let script else { throw TernError.message("Could not prepare Dia automation.") }
                    let argv = NSAppleEventDescriptor.list()
                    for (index, value) in arguments.enumerated() { argv.insert(NSAppleEventDescriptor(string: value), at: index + 1) }
                    let parameters = NSAppleEventDescriptor.list()
                    parameters.insert(argv, at: 1)
                    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
                    event.setParam(NSAppleEventDescriptor(string: "performaction"), forKeyword: AEKeyword(keyASSubroutineName))
                    event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
                    var error: NSDictionary?
                    let result = script.executeAppleEvent(event, error: &error)
                    if let error {
                        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
                        // AppleScript's raw error can contain URL arguments. Do not surface it.
                        let text: String
                        switch number {
                        case -1743: text = "Allow Tern to control Dia in System Settings → Privacy & Security → Automation, then retry."
                        case -1712: text = "Dia did not respond in time. Retry to recover the existing tab if it was created."
                        case 7101: text = "Open a Dia window, then retry. No link was opened."
                        case 7102: text = "The Dia profile is missing or its name is ambiguous. Refresh destinations and choose its exact name."
                        case 7104: text = "Dia may already have opened this link. Check Dia, then cancel this request to avoid creating a duplicate."
                        case 7103: text = "The original Dia window or tab is no longer available. Choose a destination again."
                        default: text = "Dia automation failed (\(number)). Open Dia and retry; check Automation permission if needed."
                        }
                        throw TernError.message(text)
                    }
                    let values = (1..<(result.numberOfItems + 1)).compactMap { result.atIndex($0)?.stringValue }
                    continuation.resume(returning: values)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    static let source = #"""
    property receipts : {}
    property uncertainRequests : {}
    on performaction(argv)
      with timeout of 12 seconds
        set operation to item 1 of argv
        tell application id "company.thebrowser.dia"
          if (count of windows) is 0 then error "No window" number 7101
          set chosenWindow to window 1
          set chosenID to id of chosenWindow
          if operation is "profiles" then
            return name of every profile of chosenWindow
          end if
          if operation is "currentURL" then return {URL of active tab of chosenWindow}
          set profileName to item 2 of argv
          set matchingProfiles to every profile of chosenWindow whose name is profileName
          if (count of matchingProfiles) is not 1 then error "Missing or ambiguous profile" number 7102
          set destination to item 1 of matchingProfiles
          if operation is "switch" then
            focus destination
            return {chosenID}
          end if
          if operation is "open" then
            set requestID to item 3 of argv
            set targetURL to item 4 of argv
            set existingReceipt to missing value
            repeat with receipt in my receipts
              if item 1 of receipt is requestID then set existingReceipt to contents of receipt
            end repeat
            if existingReceipt is not missing value then
              -- Retrying a partially completed request only focuses the original tab.
              set matchingWindows to every window whose id is item 2 of existingReceipt
              if (count of matchingWindows) is not 1 then error "Window closed" number 7103
              set receiptWindow to item 1 of matchingWindows
              set matchingTabs to every tab of receiptWindow whose id is item 3 of existingReceipt
              if (count of matchingTabs) is not 1 then error "Tab closed" number 7103
              focus (item 1 of matchingTabs)
              return {item 2 of existingReceipt, item 3 of existingReceipt}
            end if
            if my uncertainRequests contains requestID then error "Uncertain delivery" number 7104
            set end of my uncertainRequests to requestID
            set createdTab to make new tab at end of tabs of destination with properties {URL:targetURL}
            set createdID to id of createdTab
            set end of my receipts to {requestID, chosenID, createdID}
            focus createdTab
            return {chosenID, createdID}
          end if
        end tell
      end timeout
      return {}
    end performaction
    """#
}
