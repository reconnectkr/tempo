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

            let relX = (point.x - frame.minX) / frame.width
            let relY = (point.y - frame.minY) / frame.height

            // 박스 본체(가운데 50%)에 떨어뜨리면 자식.
            // 위/아래 가장자리(각 25%)는 형제, 단 그 위치에서 오른쪽으로 충분히 끌면 자식으로 승격.
            let inBox = relY >= 0.25 && relY <= 0.75
            let mode: DropMode
            if inBox {
                mode = .child
            } else if relX > 0.6 {
                mode = .child
            } else if relY < 0.5 {
                mode = .siblingAbove
            } else {
                mode = .siblingBelow
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
