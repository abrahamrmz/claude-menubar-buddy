import Foundation

/// One permission opencode is waiting for: `permission.asked` plus the tool call
/// that triggered it, as far as the rule needs to know it.
public struct OpenCodePermissionRequest: Equatable {
    public let id: String                 // "per_…"
    public let sessionID: String
    public let action: String             // "shell", "edit", "read", "webfetch", …
    public let resources: [String]
    public let editedFiles: [String]      // metadata.files[].file, in order
    public let patches: [String]          // metadata.files[].patch, same order
    public let callID: String?            // source.id
    public init(id: String, sessionID: String, action: String, resources: [String],
                editedFiles: [String] = [], patches: [String] = [], callID: String? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.action = action
        self.resources = resources
        self.editedFiles = editedFiles
        self.patches = patches
        self.callID = callID
    }
}

public struct OpenCodeFormOption: Equatable {
    public let value: String
    public let label: String
    public let description: String?
    public init(value: String, label: String, description: String? = nil) {
        self.value = value
        self.label = label
        self.description = description
    }
}

public struct OpenCodeFormField: Equatable {
    public let key: String
    public let title: String?
    public let description: String?
    public let type: String               // "string", "multiselect", …
    public let options: [OpenCodeFormOption]
    public init(key: String, title: String?, description: String?, type: String, options: [OpenCodeFormOption]) {
        self.key = key
        self.title = title
        self.description = description
        self.type = type
        self.options = options
    }
}

public struct OpenCodeForm: Equatable {
    public let id: String                 // "frm_…"
    public let sessionID: String
    public let title: String
    public let kind: String?              // metadata.kind — "question" for the question tool
    public let fields: [OpenCodeFormField]
    public init(id: String, sessionID: String, title: String, kind: String?, fields: [OpenCodeFormField]) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.kind = kind
        self.fields = fields
    }
}

/// The opencode events the bridge uses, decoded from one SSE `data` body.
public enum OpenCodeEvent: Equatable {
    case permissionAsked(OpenCodePermissionRequest, directory: String?)
    case permissionReplied(sessionID: String, requestID: String)
    case toolCalled(sessionID: String, callID: String, input: [String: String])   // only the string-valued inputs
    case formCreated(OpenCodeForm, directory: String?)
    case formClosed(sessionID: String, formID: String)       // form.replied or form.cancelled
    case sessionCreated(sessionID: String, directory: String?)
    case executionStarted(sessionID: String)
    case executionFinished(sessionID: String)                // succeeded, failed or interrupted
    case other(type: String)

    /// nil when the text isn't a JSON object with a string "type"; `.other(type)` for a type the
    /// bridge doesn't use, or for a known type whose required fields are missing.
    public static func decode(_ json: String) -> OpenCodeEvent? {
        // JSONSerialization, not Codable: opencode adds fields between versions
        // and a strict model would turn any of them into a decode failure.
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let dict = object as? [String: Any],
              let type = dict["type"] as? String else { return nil }
        let data = dict["data"] as? [String: Any] ?? [:]
        let directory = (dict["location"] as? [String: Any])?["directory"] as? String

        switch type {
        case "permission.asked":
            guard let id = data["id"] as? String,
                  let sessionID = data["sessionID"] as? String,
                  let action = data["action"] as? String else { return .other(type: type) }
            let resources = data["resources"] as? [String] ?? []
            let callID = (data["source"] as? [String: Any])?["id"] as? String
            var editedFiles: [String] = []
            var patches: [String] = []
            for entry in (data["metadata"] as? [String: Any])?["files"] as? [[String: Any]] ?? [] {
                guard let file = entry["file"] as? String else { continue }
                editedFiles.append(file)
                patches.append(entry["patch"] as? String ?? "")
            }
            return .permissionAsked(OpenCodePermissionRequest(id: id, sessionID: sessionID, action: action,
                                                              resources: resources, editedFiles: editedFiles,
                                                              patches: patches, callID: callID),
                                    directory: directory)

        case "permission.replied":
            guard let sessionID = data["sessionID"] as? String,
                  let requestID = data["requestID"] as? String else { return .other(type: type) }
            return .permissionReplied(sessionID: sessionID, requestID: requestID)

        case "session.tool.called":
            guard let sessionID = data["sessionID"] as? String,
                  let callID = data["id"] as? String else { return .other(type: type) }
            var input: [String: String] = [:]
            for (key, value) in data["input"] as? [String: Any] ?? [:] {
                if let text = value as? String { input[key] = text }
            }
            return .toolCalled(sessionID: sessionID, callID: callID, input: input)

        case "form.created":
            guard let raw = data["form"] as? [String: Any],
                  let id = raw["id"] as? String,
                  let sessionID = raw["sessionID"] as? String else { return .other(type: type) }
            let kind = (raw["metadata"] as? [String: Any])?["kind"] as? String
            var fields: [OpenCodeFormField] = []
            for entry in raw["fields"] as? [[String: Any]] ?? [] {
                guard let key = entry["key"] as? String, let fieldType = entry["type"] as? String else { continue }
                var options: [OpenCodeFormOption] = []
                for option in entry["options"] as? [[String: Any]] ?? [] {
                    guard let value = option["value"] as? String,
                          let label = option["label"] as? String else { continue }
                    options.append(OpenCodeFormOption(value: value, label: label,
                                                      description: option["description"] as? String))
                }
                fields.append(OpenCodeFormField(key: key, title: entry["title"] as? String,
                                                description: entry["description"] as? String,
                                                type: fieldType, options: options))
            }
            return .formCreated(OpenCodeForm(id: id, sessionID: sessionID,
                                             title: raw["title"] as? String ?? "", kind: kind, fields: fields),
                                directory: directory)

        case "form.replied", "form.cancelled":
            guard let id = data["id"] as? String,
                  let sessionID = data["sessionID"] as? String else { return .other(type: type) }
            return .formClosed(sessionID: sessionID, formID: id)

        case "session.created":
            guard let sessionID = data["sessionID"] as? String else { return .other(type: type) }
            return .sessionCreated(sessionID: sessionID, directory: directory)

        case "session.execution.started":
            guard let sessionID = data["sessionID"] as? String else { return .other(type: type) }
            return .executionStarted(sessionID: sessionID)

        case "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted":
            guard let sessionID = data["sessionID"] as? String else { return .other(type: type) }
            return .executionFinished(sessionID: sessionID)

        default:
            return .other(type: type)
        }
    }
}
