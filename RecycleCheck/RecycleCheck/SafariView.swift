import SwiftUI
import SafariServices

// MARK: - Обёртка SFSafariViewController для SwiftUI (СП4)
// Открывает страницу источника внутри приложения,
// не выбрасывая пользователя во внешний браузер.

struct SafariView: UIViewControllerRepresentable {

    /// Адрес открываемой страницы
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {
        // Обновление не требуется — контроллер создаётся один раз для URL
    }
}
