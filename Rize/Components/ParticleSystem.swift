import SwiftUI

// MARK: - Particle Model

struct Particle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var opacity: Double
    var scale: Double
    var color: Color
    var velocityX: Double
    var velocityY: Double
    var rotation: Double
    var rotationSpeed: Double
}

// MARK: - Particle Type

enum ParticleType {
    case goldBurst
    case emberFall
    case confettiRain
    case levelUpBurst
    case phoenixEmbers
}

// MARK: - Emitter View

struct ParticleEmitterView: View {
    let type: ParticleType
    @State private var particles: [Particle]

    private let duration: Double

    init(type: ParticleType) {
        self.type = type
        let particleCount: Int
        switch type {
        case .goldBurst: particleCount = 20
        case .emberFall: particleCount = 30
        case .confettiRain: particleCount = 40
        case .levelUpBurst: particleCount = 35
        case .phoenixEmbers: particleCount = 10
        }
        switch type {
        case .phoenixEmbers: self.duration = 4.5
        default: self.duration = 2.0
        }
        // Seeded here (not in .onAppear) so the first Canvas draw already has
        // particles to render — onAppear on a TimelineView-hosted Canvas isn't
        // reliably observed before the initial frame renders, leaving `particles`
        // empty (and the effect invisible) indefinitely.
        _particles = State(initialValue: (0..<particleCount).map { _ in Self.makeParticle(type: type) })
    }

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { context2, size in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: duration) / duration
                for particle in particles {
                    let progress = t
                    let px = particle.x * size.width + particle.velocityX * progress * size.width * 0.5
                    let py = particle.y * size.height + particle.velocityY * progress * size.height * 0.5
                    let opacity = particle.opacity * (1.0 - progress)
                    let scale = particle.scale * (1.0 - progress * 0.5)

                    var ctx = context2
                    ctx.opacity = opacity

                    let rect = CGRect(
                        x: px - 4 * scale,
                        y: py - 4 * scale,
                        width: 8 * scale,
                        height: 8 * scale
                    )

                    ctx.fill(
                        Path(ellipseIn: rect),
                        with: .color(particle.color)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func makeParticle(type: ParticleType) -> Particle {
        switch type {
        case .goldBurst:
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.3...1.0)
            return Particle(
                x: 0.5,
                y: 0.5,
                opacity: 1.0,
                scale: Double.random(in: 0.8...2.0),
                color: Bool.random() ? .yellow : Color(hex: "FFD700"),
                velocityX: cos(angle) * speed,
                velocityY: sin(angle) * speed,
                rotation: 0,
                rotationSpeed: 0
            )
        case .emberFall:
            return Particle(
                x: Double.random(in: 0...1),
                y: 0,
                opacity: Double.random(in: 0.6...1.0),
                scale: Double.random(in: 0.5...1.5),
                color: [Color.red, Color.orange, Color(hex: "FF6B00")].randomElement()!,
                velocityX: Double.random(in: -0.1...0.1),
                velocityY: Double.random(in: 0.5...1.5),
                rotation: 0,
                rotationSpeed: Double.random(in: -2...2)
            )
        case .confettiRain:
            let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .cyan, .orange]
            return Particle(
                x: Double.random(in: 0...1),
                y: 0,
                opacity: 1.0,
                scale: Double.random(in: 0.6...1.8),
                color: colors.randomElement()!,
                velocityX: Double.random(in: -0.2...0.2),
                velocityY: Double.random(in: 0.6...1.2),
                rotation: Double.random(in: 0...360),
                rotationSpeed: Double.random(in: -5...5)
            )
        case .levelUpBurst:
            let angle = Double.random(in: 0...(2 * .pi))
            let speed = Double.random(in: 0.5...1.2)
            let colors: [Color] = [.yellow, .cyan, .purple, .green, .orange, .pink]
            return Particle(
                x: 0.5,
                y: 0.5,
                opacity: 1.0,
                scale: Double.random(in: 1.0...2.5),
                color: colors.randomElement()!,
                velocityX: cos(angle) * speed,
                velocityY: sin(angle) * speed,
                rotation: 0,
                rotationSpeed: Double.random(in: -3...3)
            )
        case .phoenixEmbers:
            return Particle(
                x: Double.random(in: 0.25...0.75),
                y: Double.random(in: 0.6...1.0),
                opacity: Double.random(in: 0.4...0.9),
                scale: Double.random(in: 0.4...1.0),
                color: Bool.random() ? Color(hex: "F5A623") : Color(hex: "FFD700"),
                velocityX: Double.random(in: -0.08...0.08),
                velocityY: Double.random(in: -1.2...(-0.6)),
                rotation: 0,
                rotationSpeed: 0
            )
        }
    }
}
