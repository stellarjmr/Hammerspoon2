//
//  HSOSAScriptModule.swift
//  Hammerspoon 2
//

import Foundation
import JavaScriptCore

// MARK: - JavaScript API

/// JavaScript-visible API for `hs.osascript`.
///
/// All functions return a `Promise` that **always resolves** (never rejects)
/// with `{ success: Bool, result: Any, raw: String }`, matching v1 behaviour
/// while being async-friendly.
@objc protocol HSOSAScriptModuleAPI: JSExport {
    /// Run an AppleScript string.
    @objc func applescript(_ source: String) -> JSPromise?

    /// Run an OSA JavaScript string.
    @objc func javascript(_ source: String) -> JSPromise?

    /// Read a file and run its contents as AppleScript.
    @objc func applescriptFromFile(_ path: String) -> JSPromise?

    /// Read a file and run its contents as OSA JavaScript.
    @objc func javascriptFromFile(_ path: String) -> JSPromise?

    /// Low-level entry point.  `language` must be `"AppleScript"` or `"JavaScript"`.
    @objc func _execute(_ source: String, _ language: String) -> JSPromise?
}

// MARK: - Implementation

@_documentation(visibility: private)
@MainActor
@objc class HSOSAScriptModule: NSObject, HSModuleAPI, HSOSAScriptModuleAPI {
    var name = "hs.osascript"

    private let runner = HSOSAScriptRunner()

    // MARK: - Module lifecycle

    override required init() { super.init() }

    func shutdown() {
        runner.shutdown()
    }

    deinit {
        print("Deinit of \(name)")
    }

    // MARK: - Public API

    @objc func applescript(_ source: String) -> JSPromise? {
        return _execute(source, "AppleScript")
    }

    @objc func javascript(_ source: String) -> JSPromise? {
        return _execute(source, "JavaScript")
    }

    @objc func applescriptFromFile(_ path: String) -> JSPromise? {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return resolvedFailurePromise(raw: "Failed to read file: \(path)")
        }
        return _execute(source, "AppleScript")
    }

    @objc func javascriptFromFile(_ path: String) -> JSPromise? {
        guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
            return resolvedFailurePromise(raw: "Failed to read file: \(path)")
        }
        return _execute(source, "JavaScript")
    }

    @objc func _execute(_ source: String, _ language: String) -> JSPromise? {
        guard let context = JSContext.current() else {
            AKError("hs.osascript: _execute called outside a JS context")
            return nil
        }

        return wrapAsyncInJSPromise(in: context) { holder in
            Task { @MainActor in
                let resultDict: [String: Any]
                do {
                    let (success, resultJSON, raw) = try await self.runner.run(
                        source: source, language: language)

                    if success {
                        let parsed = Self.parseJSON(resultJSON)
                        resultDict = ["success": true, "result": parsed, "raw": raw]
                    } else {
                        resultDict = ["success": false, "result": NSNull(), "raw": raw]
                    }
                } catch {
                    resultDict = [
                        "success": false,
                        "result": NSNull(),
                        "raw": "XPC error: \(error.localizedDescription)"
                    ]
                }
                holder.resolveWith(resultDict)
            }
        }
    }

    // MARK: - Private helpers

    /// Immediately-resolved failure promise, used for synchronous errors (e.g. file not found).
    private func resolvedFailurePromise(raw: String) -> JSPromise? {
        guard let context = JSContext.current() else { return nil }
        let result: [String: Any] = ["success": false, "result": NSNull(), "raw": raw]
        return context.createResolvedPromise(with: result)
    }

    /// Deserialise a JSON string into a JS-compatible value.
    /// Returns `NSNull()` if the string is nil or unparseable.
    private static func parseJSON(_ jsonString: String?) -> Any {
        guard let jsonString,
              let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(
                  with: data, options: [.fragmentsAllowed]) else {
            return NSNull()
        }
        return parsed
    }
}
