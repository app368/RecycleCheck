import SwiftUI
import UIKit

// MARK: - Системное меню «Поделиться»
// Обёртка UIActivityViewController для SwiftUI: AirDrop, Файлы, почта и т. д.
// Используется для отправки файла резервной копии (экран Profile)

struct ShareSheet: UIViewControllerRepresentable {

    /// Что отправляем (например, URL файла)
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
