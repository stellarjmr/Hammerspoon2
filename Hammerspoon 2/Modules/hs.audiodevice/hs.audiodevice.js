//
//  hs.audiodevice.js
//  Hammerspoon 2
//

"use strict";

// one-to-many emitter for hs.audiodevice module-level events.
// All listeners receive every event; filtering by type is the caller's responsibility.
class AudioDeviceModuleWatcherEmitter {
    #listeners = []

    constructor() {}

    #handleEvent(event) {
        var listeners = this.#listeners.slice();
        const length = listeners.length;

        for (var i = 0; i < length; i++) {
            listeners[i].apply(null, [event]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.audiodevice.addWatcher(): The provided handler must be a function")
        }

        if (this.#listeners.includes(listener)) {
            console.error("hs.audiodevice.addWatcher(): The provided handler is already registered.")
            return;
        }

        if (this.#listeners.length === 0) {
            hs.audiodevice._addWatcher((event) => { this.#handleEvent(event) });
        }

        this.#listeners.push(listener);
    }

    removeListener(listener) {
        var idx = this.#listeners.indexOf(listener);

        if (idx > -1) {
            this.#listeners.splice(idx, 1);
        }

        if (this.#listeners.length === 0) {
            hs.audiodevice._removeWatcher();
        }
    }
}

// one-to-many emitter for per-device events.
// All listeners receive every event; filtering by type is the caller's responsibility.
class AudioDeviceWatcherEmitter {
    #device
    #listeners = []

    constructor(device) {
        this.#device = device;
    }

    #handleEvent(event) {
        var listeners = this.#listeners.slice();
        const length = listeners.length;

        for (var i = 0; i < length; i++) {
            listeners[i].apply(null, [event]);
        }
    }

    on(listener) {
        if (typeof listener !== 'function') {
            throw new Error("hs.audiodevice device.addWatcher(): The provided handler must be a function")
        }

        if (this.#listeners.includes(listener)) {
            console.error("hs.audiodevice device.addWatcher(): The provided handler is already registered.")
            return;
        }

        if (this.#listeners.length === 0) {
            this.#device._addWatcher((event) => { this.#handleEvent(event) });
        }

        this.#listeners.push(listener);
    }

    removeListener(listener) {
        var idx = this.#listeners.indexOf(listener);

        if (idx > -1) {
            this.#listeners.splice(idx, 1);
        }

        if (this.#listeners.length === 0) {
            this.#device._removeWatcher();
        }
    }
}

// Store an instance of the module-level Watcher/Emitter in a Swift-retained property so it is not garbage collected.
hs.audiodevice._watcherEmitter = new AudioDeviceModuleWatcherEmitter();

// Factory for per-device emitters; called lazily from Swift when the first watcher is registered on a device.
/// SKIP_DOCS
hs.audiodevice._makeDeviceEmitter = function(device) {
    return new AudioDeviceWatcherEmitter(device);
};
