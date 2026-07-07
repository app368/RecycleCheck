import SwiftUI

// MARK: - Экран деталей записи истории (СП7.2)
// Показывает полную информацию о проверке:
// фото предмета, описания (пользовательское и AI),
// статус, доказательство с сайта, дата, отправка email.

struct HistoryDetailView: View {
    
    /// Запись из истории проверок
    let entry: CheckHistoryEntry
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Фотография предмета
                photoSection
                
                // MARK: - Статус проверки
                statusSection
                
                // MARK: - Описания предмета
                descriptionsSection
                
                // MARK: - Подтверждение вердикта (СП4.1) или старый evidence
                confirmationOrEvidenceSection
                
                // MARK: - Информация о проверке
                infoSection
            }
            .padding()
        }
        .navigationTitle("Check details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Секция фотографии
    
    private var photoSection: some View {
        Group {
            if let fileName = entry.item.photoFileName,
               let image = StorageService.shared.loadPhoto(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                // Заглушка, если фото нет
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
    
    // MARK: - Секция статуса
    
    private var statusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.title2)
            Text(statusText)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .foregroundStyle(statusColor)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Секция описаний
    
    private var descriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Описание от AI (СП2)
            if let aiDesc = entry.item.aiDescription, !aiDesc.isEmpty {
                DetailCard(
                    title: "AI description",
                    icon: "brain",
                    content: aiDesc
                )
            }
            
            // Описание от пользователя
            if let userDesc = entry.item.userDescription, !userDesc.isEmpty {
                DetailCard(
                    title: "Your description",
                    icon: "text.quote",
                    content: userDesc
                )
            }
        }
    }
    
    // MARK: - Подтверждение вердикта (СП4.1)

    /// Единый путь для всех записей: секция подтверждения + свёрнутый evidence.
    /// Если confirmation в записи нет (догрузка не удалась или запись старая) —
    /// показываем «Confirmation unavailable», evidence остаётся доступен ниже.
    /// В истории догрузки нет: показываем то, что было сохранено при проверке.
    @ViewBuilder
    private var confirmationOrEvidenceSection: some View {
        // Для notFound подтверждения не бывает — секцию не показываем
        if let result = entry.result, result.status != .notFound {
            if let confirmation = result.confirmation {
                ConfirmationSectionView(state: .loaded(confirmation))
            } else {
                ConfirmationSectionView(state: .unavailable)
            }
        }

        // Сырой evidence — заметная кнопка с разворачиванием, где он есть
        if let evidence = entry.result?.evidence, !evidence.isEmpty {
            RawEvidenceDisclosure(evidence: evidence)
        }
    }
    
    // MARK: - Секция информации
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Дата проверки
            InfoRow(
                label: "Checked",
                value: entry.checkedAt.formatted(
                    .dateTime.day().month(.wide).year().hour().minute()
                )
            )
            
            // Источник (URL страницы)
            if let sourceURL = entry.result?.sourceURL, !sourceURL.isEmpty {
                InfoRow(label: "Source", value: sourceURL)
            }
            
            // Статус отправки email (СП5)
            InfoRow(
                label: "Email sent",
                value: entry.emailSent ? "Yes" : "No"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Вспомогательные свойства статуса
    
    private var statusIcon: String {
        switch entry.result?.status {
        case .recyclable:
            return "checkmark.circle.fill"
        case .notRecyclable:
            return "xmark.circle.fill"
        case .notFound, .none:
            return "questionmark.circle.fill"
        }
    }
    
    private var statusText: String {
        entry.result?.status.rawValue ?? "Not checked"
    }
    
    private var statusColor: Color {
        switch entry.result?.status {
        case .recyclable:
            return .green
        case .notRecyclable:
            return .red
        case .notFound, .none:
            return .orange
        }
    }
}

// MARK: - Карточка с деталями

/// Переиспользуемая карточка для отображения блока информации
struct DetailCard: View {
    let title: String
    let icon: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Заголовок карточки
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontWeight(.medium)
            
            // Содержимое
            Text(content)
                .font(.body)
                // Долгое нажатие — системное меню: Copy / Translate / Share
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Строка информации

/// Строка «Метка: Значение»
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(
            entry: CheckHistoryEntry(
                item: RecycleItem(userDescription: "Plastic bottle"),
                result: SearchResult(
                    status: .recyclable,
                    evidence: "Plastic bottles (PET #1) are widely accepted in curbside recycling programs."
                )
            )
        )
    }
}
