import SwiftUI

/// A shareable "achievement unlocked" card — Rize's answer to Duolingo's
/// shareable streak/badge cards. With no friends/social layer in the app
/// (yet), this is the one piece of content deliberately designed to leave
/// the app and pull a viewer back in: posted to a story, it reads as an ad
/// for Rize with the app's own branding baked into the image.
///
/// Rendered off-screen at a fixed size via `ImageRenderer` (see
/// `AchievementShareRenderer` below) rather than shown live on screen, so it
/// always exports at the same crisp, portrait, story-friendly aspect ratio
/// regardless of the device it's generated on.
struct AchievementSharePlaque: View {
    let achievement: AchievementDefinition
    var streak: Int = 0

    private var goldGradient: LinearGradient {
        LinearGradient(
            colors: [PhoenixPalette.eternal, PhoenixPalette.radiant, PhoenixPalette.primary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "000000"), Color(hex: "1A0505"), Color(hex: "3D0A0A")],
                startPoint: .bottom, endPoint: .top
            )

            VStack(spacing: 0) {
                Text("RIZE")
                    .font(.phoenixHero(26))
                    .foregroundColor(.white)
                    .padding(.top, 40)

                Spacer(minLength: 0)

                medallion
                    .padding(.bottom, 32)

                VStack(spacing: 10) {
                    Text("ACHIEVEMENT UNLOCKED")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(PhoenixPalette.eternal)

                    Text(achievement.title)
                        .font(.phoenixHero(32))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    Text(achievement.description)
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 44)
                }

                Spacer(minLength: 0)

                if streak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundColor(.orange)
                        Text("\(streak) day streak")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    .padding(.bottom, 14)
                }

                Text("Show up. Even on your worst days.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 40)
            }
        }
        .frame(width: 420, height: 620)
    }

    private var medallion: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [PhoenixPalette.radiant, PhoenixPalette.primary], center: .center, startRadius: 0, endRadius: 90))
            Circle()
                .stroke(goldGradient, lineWidth: 5)
            Image(systemName: achievement.icon)
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 172, height: 172)
        .shadow(color: PhoenixPalette.eternal.opacity(0.5), radius: 30)
    }
}

/// Lets a previously-unlocked badge be re-shared anytime, not just at the
/// moment it unlocks — tapped from the Phoenix tab's badge grid.
struct BadgeShareSheet: View {
    let achievement: AchievementDefinition
    var streak: Int = 0
    @Environment(\.dismiss) private var dismiss
    @State private var shareImage: Image?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                if let shareImage {
                    shareImage
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .black.opacity(0.4), radius: 20)

                    ShareLink(
                        item: shareImage,
                        preview: SharePreview(achievement.title, image: shareImage)
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                            Text("SHARE")
                        }
                        .font(.phoenixHeadline())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PhoenixPalette.primary)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                    }
                    .padding(.horizontal, 24)
                } else {
                    ProgressView()
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PhoenixBackground())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            shareImage = AchievementShareRenderer.image(for: achievement, streak: streak)
        }
    }
}

/// Renders `AchievementSharePlaque` to a `UIImage` off-screen, at 3x scale
/// regardless of the device's actual screen scale — so the shared image is
/// always crisp even if generated on an older/lower-density device.
@MainActor
enum AchievementShareRenderer {
    static func image(for achievement: AchievementDefinition, streak: Int = 0) -> Image? {
        let renderer = ImageRenderer(content: AchievementSharePlaque(achievement: achievement, streak: streak))
        renderer.scale = 3
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}
