import Foundation

public enum ScreenEdgeAppearance: Equatable, Sendable {
    case hidden
    case live
    case warning
    case idleOutline
}

public enum ScreenEdgeIndicatorPresentation {
    public static func appearance(
        mode: MuteMode,
        status: MuteStatus,
        preferences: ScreenEdgeIndicatorPreferences
    ) -> ScreenEdgeAppearance {
        guard preferences.isEnabled, mode == .pushToTalk else { return .hidden }

        switch status {
        case .live:
            return .live
        case .mixed, .partial, .unsupported, .externallySilenced, .error:
            // Sound may still reach the input, so the edge reports it even between gestures.
            // An error leaves the state untrustworthy, which is not a confirmed mute either.
            // An input silenced outside Mutelet is quiet, but a gesture cannot deliver what
            // it promises on it, and the edge is the only report a full-screen user sees.
            return .warning
        case .muted, .unavailable, .disconnected, .loading:
            // The outline means "Mutelet is watching", not "the input is muted", so it also
            // covers targets that cannot be resolved.
            return preferences.showsIdleOutline ? .idleOutline : .hidden
        }
    }

    // The edge speaks in "audible" and "silent". A target that cannot be resolved is silent
    // too, so the edge alone would leave a press that found no microphone unanswered.
    public static func expressesGestureResult(_ status: MuteStatus) -> Bool {
        switch status {
        case .live, .muted, .mixed, .partial, .unsupported, .externallySilenced, .error:
            true
        case .unavailable, .disconnected, .loading:
            false
        }
    }

    public static func suppressesHotKeyHUD(
        mode: MuteMode,
        preferences: ScreenEdgeIndicatorPreferences
    ) -> Bool {
        preferences.isEnabled && mode == .pushToTalk
    }
}
