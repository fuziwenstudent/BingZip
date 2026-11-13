import AppKit

/// NSScrollView subclass that turns horizontal trackpad swipes into
/// Finder-style back / forward navigation while leaving normal vertical
/// scrolling untouched.
///
/// macOS delivers two-finger "swipe between pages" gestures as scroll events
/// (unless the user configured three-finger swipes, which arrive through
/// `swipe(with:)`). Both paths are handled here.
final class TrackpadScrollView: NSScrollView {

    /// Fingers moved to the right (content moves right) → go back.
    var onSwipeRight: (() -> Void)?
    /// Fingers moved to the left (content moves left) → go forward.
    var onSwipeLeft: (() -> Void)?

    private var isSwipeTracking = false
    private var swipeDistance: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        // Mouse wheels and older input devices keep the stock behaviour.
        guard event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }

        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY

        if event.phase == .began || event.phase == .mayBegin {
            // Only take over clearly horizontal gestures, and only when the
            // document itself cannot scroll horizontally.
            let canScrollHorizontally: Bool = {
                guard let documentView = documentView else { return false }
                return documentView.bounds.width > contentView.bounds.width + 1
            }()
            isSwipeTracking = !canScrollHorizontally && abs(dx) > abs(dy) * 1.5
            swipeDistance = 0
        }

        guard isSwipeTracking else {
            super.scrollWheel(with: event)
            return
        }

        // Swallow momentum events belonging to the gesture so the table does
        // not rubber-band after a navigation swipe.
        if event.momentumPhase != [] {
            return
        }

        switch event.phase {
        case .began, .changed:
            swipeDistance += dx
        case .ended, .cancelled:
            let threshold = max(60, contentView.bounds.width * 0.12)
            if swipeDistance <= -threshold {
                onSwipeLeft?()
            } else if swipeDistance >= threshold {
                onSwipeRight?()
            }
            isSwipeTracking = false
            swipeDistance = 0
        default:
            break
        }
    }

    override func swipe(with event: NSEvent) {
        // 系统 swipe 事件:deltaX = -1 表示向右滑,+1 表示向左滑。
        if event.deltaX < 0 {
            onSwipeRight?()
        } else if event.deltaX > 0 {
            onSwipeLeft?()
        } else {
            super.swipe(with: event)
        }
    }
}
