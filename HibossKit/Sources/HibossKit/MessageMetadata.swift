// Option lists, reaction summaries, answer provenance and task-context files on a message.
// Exports: MessageMetadata decoded from the boss API payload.
// Dependencies: Foundation Codable.

import Foundation

public struct OptionMedia: Codable, Equatable, Identifiable, Sendable {
    public let label: String
    public let url: String
    public let caption: String?
    /// A small display copy of the option image; absent on older messages.
    public let thumbnailURL: String?

    public var id: String { label }

    /// The image a tile shows: the valid display copy when present, otherwise the original.
    public var displayURL: String {
        thumbnailURL.flatMap(MessageAttachment.webURL)?.absoluteString ?? url
    }

    enum CodingKeys: String, CodingKey {
        case label, url, caption
        case thumbnailURL = "thumbnail_url"
    }

    public init(label: String, url: String, caption: String? = nil, thumbnailURL: String? = nil) {
        self.label = label
        self.url = url
        self.caption = caption
        self.thumbnailURL = thumbnailURL
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        label = try values.decode(String.self, forKey: .label)
        url = try values.decode(String.self, forKey: .url)
        caption = try values.decodeIfPresent(String.self, forKey: .caption)
        thumbnailURL = try? values.decodeIfPresent(String.self, forKey: .thumbnailURL)
    }
}

public struct MessageMetadata: Codable, Equatable, Sendable {
    public let options: [String]
    /// Valid reactions, unique by actor, actor ID and emoji, in first-seen order.
    public let reactions: [MessageReaction]
    /// Emoji groups in first-seen order, with distinct reaction counts and actor flags.
    public var reactionGroups: [MessageReactionGroup] { MessageReaction.groups(reactions) }
    public let optionMedia: [OptionMedia]
    public let optionDescriptions: [OptionDescription]
    public let isExpired: Bool
    /// Label of the option auto-selected on timeout, if the asker marked one.
    public let defaultOption: String?
    /// On a reply's metadata, where the answer came from: "ios", "telegram", etc.
    public let source: String?
    public let answeredBy: AnsweringDevice?
    /// On a reply's metadata: the server wrote this answer when the decision timed out.
    /// `auto_default: true` is the only marker of an automatic answer. `source` is not:
    /// older timeout replies carry `source: "api"`, newer ones `source: "system"`.
    public let isAutoDefault: Bool
    public let content: String?
    /// Server-owned Markdown with hiboss-embed cards; drawn instead of `content` when present.
    public let richContent: String?
    /// Related file paths from `files` or nested `task_context.files`.
    public let files: [String]
    /// Raw `file_url` an agent attached; `attachment` is the validated form.
    public let fileURL: String?
    /// Raw `file_thumbnail_url`: a small display copy uploaded beside an image `file_url`.
    public let fileThumbnailURL: String?
    /// Raw `form` of a form ask (one catalog v2 input); `form` is the validated reading.
    public let formValue: PanelValue?
    /// On a reply to a form ask: the structured answer the server validated.
    public let answers: PanelValue?

    public var form: AskForm? { AskForm(formValue) }

    public var attachment: MessageAttachment? {
        fileURL.flatMap { MessageAttachment(urlString: $0, thumbnailURLString: fileThumbnailURL) }
    }

    enum CodingKeys: String, CodingKey {
        case options
        case reactions
        case optionMedia = "option_media"
        case optionDescriptions = "option_descriptions"
        case isExpired = "options_expired"
        case defaultOption = "default_option"
        case source
        case answeredBy = "answered_by"
        case isAutoDefault = "auto_default"
        case content
        case richContent = "rich_content"
        case files
        case taskContext = "task_context"
        case fileURL = "file_url"
        case fileThumbnailURL = "file_thumbnail_url"
        case formValue = "form"
        case answers
    }

    public init(
        options: [String],
        optionMedia: [OptionMedia] = [],
        optionDescriptions: [OptionDescription] = [],
        isExpired: Bool = false,
        defaultOption: String? = nil,
        source: String? = nil,
        answeredBy: AnsweringDevice? = nil,
        isAutoDefault: Bool = false,
        content: String? = nil,
        richContent: String? = nil,
        files: [String] = [],
        fileURL: String? = nil,
        fileThumbnailURL: String? = nil,
        reactions: [MessageReaction] = [],
        formValue: PanelValue? = nil,
        answers: PanelValue? = nil
    ) {
        self.reactions = MessageReaction.unique(reactions)
        self.options = options
        self.optionMedia = optionMedia
        self.optionDescriptions = OptionDescription.validated(optionDescriptions, options: options)
        self.isExpired = isExpired
        self.defaultOption = defaultOption
        self.source = source
        self.answeredBy = answeredBy
        self.isAutoDefault = isAutoDefault
        self.content = content
        self.richContent = richContent
        self.files = files
        self.fileURL = fileURL
        self.fileThumbnailURL = fileThumbnailURL
        self.formValue = formValue
        self.answers = answers
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = try? values.decode([FailableReaction].self, forKey: .reactions)
        reactions = MessageReaction.unique(decoded?.compactMap(\.value) ?? [])
        options = try values.decodeIfPresent([String].self, forKey: .options) ?? []
        optionMedia = try values.decodeIfPresent([OptionMedia].self, forKey: .optionMedia) ?? []
        let descriptions = try? values.decodeIfPresent([FailableOptionDescription].self,
            forKey: .optionDescriptions)
        optionDescriptions = OptionDescription.validated(
            descriptions?.compactMap(\.value) ?? [], options: options)
        isExpired = try values.decodeIfPresent(Bool.self, forKey: .isExpired) ?? false
        defaultOption = try values.decodeIfPresent(String.self, forKey: .defaultOption)
        source = try values.decodeIfPresent(String.self, forKey: .source)
        answeredBy = try? values.decodeIfPresent(AnsweringDevice.self, forKey: .answeredBy)
        isAutoDefault = (try? values.decodeIfPresent(Bool.self, forKey: .isAutoDefault)) == true
        content = try values.decodeIfPresent(String.self, forKey: .content)
        richContent = try? values.decodeIfPresent(String.self, forKey: .richContent)
        let direct = try values.decodeIfPresent([String].self, forKey: .files) ?? []
        let nested = try values.decodeIfPresent(TaskContext.self, forKey: .taskContext)
        files = direct.isEmpty ? (nested?.files ?? []) : direct
        fileURL = try? values.decodeIfPresent(String.self, forKey: .fileURL)
        fileThumbnailURL = try? values.decodeIfPresent(String.self, forKey: .fileThumbnailURL)
        formValue = try? values.decodeIfPresent(PanelValue.self, forKey: .formValue)
        answers = try? values.decodeIfPresent(PanelValue.self, forKey: .answers)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        if !reactions.isEmpty { try values.encode(reactions, forKey: .reactions) }
        try values.encode(options, forKey: .options)
        if !optionMedia.isEmpty { try values.encode(optionMedia, forKey: .optionMedia) }
        if !optionDescriptions.isEmpty {
            try values.encode(optionDescriptions, forKey: .optionDescriptions)
        }
        try values.encode(isExpired, forKey: .isExpired)
        try values.encodeIfPresent(defaultOption, forKey: .defaultOption)
        try values.encodeIfPresent(source, forKey: .source)
        try values.encodeIfPresent(answeredBy, forKey: .answeredBy)
        if isAutoDefault { try values.encode(true, forKey: .isAutoDefault) }
        try values.encodeIfPresent(content, forKey: .content)
        try values.encodeIfPresent(richContent, forKey: .richContent)
        if !files.isEmpty { try values.encode(files, forKey: .files) }
        try values.encodeIfPresent(fileURL, forKey: .fileURL)
        try values.encodeIfPresent(fileThumbnailURL, forKey: .fileThumbnailURL)
        try values.encodeIfPresent(formValue, forKey: .formValue)
        try values.encodeIfPresent(answers, forKey: .answers)
    }

    public func optionDescription(for label: String) -> String? {
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return optionDescriptions.first { $0.label == label }?.text
    }

    private struct TaskContext: Decodable {
        let files: [String]?
    }
}
