//
//  OSAScriptXPCService.swift
//  HammerspoonOSAScriptHelper
//

import Foundation
import OSAKit

/// XPC service object exported to the main app.
///
/// One instance is created per XPC connection (the listener delegate does
/// `newConnection.exportedObject = OSAScriptXPCService()`).
///
/// `OSAScript` requires the **main thread**; every call is therefore dispatched
/// to `DispatchQueue.main` before any OSA work is done.
class HSOSAScriptXPCService: NSObject, HSOSAScriptServiceProtocol {

    func execute(source: String,
                 language languageName: String,
                 withReply reply: @escaping (Bool, String?, String?) -> Void) {
        // OSAScript is not thread-safe and must run on the main thread.
        DispatchQueue.main.async {
            self.runScript(source: source, languageName: languageName, reply: reply)
        }
    }

    // MARK: - Private

    private func runScript(source: String,
                           languageName: String,
                           reply: @escaping (Bool, String?, String?) -> Void) {
        // 1. Look up the OSA language.
        guard let language = OSALanguage(forName: languageName) else {
            reply(false, nil, "OSA language not found: \(languageName)")
            return
        }

        // 2. Create and compile the script.
        let script = OSAScript(source: source, language: language)

        var compileError: NSDictionary? = nil
        guard script.compileAndReturnError(&compileError) else {
            reply(false, nil, errorMessage(from: compileError, fallback: "Compilation failed"))
            return
        }

        // 3. Execute the script.
        var execError: NSDictionary? = nil
        guard let result = script.executeAndReturnError(&execError) else {
            reply(false, nil, errorMessage(from: execError, fallback: "Execution failed"))
            return
        }

        // 4. Convert the result descriptor to a JSON-serialisable value.
        let rawString  = result.stringValue ?? ""
        let jsonObject = result.toJSONCompatibleObject()

        do {
            let jsonData   = try JSONSerialization.data(
                withJSONObject: jsonObject, options: [.fragmentsAllowed])
            let jsonString = String(data: jsonData, encoding: .utf8)
            reply(true, jsonString, rawString)
        } catch {
            // Serialisation failed (unexpected); fall back to JSON-encoded raw string.
            if let fallbackData = try? JSONSerialization.data(
                withJSONObject: rawString, options: [.fragmentsAllowed]),
               let fallbackString = String(data: fallbackData, encoding: .utf8) {
                reply(true, fallbackString, rawString)
            } else {
                // Extremely unlikely: as a last resort, return an empty JSON string.
                reply(true, "\"\"", rawString)
            }
        }
    }

    /// Extract a human-readable error message from an OSA/AppleScript error dictionary.
    private func errorMessage(from dict: NSDictionary?, fallback: String) -> String {
        guard let dict else { return fallback }
        // OSA/AppleScript error dicts use various keys depending on the engine.
        return (dict[NSLocalizedDescriptionKey] as? String)
            ?? (dict["NSAppleScriptErrorMessage"] as? String)
            ?? (dict["OSAScriptErrorMessage"] as? String)
            ?? (dict.description)
    }
}
