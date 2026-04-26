import SwiftUI
import SwiftData

@Observable
final class DragState {
    var draggedTaskId: UUID?
    var currentDropTaskId: UUID?
    var currentDropMode: DropMode?
    var dragOffset: CGSize = .zero
    var isDragging: Bool { draggedTaskId != nil }

    private var rowFrames: [UUID: CGRect] = [:]

    func registerFrame(_ id: UUID, frame: CGRect) {
        rowFrames[id] = frame
    }

    func clearFrames() {
        rowFrames.removeAll()
    }

    func updateDrop(at point: CGPoint) {
        var bestMatch: (id: UUID, mode: DropMode)?

        for (id, frame) in rowFrames {
            guard id != draggedTaskId else { continue }
            guard frame.contains(point) else { continue }

            let relativeY = (point.y - frame.minY) / frame.height
            let mode: DropMode
            if relativeY < 0.3 {
                mode = .siblingAbove
            } else if relativeY > 0.7 {
                mode = .siblingBelow
            } else {
                mode = .child
            }
            bestMatch = (id, mode)
            break
        }

        currentDropTaskId = bestMatch?.id
        currentDropMode = bestMatch?.mode
    }

    func reset() {
        draggedTaskId = nil
        currentDropTaskId = nil
        currentDropMode = nil
        dragOffset = .zero
    }
}
