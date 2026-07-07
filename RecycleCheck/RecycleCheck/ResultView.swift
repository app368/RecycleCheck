import SwiftUI

// MARK: - Экран результатов проверки (СП4)
// Отображает результат поиска предмета на сайте:
// — статус (пригоден / не пригоден / не найден)
// — доказательство с сайта (текст)
// — фото предмета
// Если предмет не найден — кнопка перехода к отправке запроса (СП5).

struct ResultView: View {
    
    /// Проверяемый предмет (из СП1 + СП2)
    let item: RecycleItem
    
    /// Результат поиска на сайте (из СП3)
    let result: SearchResult
    
    /// Флаг перехода к отправке email (СП5)
    @State private var showEmailComposer = false
    
    @Environment(\.dismiss) private var dismiss
    
    private let storage = StorageService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - Иконка статуса
                
                statusIcon
                
                // MARK: - Название предмета
                
                Text(item.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                // MARK: - Статус пригодности
                
                statusBadge
                
                // MARK: - Фото предмета
                
                itemPhoto
                
                // MARK: - Доказательство с сайта
                
                evidenceSection
                
                // MARK: - Кнопки действий
                
                actionsSection
            }
            .padding()
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)
        
        // MARK: - Переход к отправке email (СП5)
        
        .navigationDestination(isPresented: $showEmailComposer) {
            SuggestItemView(item: item)
        }
    }
    
    // MARK: - Иконка статуса (большая, по центру)
    
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 100, height: 100)
            
            Image(systemName: statusSystemImage)
                .font(.system(size: 44))
                .foregroundStyle(statusColor)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Бейдж со статусом
    
    private var statusBadge: some View {
        Text(result.status.rawValue)
            .font(.headline)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
    }
    
    // MARK: - Фото предмета
    
    @ViewBuilder
    private var itemPhoto: some View {
        if let fileName = item.photoFileName,
           let image = storage.loadPhoto(named: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Секция доказательства с сайта
    
    @ViewBuilder
    private var evidenceSection: some View {
        if let evidence = result.evidence, !evidence.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Evidence from website", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Text(evidence)
                    .font(.body)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        
        // Ссылка на источник
        if let sourceURL = result.sourceURL {
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption)
                Text("Source: \(sourceURL)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .foregroundStyle(.blue)
        }
    }
    
    // MARK: - Кнопки действий
    
    private var actionsSection: some View {
        VStack(spacing: 12) {
            
            // Если предмет не найден — предлагаем отправить запрос (СП5)
            if result.status == .notFound {
                Button {
                    showEmailComposer = true
                } label: {
                    Label("Suggest adding this item", systemImage: "envelope.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            
            // Кнопка возврата на главный экран
            Button {
                // Возвращаемся к корневому экрану
                dismiss()
            } label: {
                Text("Done")
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
    
    // MARK: - Вспомогательные свойства для стилизации по статусу
    
    /// Цвет, соответствующий статусу
    private var statusColor: Color {
        switch result.status {
        case .recyclable:
            return .green
        case .notRecyclable:
            return .red
        case .notFound:
            return .orange
        }
    }
    
    /// SF Symbol, соответствующий статусу
    private var statusSystemImage: String {
        switch result.status {
        case .recyclable:
            return "checkmark.circle.fill"
        case .notRecyclable:
            return "xmark.circle.fill"
        case .notFound:
            return "questionmark.circle.fill"
        }
    }
}

#Preview("Recyclable") {
    NavigationStack {
        ResultView(
            item: RecycleItem(userDescription: "plastic water bottle"),
            result: SearchResult(
                status: .recyclable,
                evidence: "Plastic bottles (PET #1) are widely accepted in curbside recycling programs. Rinse and remove the cap before placing in the recycling bin.",
                sourceURL: "https://example-recycling-site.com"
            )
        )
    }
}

#Preview("Not found") {
    NavigationStack {
        ResultView(
            item: RecycleItem(userDescription: "old sneakers"),
            result: SearchResult(status: .notFound)
        )
    }
}
