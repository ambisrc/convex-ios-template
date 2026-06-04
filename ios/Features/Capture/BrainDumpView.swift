import SwiftUI

struct BrainDumpView: View {
    @ObservedObject var model: VoiceAgentTemplateModel
    let prompt: TemplateReflectionPrompt?

    private var promptText: String {
        if let prompt {
            return prompt.question
        }
        return "Tell me about it."
    }

    private var promptLead: String {
        if prompt == nil {
            return "How did your day go?"
        }
        return "Reflect on this"
    }

    private var isRecording: Bool {
        if case .recording = model.voiceState {
            return true
        }
        return false
    }

    var body: some View {
        ZStack {
            WatercolorBackgroundView()
            VStack(spacing: 0) {
                HStack {
                    Button {
                        model.goHome()
                    } label: {
                        Label("Home", systemImage: "chevron.left")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(JournalPalette.moss)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.white.opacity(0.48), in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.62), lineWidth: 1))
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)

                Spacer(minLength: 54)

                VStack(spacing: 14) {
                    Text(promptLead)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(JournalPalette.secondaryInk)
                        .multilineTextAlignment(.center)

                    Text(promptText)
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .lineSpacing(3)
                        .foregroundStyle(JournalPalette.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 38)

                waveform
                    .accessibilityIdentifier(TemplateAccessibility.brainDumpWaveform)

                Text(isRecording ? "Listening..." : "Tap to speak")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isRecording ? JournalPalette.moss : JournalPalette.secondaryInk)
                    .padding(.top, 12)

                voiceStatus
                    .padding(.top, 18)
                    .padding(.horizontal, 30)

                Spacer(minLength: 72)

                recordButton
                    .padding(.bottom, 54)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if let feedbackMessage = model.feedbackMessage {
                Text(feedbackMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
    }

    private var recordButton: some View {
        Button {
            Task { await model.startVoiceDump(from: prompt) }
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.64))
                    .frame(width: 128, height: 128)
                    .shadow(color: JournalPalette.moss.opacity(0.22), radius: 28, x: 0, y: 18)
                    .overlay(Circle().stroke(.white.opacity(0.72), lineWidth: 1))

                Circle()
                    .fill(JournalPalette.moss)
                    .frame(width: 88, height: 88)

                Circle()
                    .fill(JournalPalette.paper)
                    .frame(width: isRecording ? 30 : 22, height: isRecording ? 30 : 22)
                    .clipShape(RoundedRectangle(cornerRadius: isRecording ? 8 : 11, style: .continuous))
            }
        }
        .accessibilityLabel("Start voice dump")
        .accessibilityIdentifier(TemplateAccessibility.brainDumpStartVoice)
        .disabled(isRecording)
    }

    @ViewBuilder
    private var voiceStatus: some View {
        if let transcript = model.voiceTranscriptPreview, !transcript.isEmpty {
            VStack(spacing: 6) {
                Text("Heard")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(JournalPalette.secondaryInk)

                Text(transcript)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(JournalPalette.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 320)
            .background(.white.opacity(0.46), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.6), lineWidth: 1)
            )
        } else if let feedbackMessage = model.feedbackMessage {
            Text(feedbackMessage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(JournalPalette.secondaryInk)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: 320)
                .background(.white.opacity(0.38), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.54), lineWidth: 1)
                )
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 8) {
            ForEach(Array([18, 34, 52, 68, 36, 48, 58, 72, 36, 48, 58, 72].enumerated()), id: \.offset) { _, height in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill((isRecording ? JournalPalette.moss : JournalPalette.teal).opacity(isRecording ? 0.88 : 0.72))
                    .frame(width: 7, height: CGFloat(isRecording ? height + 12 : height))
            }
        }
        .frame(width: 250, height: 92)
        .background(.white.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.28), lineWidth: 1))
    }
}
