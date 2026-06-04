import SwiftUI

struct EntryEditorView: View {
    @ObservedObject var model: VoiceAgentTemplateModel
    let entry: Entry

    @State private var draftBody: String

    init(model: VoiceAgentTemplateModel, entry: Entry) {
        self.model = model
        self.entry = entry
        _draftBody = State(initialValue: entry.body)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextEditor(text: $draftBody)
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityIdentifier(TemplateAccessibility.entryEditBody)

                Button("Save") {
                    Task {
                        await model.saveEntryEdit(id: entry.id, body: draftBody)
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(TemplateAccessibility.entryEditSave)
            }
            .padding()
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.goHome()
                    }
                }
            }
        }
    }
}
