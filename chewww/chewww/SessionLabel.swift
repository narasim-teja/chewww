//
//  SessionLabel.swift
//  chewww
//
//  The fixed activity vocabulary for Phase 1's labeled-dataset collector.
//  The user picks ONE `SessionLabel` (and, for eating, an optional
//  `FoodTexture`) before tapping Start; the whole session carries it.
//
//  The chosen label is resolved into ONE token (e.g. "eating-crunchy",
//  "walking") that travels two ways, identically:
//    1. The filename  — `CSVLogger.start(label:)` names the file.
//    2. A per-row CSV column — lets us concatenate files later.
//
//  Using the SAME token for both means filename and rows never disagree, and
//  the history view can recover the label from the filename alone.
//
//  Both enums are plain value types: String-backed, CaseIterable (drives a
//  Picker), Identifiable (drives ForEach / List), Codable + Sendable (clean
//  to hand to the @MainActor CSVLogger in Swift 5, and easy to persist later).
//

import Foundation

// MARK: - SessionLabel

/// What the user is doing for the duration of one recording session.
///
/// Raw values double as the canonical, filename-safe machine token, so the
/// token is stable even if we rename a display string later. Keep these
/// lowercase-able, ASCII, and free of the separators we rely on elsewhere:
/// `_` (the filename field separator) and `,`/newlines (CSV separators).
enum SessionLabel: String, CaseIterable, Identifiable, Codable, Sendable {
    case eating
    case drinking
    case talking
    case nothing
    case walking
    case talkingWhileWalking

    var id: String { rawValue }

    /// Human-facing name for the picker tiles, status line, and history list.
    var title: String {
        switch self {
        case .eating:             return "Eating"
        case .drinking:           return "Drinking"
        case .talking:            return "Talking"
        case .nothing:            return "Nothing"
        case .walking:            return "Walking"
        case .talkingWhileWalking: return "Talking + Walking"
        }
    }

    /// SF Symbol for the picker tile.
    var systemImage: String {
        switch self {
        case .eating:             return "fork.knife"
        case .drinking:           return "cup.and.saucer"
        case .talking:            return "waveform"
        case .nothing:            return "moon.zzz"
        case .walking:            return "figure.walk"
        case .talkingWhileWalking: return "figure.walk.motion"
        }
    }

    /// Filename-safe, lowercase token for this label alone (no texture).
    ///
    /// The only camelCase case (`talkingWhileWalking`) is flattened to
    /// lowercase so filenames never carry capitals; the result is guaranteed
    /// to contain no `_`, `,`, or newline.
    var slug: String { rawValue.lowercased() }

    /// Only `.eating` carries a crunchy/soft texture tag — the doc says
    /// texture matters a lot, but it's meaningless for the other activities.
    var supportsTexture: Bool { self == .eating }

    // MARK: Combined label + texture token

    /// The single token used for BOTH the filename and the per-row CSV column.
    ///
    /// Examples: `eating-crunchy`, `eating-soft`, `eating` (texture unset),
    /// `walking`. Joined with `-` because the filename pattern
    /// `chewww_<label>_<timestamp>.csv` already uses `_` as its field
    /// separator — keeping `_` out of the token keeps the filename
    /// unambiguous to split. Guaranteed free of `_`, `,`, and newline.
    func token(texture: FoodTexture = .none) -> String {
        guard supportsTexture, let textureSlug = texture.slug else {
            return slug
        }
        return "\(slug)-\(textureSlug)"
    }
}

// MARK: - FoodTexture

/// Optional texture tag for eating sessions. `.none` means "not applicable /
/// unspecified" — the value for every non-eating label and for eating before
/// the user has chosen.
enum FoodTexture: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case crunchy
    case soft

    var id: String { rawValue }

    /// Human-facing name for the texture picker.
    var title: String {
        switch self {
        case .none:    return "Unspecified"
        case .crunchy: return "Crunchy"
        case .soft:    return "Soft"
        }
    }

    /// The textures a user can actually choose between (excludes `.none`).
    static var choices: [FoodTexture] { [.crunchy, .soft] }

    /// Filename/column token, or `nil` when there's nothing to append.
    /// `.none` returns `nil` so `token(texture:)` collapses to the bare label.
    var slug: String? {
        self == .none ? nil : rawValue.lowercased()
    }
}
