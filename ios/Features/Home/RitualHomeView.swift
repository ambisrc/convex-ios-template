import SwiftUI

struct RitualHomeView: View {
    @ObservedObject var model: VoiceAgentTemplateModel

    var body: some View {
        ZStack {
            WatercolorBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    brainDumpCard

                    if !model.homeReflectionPrompts.isEmpty {
                        sectionTitle("Reflections")
                        VStack(spacing: 12) {
                            ForEach(model.homeReflectionPrompts) { prompt in
                                ReflectionPromptBubble(prompt: prompt) {
                                    model.openBrainDump(prompt: prompt)
                                }
                            }
                        }
                    }

                    if !model.entries.isEmpty {
                        sectionTitle("Recent")
                        VStack(spacing: 10) {
                            ForEach(model.entries.prefix(5)) { entry in
                                recentEntryButton(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 64)
                .padding(.bottom, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $model.isSettingsPresented) {
            SettingsView(model: model)
        }
        .overlay(alignment: .bottom) {
            if let feedbackMessage = model.feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your ritual")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JournalPalette.secondaryInk)
                Text("Today")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(JournalPalette.ink)
            }

            Spacer()

            Button {
                model.isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(JournalPalette.moss)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.55), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 1))
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier(TemplateAccessibility.settingsOpen)
        }
    }

    private var brainDumpCard: some View {
        Button {
            model.openBrainDump()
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Spacer()
                Text("Brain Dump")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(JournalPalette.secondaryInk)
                Text("Tell me about it.")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(JournalPalette.ink)
                Text("Open the voice screen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JournalPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .padding(22)
            .background {
                ZStack {
                    WatercolorBackgroundView(fillsSafeArea: false)
                    LinearGradient(
                        colors: [.white.opacity(0.18), .white.opacity(0.54)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(.white.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: JournalPalette.moss.opacity(0.12), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(TemplateAccessibility.homeBrainDumpCard)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline.weight(.bold))
            .foregroundStyle(JournalPalette.ink)
            .padding(.top, 2)
    }

    private func recentEntryButton(_ entry: Entry) -> some View {
        Button {
            model.openEntryEditor(entry)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(entry.body)
                    .font(.body.weight(.medium))
                    .foregroundStyle(JournalPalette.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(entry.source.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JournalPalette.secondaryInk.opacity(0.78))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(JournalPalette.warmCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
