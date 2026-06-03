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
                Text("Voice Agent")
                    .font(.largeTitle.weight(.semibold))
                Text("Talk or type. The backend validates the operation before anything is saved.")
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

    private var signedInView: some View {
        NavigationStack {
            List {
                if model.entries.isEmpty {
                    ContentUnavailableView(
                        "No entries",
                        systemImage: "waveform",
                        description: Text("Send a typed or voice command to create one.")
                    )
                } else {
                    ForEach(model.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.body)
                                .font(.body)
                                .accessibilityIdentifier("\(TemplateAccessibility.entryBodyPrefix).\(entry.id)")
                            Text(entry.source.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let feedbackMessage = model.feedbackMessage {
                    Text(feedbackMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                CaptureBar(model: model)
            }
            .navigationTitle("Entries")
            .toolbar {
                Button {
                    model.isSettingsPresented = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
                .accessibilityIdentifier(TemplateAccessibility.settingsOpen)
            }
            .sheet(isPresented: $model.isSettingsPresented) {
                SettingsView(model: model)
            }
        }
    }
}

#Preview {
    VoiceAgentRootView(model: VoiceAgentTemplateModel())
}
