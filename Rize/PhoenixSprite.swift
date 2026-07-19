//
//  PhoenixSprite.swift
//  Rize — animated phoenix mascot (2D sprite, no 3D on-device)
//
//  Assets: drag the `Phoenix.atlas` folder into your Xcode project
//  (Xcode auto-compiles a texture atlas). 264 transparent PNG frames,
//  512×512, named phoenix_000 … phoenix_263 — the full Blender flight:
//  takeoff from the bonfire → flight loops → swoop → settle. The bird's
//  motion around the screen is baked into the frames (fixed camera),
//  so DO NOT move the node — just play the frames.
//
//  This plays pre-rendered 2D frames, so it costs almost nothing on device —
//  no meshes, no fire simulation. Move the node's `position` to make it fly.

import SpriteKit

// MARK: - SpriteKit (recommended)
final class PhoenixNode: SKSpriteNode {

    static func make() -> PhoenixNode {
        let atlas = SKTextureAtlas(named: "Phoenix")
        // Sort so phoenix_000 … phoenix_263 play in order.
        let frames = atlas.textureNames.sorted().map { atlas.textureNamed($0) }
        let node = PhoenixNode(texture: frames.first)
        let fps = 1.0 / 24.0
        // Play the fire takeoff (frames 0–69) once, then loop the in-flight
        // portion from frame 70 onward so the bonfire only appears the
        // first time the phoenix shows up.
        let intro = SKAction.animate(with: Array(frames.prefix(70)), timePerFrame: fps)
        let loop = SKAction.repeatForever(
            SKAction.animate(with: Array(frames.dropFirst(70)), timePerFrame: fps)
        )
        node.run(.sequence([intro, loop]))
        return node
    }
}

// The full flight (takeoff from fire → loops → swoop → settle) is baked
// into the frames, camera-framed. Treat the sprite as a fixed "stage":
// position it once, never animate its position.
//
// The fire is baked into the frames as soft-alpha glow, so it composites
// over any background. On very light backgrounds you can optionally set
//   phoenix.blendMode = .alpha        // (default; use .add for extra glow on dark UI)


// MARK: - SwiftUI (SpriteView with transparent background)
import SwiftUI

/// SKScene that hosts the phoenix and drifts it across the top of the screen.
final class PhoenixScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill

        let phoenix = PhoenixNode.make()
        // The flight path is baked into the 264 frames (fixed Blender camera),
        // so the node stays put and fills the view — no SKActions on position.
        phoenix.setScale(min(size.width, size.height) / 512.0)
        // On the app's black background the default alpha blend reads well.
        // If it ever looks faint on a light background, uncomment:
        // phoenix.blendMode = .add
        phoenix.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        addChild(phoenix)
    }
}

/// Drop-in SwiftUI view: transparent, non-interactive, loops forever.
struct PhoenixSpriteView: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(
                scene: {
                    let scene = PhoenixScene(size: geo.size)
                    scene.backgroundColor = .clear
                    return scene
                }(),
                options: [.allowsTransparency]
            )
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Perched idle mascot (PhoenixPerchedSmall.atlas, 42 frames, 512×512)
// Same bird, perched on thin air — for onboarding, Duolingo-style.
// Plays forward-then-reverse so the loop is seamless.
final class PhoenixPerchedNode: SKSpriteNode {

    static func make() -> PhoenixPerchedNode {
        let atlas = SKTextureAtlas(named: "PhoenixPerchedSmall")
        let frames = atlas.textureNames.sorted().map { atlas.textureNamed($0) }
        let node = PhoenixPerchedNode(texture: frames.first)
        let forward = SKAction.animate(with: frames, timePerFrame: 1.0 / 24.0)
        node.run(.repeatForever(.sequence([forward, forward.reversed()])))  // ~3.5s ping-pong
        return node
    }
}

final class PhoenixPerchedScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        let phoenix = PhoenixPerchedNode.make()
        phoenix.setScale(min(size.width, size.height) / 512.0)
        phoenix.position = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        phoenix.name = "phoenix"          // handy for future tap handling
        addChild(phoenix)
    }

    // To make it interactive later: override touchesBegan here, check the
    // touched node named "phoenix", and run a reaction SKAction (hop, wing
    // flare, a rendered reaction clip) before resuming the idle loop.
}

/// Drop-in SwiftUI view. Example placement (bottom-right, onboarding):
///
///   .overlay(alignment: .bottomTrailing) {
///       PhoenixPerchedView()
///           .frame(width: 140, height: 140)
///           .padding(.trailing, 8)
///           .padding(.bottom, 24)
///   }
///
/// Remove `.allowsHitTesting(false)` below when you wire up tap reactions.
struct PhoenixPerchedView: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(
                scene: {
                    let scene = PhoenixPerchedScene(size: geo.size)
                    scene.backgroundColor = .clear
                    return scene
                }(),
                options: [.allowsTransparency]
            )
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Tier 1 idle mascot (Tier1_Ashes.atlas, 110 frames, 1024×1024)
// A smoldering ash pile with an occasional ember flare — the Tier 1 (Ash) visual.
// Plays forward and loops (no reverse; the flare-up needs to read as one cycle).
final class Tier1AshesNode: SKSpriteNode {

    // The ash pile's footprint fills ~47% of its 1024×1024 canvas width, while the
    // Tier 2 flame's base (where the fire "catches" the pile) only fills ~22% of
    // its own canvas. Without correction the pile renders roughly 2x wider than the
    // flame base it turns into, so the tier-up transition reads as a resize instead
    // of "this exact pile caught fire." Shrink here so the two footprints match.
    static let contentScale: CGFloat = 0.47

    static func make() -> Tier1AshesNode {
        let atlas = SKTextureAtlas(named: "Tier1_Ashes")
        let frames = atlas.textureNames.sorted().map { atlas.textureNamed($0) }
        let node = Tier1AshesNode(texture: frames.first)
        node.run(.repeatForever(.animate(with: frames, timePerFrame: 1.0 / 24.0)))
        return node
    }
}

final class Tier1AshesScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        let ash = Tier1AshesNode.make()
        ash.setScale(min(size.width, size.height) / 1024.0 * Tier1AshesNode.contentScale)
        // Ground the pile to the bottom of the box (anchor at its base, not its center)
        // so shrinking it for contentScale doesn't pull it toward the middle. The lift
        // compensates for how much shorter contentScale makes the transparent margin
        // below the pile, so its visible base lands at the same height as the flame's
        // base in Tier2FlameScene below — same floor line across the tier-up transition.
        ash.anchorPoint = CGPoint(x: 0.5, y: 0)
        ash.position = CGPoint(x: size.width * 0.5, y: size.height * 0.043)
        addChild(ash)
    }
}

/// Drop-in SwiftUI view for the Tier 1 (Ash) card.
struct Tier1AshesView: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(
                scene: {
                    let scene = Tier1AshesScene(size: geo.size)
                    scene.backgroundColor = .clear
                    return scene
                }(),
                options: [.allowsTransparency]
            )
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Tier 2 idle mascot (Tier2.atlas, 110 frames, 1024×1024)
// A rising flame — the Tier 2 (Awakening) visual.
// Plays the full rise (frame 1–110) once, then loops frame 25 onward so the
// "catching fire" rise only plays the first time the tier is shown.
final class Tier2FlameNode: SKSpriteNode {

    static func make() -> Tier2FlameNode {
        let atlas = SKTextureAtlas(named: "Tier2")
        let frames = atlas.textureNames.sorted().map { atlas.textureNamed($0) }
        let node = Tier2FlameNode(texture: frames.first)
        let fps = 1.0 / 24.0
        let rise = SKAction.animate(with: frames, timePerFrame: fps)
        let loop = SKAction.repeatForever(
            SKAction.animate(with: Array(frames.dropFirst(24)), timePerFrame: fps)
        )
        node.run(.sequence([rise, loop]))
        return node
    }
}

final class Tier2FlameScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        let flame = Tier2FlameNode.make()
        flame.setScale(min(size.width, size.height) / 1024.0)
        // Same floor-line anchoring as Tier1AshesScene, so the pile's base and the
        // flame's base sit at the same height across the tier-up transition.
        flame.anchorPoint = CGPoint(x: 0.5, y: 0)
        flame.position = CGPoint(x: size.width * 0.5, y: 0)
        addChild(flame)
    }
}

/// Drop-in SwiftUI view for the Tier 2 (Awakening) card.
struct Tier2FlameView: View {
    var body: some View {
        GeometryReader { geo in
            SpriteView(
                scene: {
                    let scene = Tier2FlameScene(size: geo.size)
                    scene.backgroundColor = .clear
                    return scene
                }(),
                options: [.allowsTransparency]
            )
        }
        .allowsHitTesting(false)
    }
}


// MARK: - Tier 3 idle mascot (Tier3.atlas, 110 frames, 1024×1024)
// A bigger, hungrier flame — the Tier 3 (Rising) visual.
// Plays the full rise (frame 1–110) once, then loops frame 25 onward, same as Tier2FlameNode.
final class Tier3FlameNode: SKSpriteNode {

    static func make() -> Tier3FlameNode {
        let atlas = SKTextureAtlas(named: "Tier3")
        let frames = atlas.textureNames.sorted().map { atlas.textureNamed($0) }
        let node = Tier3FlameNode(texture: frames.first)
        let fps = 1.0 / 24.0
        let rise = SKAction.animate(with: frames, timePerFrame: fps)
        let loop = SKAction.repeatForever(
            SKAction.animate(with: Array(frames.dropFirst(24)), timePerFrame: fps)
        )
        node.run(.sequence([rise, loop]))
        return node
    }
}

final class Tier3FlameScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        let flame = Tier3FlameNode.make()
        flame.setScale(min(size.width, size.height) / 1024.0)
        // Same floor-line anchoring as Tier1/Tier2. The base-width correction (see
        // Tier3FlameView.contentScale) is applied outside SpriteKit rather than baked in
        // here: SpriteKit hard-clips to its view's rectangular bounds, so scaling the
        // node up in here would crop the flame's tip. Keeping the in-scene render at its
        // natural, non-overflowing size and scaling up at the SwiftUI layer instead lets
        // the enlarged flame bleed into the surrounding space instead of getting cut off.
        flame.anchorPoint = CGPoint(x: 0.5, y: 0)
        flame.position = CGPoint(x: size.width * 0.5, y: 0)
        addChild(flame)
    }
}

/// Drop-in SwiftUI view for the Tier 3 (Rising) card.
struct Tier3FlameView: View {
    // Tier3's flame base (the fixed log/ember structure at its foot) fills only ~14.6%
    // of its own canvas width, versus ~22% for Tier2's base — without correction the
    // tier2→tier3 transition would look like the fire *shrinking* even though Tier3 is
    // meant to be the bigger fire. Scale up so the two base widths match.
    static let contentScale: CGFloat = 1.497

    // Anchoring the scale at .bottom is NOT enough on its own to line up the two
    // floors: Tier3's transparent bottom margin (13.8% of its own canvas) is larger
    // than Tier2's (~8.6%), and contentScale stretches that margin too, so the
    // visible flame base still ends up sitting higher than Tier2's. This shifts it
    // back down by the gap (13.8% × 1.497 − 8.6% ≈ 12.0% of box height) so the two
    // floors actually coincide, not just the (invisible) canvas edges.
    static let floorCompensation: CGFloat = 0.120

    var body: some View {
        GeometryReader { geo in
            SpriteView(
                scene: {
                    let scene = Tier3FlameScene(size: geo.size)
                    scene.backgroundColor = .clear
                    return scene
                }(),
                options: [.allowsTransparency]
            )
            .scaleEffect(Self.contentScale, anchor: .bottom)
            .offset(y: geo.size.height * Self.floorCompensation)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Tier 4 idle mascot (Tier4.atlas, 264 frames, 307×307)
// The Radiant tier flame — a bigger, brighter fire with full 264-frame animation.
final class Tier4FlameNode: SKSpriteNode {

    static func make() -> Tier4FlameNode {
        let atlas = SKTextureAtlas(named: "Tier4")
        let frames = atlas.textureNames.sorted().map { atlas.textureNamed($0) }
        let node = Tier4FlameNode(texture: frames.first)
        let fps = 1.0 / 24.0
        let rise = SKAction.animate(with: frames, timePerFrame: fps)
        let loop = SKAction.repeatForever(
            SKAction.animate(with: Array(frames.dropFirst(24)), timePerFrame: fps)
        )
        node.run(.sequence([rise, loop]))
        return node
    }
}

final class Tier4FlameScene: SKScene {

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        scaleMode = .resizeFill
        let flame = Tier4FlameNode.make()
        flame.setScale(min(size.width, size.height) / 307.0)
        flame.anchorPoint = CGPoint(x: 0.5, y: 0)
        flame.position = CGPoint(x: size.width * 0.5, y: 0)
        addChild(flame)
    }
}

/// Drop-in SwiftUI view for the Tier 4 (Radiant) card.
struct Tier4FlameView: View {

    // Tier4 frames are 307×307 vs Tier3's 1024×1024, so the in-scene render is smaller
    // and needs to be scaled up to match the expected visual size for Radiant.
    static let contentScale: CGFloat = 1.0
    static let floorCompensation: CGFloat = 0.0

    var body: some View {
        GeometryReader { geo in
            SpriteView(
                scene: {
                    let scene = Tier4FlameScene(size: geo.size)
                    scene.backgroundColor = .clear
                    return scene
                }(),
                options: [.allowsTransparency]
            )
            .scaleEffect(Self.contentScale, anchor: .bottom)
            .offset(y: geo.size.height * Self.floorCompensation)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - UIKit alternative (UIImageView)
import UIKit

func makePhoenixImageView() -> UIImageView {
    let frames = (0..<264).compactMap { UIImage(named: String(format: "phoenix_%03d", $0)) }
    let iv = UIImageView()
    iv.animationImages = frames
    iv.animationDuration = 264.0 / 24.0    // 11s full flight loop
    iv.animationRepeatCount = 0            // loop forever
    iv.startAnimating()
    iv.frame = CGRect(x: 0, y: 0, width: 256, height: 256)
    return iv
}
