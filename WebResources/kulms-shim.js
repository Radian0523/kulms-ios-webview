// kulms-shim.js — chrome.* API shim for WKWebView
// This script is injected BEFORE any extension content scripts.
// It creates a fake `chrome` namespace that bridges to Swift via
// webkit.messageHandlers.

(function () {
  "use strict";

  // Prevent double-injection
  if (window.__kulmsShimInstalled) return;
  window.__kulmsShimInstalled = true;

  // ---- callback registry for async Swift responses ----
  var _cbId = 0;
  var _callbacks = {};

  window.__kulmsStorageCallback = function (id, data) {
    var cb = _callbacks[id];
    if (cb) {
      delete _callbacks[id];
      cb(data);
    }
  };

  function postToSwift(action, payload, callback) {
    var id = String(++_cbId);
    if (callback) _callbacks[id] = callback;
    var msg = Object.assign({ action: action, callbackId: id }, payload);
    try {
      webkit.messageHandlers.kulmsStorage.postMessage(msg);
    } catch (e) {
      console.warn("[kulms-shim] postMessage failed:", e);
      if (callback) callback({});
    }
  }

  // ---- chrome.storage ----
  var _changeListeners = [];

  var storageLocal = {
    get: function (keys, callback) {
      var keyList;
      if (keys === null || keys === undefined) {
        keyList = null; // get all
      } else if (typeof keys === "string") {
        keyList = [keys];
      } else if (Array.isArray(keys)) {
        keyList = keys;
      } else {
        // object with defaults
        keyList = Object.keys(keys);
      }
      postToSwift("get", { keys: keyList }, function (result) {
        // merge defaults if keys was an object
        if (keys && typeof keys === "object" && !Array.isArray(keys)) {
          var merged = {};
          for (var k in keys) {
            merged[k] = result.hasOwnProperty(k) ? result[k] : keys[k];
          }
          result = merged;
        }
        if (callback) callback(result);
      });
    },
    set: function (items, callback) {
      postToSwift("set", { items: items }, function () {
        // fire onChanged listeners
        var changes = {};
        for (var key in items) {
          changes[key] = { newValue: items[key] };
        }
        for (var i = 0; i < _changeListeners.length; i++) {
          try {
            _changeListeners[i](changes, "local");
          } catch (e) {}
        }
        if (callback) callback();
      });
    },
    remove: function (keys, callback) {
      var keyList = typeof keys === "string" ? [keys] : keys;
      postToSwift("remove", { keys: keyList }, function () {
        if (callback) callback();
      });
    },
    clear: function (callback) {
      postToSwift("clear", {}, function () {
        if (callback) callback();
      });
    }
  };

  var storageOnChanged = {
    addListener: function (fn) {
      _changeListeners.push(fn);
    },
    removeListener: function (fn) {
      _changeListeners = _changeListeners.filter(function (l) {
        return l !== fn;
      });
    },
    hasListener: function (fn) {
      return _changeListeners.indexOf(fn) !== -1;
    }
  };

  // ---- chrome.runtime ----
  var _messageListeners = [];

  var runtime = {
    id: "kulms-ios-app",
    getManifest: function () {
      return { version: window.__kulmsAppVersion || "1.0.0" };
    },
    getURL: function (path) {
      return "kulms-resource://" + path;
    },
    onMessage: {
      addListener: function (fn) {
        _messageListeners.push(fn);
      },
      removeListener: function (fn) {
        _messageListeners = _messageListeners.filter(function (l) {
          return l !== fn;
        });
      },
      hasListener: function (fn) {
        return _messageListeners.indexOf(fn) !== -1;
      }
    },
    sendMessage: function (message, callback) {
      // Textbook search etc. — Phase 2. Return empty result.
      if (callback) {
        setTimeout(function () {
          callback(undefined);
        }, 0);
      }
    },
    lastError: null
  };

  // ---- chrome.i18n ----
  var i18n = {
    getMessage: function (key, substitutions) {
      // The extension's own t() function handles i18n via __kulmsOverrideMessages.
      // This fallback handles direct chrome.i18n.getMessage calls.
      if (
        window.__kulmsOverrideMessages &&
        window.__kulmsOverrideMessages[key]
      ) {
        var entry = window.__kulmsOverrideMessages[key];
        var msg = entry.message;
        if (substitutions && entry.placeholders) {
          var subs = Array.isArray(substitutions)
            ? substitutions
            : [substitutions];
          Object.keys(entry.placeholders).forEach(function (name) {
            var idx =
              parseInt(
                entry.placeholders[name].content.replace(/\$/g, "")
              ) - 1;
            if (idx >= 0 && idx < subs.length) {
              msg = msg.replace(
                new RegExp("\\$" + name.toUpperCase() + "\\$", "g"),
                subs[idx]
              );
            }
          });
        }
        return msg;
      }
      return key;
    },
    getUILanguage: function () {
      return navigator.language || "ja";
    }
  };

  // ---- Override fetch for kulms-resource:// URLs ----
  var _originalFetch = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === "string" ? input : input.url;
    if (url && url.indexOf("kulms-resource://") === 0) {
      var resourcePath = url.replace("kulms-resource://", "");
      // Resource data is embedded inline by ContentScriptInjector
      if (
        window.__kulmsResourceData &&
        window.__kulmsResourceData[resourcePath]
      ) {
        var data = window.__kulmsResourceData[resourcePath];
        var blob = new Blob([data], { type: "application/json" });
        return Promise.resolve(new Response(blob, { status: 200 }));
      }
      return Promise.resolve(
        new Response("", { status: 404, statusText: "Not Found" })
      );
    }
    return _originalFetch.apply(this, arguments);
  };

  // ---- Assemble chrome namespace ----
  window.chrome = {
    storage: {
      local: storageLocal,
      onChanged: storageOnChanged
    },
    runtime: runtime,
    i18n: i18n
  };

  // ---- __kulmsAlive always returns true in-app ----
  window.__kulmsAlive = function () {
    return true;
  };

  console.log("[kulms-shim] chrome.* API shim installed");
})();
