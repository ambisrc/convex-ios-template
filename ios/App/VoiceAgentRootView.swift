import SwiftUI

struct VoiceAgentRootView: View {
    @ObservedObject var model: VoiceAgentTemplateModel

    var body: some View {
        Group {
            if model.isSignedIn {
                signedInView
            } else {
                signedOutView
            }
        }
        .tint(.teal)
    }

    private var signedOutView: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 10) {
                Text("Voice Journal")
                    .font(.largeTitle.weight(.semibold))
                Text("Speak freely. Your words are saved privately on the backend.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let feedbackMessage = model.feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            Button {
                Task { await model.signIn() }
            } label: {
                Label("Sign in with Apple", systemImage: "apple.logo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(TemplateAccessibility.signIn)
            .padding(.horizontal, 28)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var signedInView: some View {
        Group {
            switch model.screen {
            case .home:
                RitualHomeView(model: model)
            case .brainDump(let prompt):
                BrainDumpView(model: model, prompt: prompt)
            case .entryEditor(let entry):
                EntryEditorView(model: model, entry: entry)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WatercolorBackgroundView())
    }
}

#Preview {
    VoiceAgentRootView(model: VoiceAgentTemplateModel())
}
