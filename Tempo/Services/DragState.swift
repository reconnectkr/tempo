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

    // 현재 렌더된 행만 정확히 반영(없어진 행은 즉시 제거).
    // 날짜 전환·삭제 등으로 화면에서 빠진 행의 stale frame이 남아 드롭 hit-test에
    // 끼어드는 사고(다른 날짜 트리로 흡수되어 항목이 사라지는 현상) 방지.
    func replaceFrames(_ frames: [UUID: CGRect]) {
        rowFrames = frames
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

            // 자식 모드는 사용자가 우측 절반으로 명확히 끌었을 때만 발동.
            // 그 외에는 Y 위치에 따라 형제(위/아래)로 떨어짐 — 제자리에 두려는 의도가
            // 의도치 않게 자식으로 흡수되어 화면에서 "사라지는" 현상 방지.
            let mode: DropMode
            if relX > 0.5 {
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
