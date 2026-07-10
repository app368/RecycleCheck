import SwiftUI

// MARK: - Экран предложения добавить предмет (СП5)
// Пользователь может отправить email с просьбой добавить предмет
// в базу переработки на сайте. В письмо вкладываются:
// — фото предмета
// — описание (опционально, может дополнить пользователь)
// — обратный email пользователя (из профиля СП6, если заполнен)

struct SuggestItemView: View {
    
    /// Предмет, который не найден на сайте
    let item: RecycleItem
    
    /// Дополнительный комментарий от пользователя
    @State private var userComment: String = ""
    
    /// Управление показом почтового клиента
    @State private var showMailComposer = false
    
    /// Результат отправки
    @State private var emailSent = false
    @State private var showResultAlert = false
    
    /// Фокус для управления клавиатурой
    @FocusState private var isCommentFocused: Bool
    
    @Environment(\.dismiss) private var dismiss
    
    private let storage = StorageService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - Заголовок и пояснение
                
                headerSection
                
                // MARK: - Превью предмета
                
                itemPreview
                
                // MARK: - Комментарий пользователя
                
                commentSection
                
                // MARK: - Информация об отправке
                
                emailInfoSection
                
                // MARK: - Кнопки действий
                
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Suggest item")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isCommentFocused = false
                }
            }
        }
        
        // MARK: - Почтовый клиент
        
        .sheet(isPresented: $showMailComposer) {
            MailComposer(
                recipient: AppConfig.requestEmail,
                subject: AppConfig.emailSubject,
                body: buildEmailBody(),
                attachments: buildAttachments(),
                onFinished: { success in
                    emailSent = success
                    showResultAlert = true
                }
            )
        }
        
        // MARK: - Результат отправки
        
        .alert(emailSent ? "Sent" : "Not sent", isPresented: $showResultAlert) {
            Button("OK") {
                if emailSent {
                    dismiss()
                }
            }
        } message: {
            Text(emailSent
                 ? "Your suggestion has been sent. Thank you!"
                 : "The email was not sent. You can try again.")
        }
    }
    
    // MARK: - Заголовок
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            
            Text("Item not found in the database")
                .font(.headline)
            
            Text("You can suggest adding this item to the recycling database. We'll send a photo and description to the website team.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Превью предмета (фото + название)
    
    private var itemPreview: some View {
        HStack(spacing: 16) {
            // Миниатюра фото
            if let fileName = item.photoFileName,
               let image = storage.loadPhoto(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    // Тап открывает фото на весь экран с зумом
                    .zoomablePhoto(image)
            }
            
            // Описание предмета
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.headline)
                
                if let aiDesc = item.aiDescription {
                    Text("Recognized: \(aiDesc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if let userDesc = item.userDescription {
                    Text("Your description: \(userDesc)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Дополнительный комментарий
    
    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Additional comment (optional)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            TextField("e.g. I found this item at a grocery store...", text: $userComment, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .focused($isCommentFocused)
        }
    }
    
    // MARK: - Информация об отправке
    
    private var emailInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The email will be sent to:", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(AppConfig.requestEmail)
                .font(.caption)
                .fontWeight(.medium)
            
            // Показываем обратный email, если заполнен в профиле
            let profile = storage.loadProfile()
            if profile.hasEmail {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.caption2)
                    Text("Reply to: \(profile.email ?? "")")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                    Text("Add your email in Profile to receive a response.")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    // MARK: - Кнопки действий
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            // Кнопка отправки email
            Button {
                showMailComposer = true
            } label: {
                Label("Send suggestion", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(MailComposer.canSendMail ? .blue : .gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!MailComposer.canSendMail)
            
            // Предупреждение, если почта не настроена
            if !MailComposer.canSendMail {
                Text("Mail is not configured on this device. Please set up a mail account in Settings.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Кнопка отмены
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.gray.opacity(0.15))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Формирование текста письма
    
    /// Собираем тело email из описания предмета, комментария и данных пользователя.
    private func buildEmailBody() -> String {
        let profile = storage.loadProfile()
        
        var body = "Hello,\n\n"
        body += "I would like to suggest adding the following item to the recycling database.\n\n"
        
        // Описание предмета
        body += "Item: \(item.displayName)\n"
        
        if let aiDesc = item.aiDescription {
            body += "AI recognition: \(aiDesc)\n"
        }
        
        if let userDesc = item.userDescription {
            body += "User description: \(userDesc)\n"
        }
        
        // Комментарий пользователя
        if !userComment.isEmpty {
            body += "\nAdditional comment: \(userComment)\n"
        }
        
        // Данные пользователя для обратной связи
        body += "\n---\n"
        
        if let name = profile.name, !name.isEmpty {
            body += "Name: \(name)\n"
        }
        
        if let email = profile.email, !email.isEmpty {
            body += "Email: \(email)\n"
        }
        
        if let phone = profile.phone, !phone.isEmpty {
            body += "Phone: \(phone)\n"
        }
        
        body += "\nSent from RecycleCheck app"
        
        return body
    }
    
    // MARK: - Формирование вложений (фото)
    
    /// Создаём массив вложений для email — фото предмета в формате JPEG.
    private func buildAttachments() -> [(Data, String, String)] {
        var attachments: [(Data, String, String)] = []
        
        if let fileName = item.photoFileName,
           let photoData = storage.photoData(named: fileName) {
            attachments.append((photoData, "image/jpeg", "item_photo.jpg"))
        }
        
        return attachments
    }
}

#Preview {
    NavigationStack {
        SuggestItemView(
            item: RecycleItem(userDescription: "old sneakers")
        )
    }
}
