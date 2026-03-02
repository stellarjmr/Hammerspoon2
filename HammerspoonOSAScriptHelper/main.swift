//
//  main.swift
//  HammerspoonOSAScriptHelper
//
//  Standard XPC service entry point.
//

import Foundation

/// Accepts incoming XPC connections from the main app and vends a fresh
/// `OSAScriptXPCService` instance per connection.
class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(
            with: HSOSAScriptServiceProtocol.self)
        newConnection.exportedObject = OSAScriptXPCService()
        newConnection.resume()
        return true
    }
}

// Hold a strong reference for the lifetime of the service process.
let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
// Blocks indefinitely, processing incoming XPC messages.
listener.resume()
