import Foundation

struct TemplateConvexCommandRequest: Encodable, Equatable {
    let text: String
    let source: TemplateCommandSource
    let promptId: String?

    init(text: String, source: TemplateCommandSource, promptId: String? = nil) {
        self.text = text
        self.source = source
        self.promptId = promptId
    }

    func encodedBody() throws -> Data {
        try JSONEncoder().encode(self)
    }
}

struct TemplateUpdateEntryRequest: Encodable, Equatable {
    let id: String
    let body: String
}

struct TemplateVoiceTranscriptionRequest: Encodable, Equatable {
    let audioBase64: String
    let mimeType: String
}
