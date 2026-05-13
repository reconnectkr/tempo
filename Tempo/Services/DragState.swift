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

            let relY = (point.y - frame.minY) / frame.height

            // 행을 세로로 3등분: 상단 20% = 위 형제, 중앙 60% = 자식, 하단 20% = 아래 형제.
            // 중앙에 명확히 겹치면 자식으로 흡수. 제자리에 두려는 동작은
            // TaskService.performDrop의 no-op 가드에서 걸러냄.
            let mode: DropMode
            if relY < 0.2 {
                mode = .siblingAbove
            } else if relY > 0.8 {
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
