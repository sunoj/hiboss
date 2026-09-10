// Option lists, resolution source, and task-context files on a message.
// Exports: MessageMetadata decoded from the boss API payload.
// Dependencies: Foundation Codable.

import Foundation

public struct OptionMedia: Codable, Equatable, Identifiable, Sendable {
    public let label: String
    public let url: String
    public let caption: String?

    public var id: String { label }

    public init(label: String, url: String, caption: String? = nil) {
        self.label = label
        self.url = url
        self.caption = caption
    }
}

public struct MessageMetadata: Codable, Equatable, Sendable {
    public let options: [String]
    public let optionMedia: [OptionMedia]
    public let isExpired: Bool
    /// Label of the option auto-selected on timeout, if the asker marked one.
    public let defaultOption: String?
    /// On a reply's metadata, where the answer came from: "ios", "telegram", etc.
    public let source: String?
    public let content: String?
    /// Related file paths from `files` or nested `task_context.files`.
    public let files: [String]

    enum CodingKeys: String, CodingKey {
        case options
        case optionMedia = "option_media"
        case isExpired = "options_expired"
        case defaultOption = "default_option"
        case source
        case content
        case files
        case taskContext = "task_context"
    }

    public init(
        options: [String],
        optionMedia: [OptionMedia] = [],
        isExpired: Bool = false,
        defaultOption: String? = nil,
        source: String? = nil,
        content: String? = nil,
        files: [String] = []
    ) {
        self.options = options
        self.optionMedia = optionMedia
        self.isExpired = isExpired
        self.defaultOption = defaultOption
        self.source = source
        self.content = content
        self.files = files
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        options = try values.decodeIfPresent([String].self, forKey: .options) ?? []
        optionMedia = try values.decodeIfPresent([OptionMedia].self, forKey: .optionMedia) ?? []
        isExpired = try values.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
        defaultOption = try values.decodeIfPresent(String.self, forKey: .defaultOption)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        content = try values.decodeIfPresent(String.self, forKey: .content)
        let direct = try values.decodeIfPresent([String].self, forKey: .files) ?? []
        let nested = try values.decodeIfPresent(TaskContext.self, forKey: .taskContext)
        files = direct.isEmpty ? (nested?.files ?? []) : direct
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(options, forKey: .options)
        if !optionMedia.isEmpty { try values.encode(optionMedia, forKey: .optionMedia) }
        try values.encode(isExpired, forKey: .isExpired)
        try values.encodeIfPresent(defaultOption, forKey: .defaultOption)
        try values.encodeIfPresent(source, forKey: .source)
        try values.encodeIfPresent(content, forKey: .content)
        if !files.isEmpty { try values.encode(files, forKey: .files) }
    }

    private struct TaskContext: Decodable {
        let files: [String]?
    }
}
