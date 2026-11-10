import SwiftUI
import UIKit

/// Full-screen greeting shown once after an explicit sign-in, before the
/// student's next destination (onboarding or Home). Never shown on session
/// restore, token refresh, or returning from the background; the app root only
/// presents it from the sign-in success path. Dismissed only by Continue.
struct SchoolWelcomeView: View {
    let welcome: SchoolWelcome
    let onContinue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AccessibilityFocusState private var headlineFocused: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 44
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    AgoraWordmark(size: 22)
                        .padding(.top, AgoraSpacing.lg)

                    Spacer(minLength: AgoraSpacing.xxl * 2)

                    VStack(alignment: .leading, spacing: AgoraSpacing.md) {
                        Text(welcome.headline)
                            .font(.system(size: headlineSize, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($headlineFocused)

                        Text(welcome.supportingText)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, AgoraSpacing.xxl)

                    continueButton
                }
                .padding(.horizontal, AgoraSpacing.xl)
                .padding(.bottom, AgoraSpacing.lg)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .leading)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 14)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .background { background.ignoresSafeArea() }
        // Light text on dark artwork in either appearance; also turns the
        // wordmark ivory.
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.55)) {
                appeared = true
            }
            // Start VoiceOver on the greeting rather than the wordmark.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { headlineFocused = true }
        }
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            HStack(spacing: AgoraSpacing.sm) {
                Text("Continue")
                Image(systemName: "arrow.right")
                    .accessibilityHidden(true)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(welcome.accent)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: AgoraRadius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(WelcomePressStyle())
        .accessibilityLabel("Continue")
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [welcome.backgroundTop, welcome.backgroundBottom],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )

            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .scaledToFill()
                    // Decorative: the headline carries the meaning.
                    .accessibilityHidden(true)
            } else {
                // Temporary school-color treatment until approved artwork is bundled.
                RadialGradient(
                    colors: [.white.opacity(0.14), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 520
                )
            }

            // Keeps the wordmark, headline, and button readable over any artwork.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .black.opacity(0.0), location: 0.28),
                    .init(color: .black.opacity(0.15), location: 0.5),
                    .init(color: .black.opacity(0.78), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .accessibilityHidden(true)
    }

    private var artwork: UIImage? {
        welcome.backgroundAsset.flatMap { UIImage(named: $0) }
    }
}

private struct WelcomePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    SchoolWelcomeView(welcome: SchoolTheme.virginiaTech.welcome!) {}
}
