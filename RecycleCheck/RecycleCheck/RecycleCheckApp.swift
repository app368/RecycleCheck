import SwiftUI

// MARK: - Точка входа в приложение RecycleCheck

@main
struct RecycleCheckApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // Только светлая тема — UIUserInterfaceStyle в Info.plist
                // задаёт то же на системном уровне, здесь дублируем
                // для SwiftUI-превью и на случай смены темы устройства
                .preferredColorScheme(.light)
        }
    }
}
