import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    private var modelContainer: ModelContainer = {
        let schema = Schema([TodoTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationManager.shared.setup()
        // SwiftData mainContext에 UndoManager 부착 — 삭제/이동/수정 등 ⌘Z로 되돌림.
        modelContainer.mainContext.undoManager = UndoManager()
        statusBarController = StatusBarController(modelContainer: modelContainer)
    }
}
