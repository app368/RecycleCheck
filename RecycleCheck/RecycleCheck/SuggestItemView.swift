import SwiftUI

// MARK: - Экран вопроса команде сайта (СП5)
// Приложение не нашло предмет в списках сайта — пользователь может
// вежливо СПРОСИТЬ команду сайта, пригоден ли предмет к переработке
// (не предложить добавить его — решение остаётся за сайтом).
// В письмо вкладываются:
// — фото предмета
// — описание (опционально, может дополнить пользователь)
// — обратный email пользователя (из профиля СП6, если заполнен)

struct SuggestItemView: View {
    
    /// Предмет, который не найден на сайте
    let item: RecycleItem

    /// Текст письма — заготовка, пользователь может отредактировать
    @State private var emailBody: String = ""
    
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
            VStack(spacing: 20) {

                // MARK: - Превью предмета (фото + описание, сразу первым блоком)

                itemPreview

                // MARK: - Текст письма (редактируемый, с готовой заготовкой)

                emailBodySection

                // MARK: - Информация об отправке

                emailInfoSection

                // MARK: - Кнопки действий

                actionsSection
            }
            .padding()
        }
        .navigationTitle("Question about")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if emailBody.isEmpty {
                emailBody = defaultEmailBody()
            }
        }
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
                subject: "Recycling question: \(item.displayName)",
                body: emailBody,
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
                 ? "Your question has been sent. Thank you!"
                 : "The email was not sent. You can try again.")
        }
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
        // Синий фон — экран «неясно»/уточнение, тот же тон по приложению
        .background(.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Текст письма (редактируемый, с готовой заготовкой)

    private var emailBodySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email text (you can edit it)")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextField("", text: $emailBody, axis: .vertical)
                .lineLimit(10...20)
                .textFieldStyle(.plain)
                .focused($isCommentFocused)
                .padding(10)
                // Лёгкий синий фон — тон «неясно»/уточнение по приложению
                .background(.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                Label("Send question", systemImage: "paperplane.fill")
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
    
    // MARK: - Заготовка текста письма

    /// Готовый текст письма — вежливый вопрос команде сайта, не предложение
    /// добавить предмет. Пользователь может отредактировать перед отправкой.
    /// Подпись — имя из профиля (СП6), если заполнено
    private func defaultEmailBody() -> String {
        let profile = storage.loadProfile()
        let name = profile.name?.isEmpty == false ? profile.name! : "[Name]"

        return """
        Hello,

        My app didn't find information about this item in the "Allowed" and \
        "Not Allowed" recycling lists on your website.

        Could you let me know whether this item is recyclable? If there are \
        any exceptions or preparation steps, that would be very helpful too.

        I'm attaching a photo of the item and a short description generated \
        by the app.

        Thank you for your time,
        \(name)
        """
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
