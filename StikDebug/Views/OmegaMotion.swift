import SwiftUI

/// Shared presentation timing. Keep these animations attached to discrete UI
/// changes, never to the location session or the complete map view's updates.
enum OmegaMotion {
    static func panel(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .spring(response: 0.38, dampingFraction: 0.88)
    }

    static func detail(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.92)
    }

    static func fade(reduceMotion: Bool) -> Animation {
        .easeOut(duration: reduceMotion ? 0.12 : 0.18)
    }

    static func scroll(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.26)
    }

    static func camera(duration: TimeInterval, following: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return following ? .linear(duration: duration) : .smooth(duration: duration)
    }

    static func symbol(reduceMotion: Bool) -> ContentTransition {
        reduceMotion ? .opacity : .symbolEffect(.replace)
    }
}

/// A symbol change crossfades/replaces in its existing frame, without replaying
/// every time the surrounding view receives a playback update.
struct OmegaStatusSymbol: View {
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: name)
            .contentTransition(OmegaMotion.symbol(reduceMotion: reduceMotion))
            .animation(OmegaMotion.fade(reduceMotion: reduceMotion), value: name)
    }
}

struct OmegaQuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.62 : 1) : 0.4)
            .animation(OmegaMotion.fade(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

/// A queued programmatic scroll must give way as soon as a person starts
/// scrolling. Older OS releases retain the existing native scroll behavior.
struct OmegaScrollInteraction: ViewModifier {
    let onBegin: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting { onBegin() }
            }
        } else {
            content
        }
    }
}
