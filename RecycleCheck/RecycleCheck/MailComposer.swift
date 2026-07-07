import SwiftUI
import MessageUI

// MARK: - Обёртка почтового клиента для SwiftUI (СП5)
// MFMailComposeViewController не имеет SwiftUI-аналога,
// оборачиваем через UIViewControllerRepresentable.
// Позволяет отправить email с вложением (фото) и текстом.

struct MailComposer: UIViewControllerRepresentable {
    
    /// Адрес получателя
    let recipient: String
    
    /// Тема письма
    let subject: String
    
    /// Текст письма
    let body: String
    
    /// Вложения: (данные, MIME-тип, имя файла)
    var attachments: [(Data, String, String)] = []
    
    /// Замыкание при завершении (успех или отмена)
    var onFinished: (Bool) -> Void = { _ in }
    
    /// Проверка доступности почтового клиента на устройстве
    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
    
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([recipient])
        composer.setSubject(subject)
        composer.setMessageBody(body, isHTML: false)
        
        // Добавляем вложения (фото предмета)
        for (data, mimeType, fileName) in attachments {
            composer.addAttachmentData(data, mimeType: mimeType, fileName: fileName)
        }
        
        return composer
    }
    
    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onFinished: onFinished)
    }
    
    // MARK: - Координатор для обработки результата отправки
    
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        
        let onFinished: (Bool) -> Void
        
        init(onFinished: @escaping (Bool) -> Void) {
            self.onFinished = onFinished
        }
        
        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult,
                                   error: Error?) {
            let success = (result == .sent)
            onFinished(success)
            controller.dismiss(animated: true)
        }
    }
}
