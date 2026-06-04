import SwiftUI

struct ReflectionPromptBubble: View {
    let prompt: TemplateReflectionPrompt
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reflection")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(JournalPalette.secondaryInk.opacity(0.78))
                Text(prompt.question)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(JournalPalette.ink)
                    .multilineTextAlignment(.leading)
                Text("Answer with voice")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JournalPalette.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(JournalPalette.sageCard.opacity(0.78), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.62), lineWidth: 1)
            )
            .shadow(color: JournalPalette.moss.opacity(0.08), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(TemplateAccessibility.homeReflectionPrompt)
    }
}
