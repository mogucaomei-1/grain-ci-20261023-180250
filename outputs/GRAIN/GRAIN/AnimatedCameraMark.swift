import SwiftUI

struct AnimatedEditorMark: View {
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let pulse = reduceMotion ? 0.55 : (sin(time * 2.8) + 1) / 2
            let sway = reduceMotion ? 0 : sin(time * 1.7) * 1.4

            ZStack {
                photoCard(color: Color(hex: 0x43848A))
                    .rotationEffect(.degrees(-11 + sway * 0.35))
                    .offset(x: -size * 0.16, y: size * 0.025)
                    .opacity(0.86)

                photoCard(color: GrainTheme.accent)
                    .rotationEffect(.degrees(11 - sway * 0.35))
                    .offset(x: size * 0.16, y: size * 0.025)
                    .opacity(0.82)

                frontEditor(progress: 0.38 + pulse * 0.24)
                    .rotationEffect(.degrees(sway * 0.16))
                    .offset(y: -size * 0.015)
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }

    private func photoCard(color: Color) -> some View {
        RoundedRectangle(cornerRadius: size * 0.11, style: .continuous)
            .fill(color)
            .frame(width: size * 0.50, height: size * 0.62)
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.075, style: .continuous)
                    .fill(Color.black.opacity(0.18))
                    .padding(size * 0.045)
                    .overlay {
                        Circle()
                            .fill(GrainTheme.paper.opacity(0.28))
                            .frame(width: size * 0.09, height: size * 0.09)
                            .offset(x: -size * 0.07, y: -size * 0.05)
                    }
            }
    }

    private func frontEditor(progress: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
            .fill(Color(hex: 0xFDFBF7))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.09, style: .continuous)
                    .stroke(Color.black.opacity(0.14), lineWidth: 0.5)
            }
            .frame(width: size * 0.54, height: size * 0.66)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.055, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0x222A31),
                                    Color(hex: 0x50615D)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: size * 0.42, height: size * 0.35)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(GrainTheme.accent)
                                .frame(width: size * 0.105, height: size * 0.105)
                                .offset(x: -size * 0.045, y: -size * 0.04)
                        }
                        .offset(y: -size * 0.075)

                    Capsule()
                        .fill(Color.black.opacity(0.13))
                        .frame(width: size * 0.37, height: max(1.5, size * 0.032))
                        .offset(y: size * 0.205)

                    Capsule()
                        .fill(GrainTheme.accent)
                        .frame(
                            width: size * 0.37 * progress,
                            height: max(1.5, size * 0.032)
                        )
                        .frame(width: size * 0.37, alignment: .leading)
                        .offset(y: size * 0.205)

                    Circle()
                        .fill(Color.white)
                        .frame(width: max(3, size * 0.064), height: max(3, size * 0.064))
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .offset(
                            x: -size * 0.185 + size * 0.37 * progress,
                            y: size * 0.205
                        )
                }
            }
    }
}
