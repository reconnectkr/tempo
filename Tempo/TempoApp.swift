import SwiftUI
import SwiftData

@main
struct TempoApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([TodoTask.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("ModelContainer 생성 실패: \(error)")
        }
    }()

    init() {
        NotificationManager.shared.setup()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .modelContainer(sharedModelContainer)
        } label: {
            MenuBarLabel()
                .modelContainer(sharedModelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
