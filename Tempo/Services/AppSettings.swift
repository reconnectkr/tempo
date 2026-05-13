import Foundation
import Combine

// 팝오버 크기를 UserDefaults에 영속화. 뷰에서 드래그로 갱신, StatusBarController가
// Combine으로 구독해 NSPopover.contentSize에 반영.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let minWidth: CGFloat = 320
    static let minHeight: CGFloat = 360
    static let minDetailPanelWidth: CGFloat = 260

    private static let widthKey = "popoverWidth"
    private static let heightKey = "popoverHeight"
    private static let detailPanelWidthKey = "detailPanelWidth"
    private static let defaultWidth: CGFloat = 360
    private static let defaultHeight: CGFloat = 500
    private static let defaultDetailPanelWidth: CGFloat = 320

    @Published var popoverWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(popoverWidth), forKey: Self.widthKey) }
    }

    @Published var popoverHeight: CGFloat {
        didSet { UserDefaults.standard.set(Double(popoverHeight), forKey: Self.heightKey) }
    }

    // 디테일 패널 폭. 패널이 열려 있을 때만 popover 총 폭에 더해짐.
    @Published var detailPanelWidth: CGFloat {
        didSet { UserDefaults.standard.set(Double(detailPanelWidth), forKey: Self.detailPanelWidthKey) }
    }

    // 패널 열림 여부. 영속화하지 않음 — 항목 선택 상태에 종속.
    @Published var detailPanelOpen: Bool = false

    private init() {
        let defaults = UserDefaults.standard
        let storedW = defaults.object(forKey: Self.widthKey) as? Double
        let storedH = defaults.object(forKey: Self.heightKey) as? Double
        let storedPanel = defaults.object(forKey: Self.detailPanelWidthKey) as? Double
        self.popoverWidth = CGFloat(storedW ?? Double(Self.defaultWidth))
        self.popoverHeight = CGFloat(storedH ?? Double(Self.defaultHeight))
        self.detailPanelWidth = CGFloat(storedPanel ?? Double(Self.defaultDetailPanelWidth))
    }

    func setSize(width: CGFloat, height: CGFloat) {
        popoverWidth = clampWidth(width)
        popoverHeight = clampHeight(height)
    }

    func clampWidth(_ value: CGFloat) -> CGFloat {
        max(value, Self.minWidth)
    }

    func clampHeight(_ value: CGFloat) -> CGFloat {
        max(value, Self.minHeight)
    }

    func clampDetailPanelWidth(_ value: CGFloat) -> CGFloat {
        max(value, Self.minDetailPanelWidth)
    }
}
