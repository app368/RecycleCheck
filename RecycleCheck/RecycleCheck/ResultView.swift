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

    /// ID записи истории — для дозаписи confirmation после догрузки (СП4.1).
    /// nil, если запись истории недоступна (превью) — тогда догрузка не сохраняется.
    var historyEntryID: UUID? = nil

    /// Состояние догрузки подтверждения вердикта (СП4.1)
    @State private var confirmationState: ConfirmationState = .loading

    /// Исправленный вердикт — заполняется, если Claude нашёл противоречие
    /// между вердиктом СП3 и содержимым упоминаний (СП4.1)
    @State private var correctedStatus: RecycleStatus?

    /// Текущий отображаемый статус: исправленный, если была коррекция
    private var currentStatus: RecycleStatus {
        correctedStatus ?? result.status
    }

    /// Флаг показа страницы источника внутри приложения
    @State private var showSourcePage = false

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

                // MARK: - Плашка коррекции вердикта (СП4.1)
                // Поясняет смену бейджа после детальной проверки,
                // чтобы она не выглядела сбоем для пользователя

                if correctedStatus != nil {
                    verdictUpdatedNote
                }
                
                // MARK: - Фото предмета
                
                itemPhoto
                
                // MARK: - Подтверждение вердикта (СП4.1)

                confirmationSection

                // MARK: - Сырой evidence (свёрнут) и ссылка на источник

                rawEvidenceSection

                sourceLink
                
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

        // MARK: - Догрузка подтверждения (СП4.1)
        // Экран открывается сразу, подтверждение подгружается фоном

        .task {
            await loadConfirmationIfNeeded()
        }

        // MARK: - Страница источника внутри приложения

        .sheet(isPresented: $showSourcePage) {
            if let url = sourcePageURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
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
        Text(currentStatus.rawValue)
            .font(.headline)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Плашка «вердикт обновлён» (СП4.1)

    private var verdictUpdatedNote: some View {
        Label("Verdict updated after detailed check", systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.gray.opacity(0.1))
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
    
    // MARK: - Секция подтверждения вердикта (СП4.1)
    // Для notFound секции нет: подтверждать нечего

    @ViewBuilder
    private var confirmationSection: some View {
        if result.status != .notFound {
            ConfirmationSectionView(state: confirmationState)
        }
    }

    // MARK: - Сырой evidence — заметная кнопка с разворачиванием

    @ViewBuilder
    private var rawEvidenceSection: some View {
        if let evidence = result.evidence, !evidence.isEmpty {
            RawEvidenceDisclosure(evidence: evidence)
        }
    }

    // MARK: - Кнопка «Source» — ссылка спрятана под неё

    /// URL страницы источника (если строка корректна)
    private var sourcePageURL: URL? {
        guard let urlString = result.sourceURL else { return nil }
        return URL(string: urlString)
    }

    @ViewBuilder
    private var sourceLink: some View {
        if sourcePageURL != nil {
            Button {
                showSourcePage = true
            } label: {
                Label("Source", systemImage: "safari")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Догрузка подтверждения (СП4.1)

    /// Запускает сбор упоминаний (Collector) и анализ (Service),
    /// затем дозаписывает confirmation в сохранённую запись истории.
    /// Если подтверждение уже есть или статус notFound — ничего не делает.
    private func loadConfirmationIfNeeded() async {
        // Подтверждение пришло готовым — показываем сразу
        if let existing = result.confirmation {
            applyCorrectionIfNeeded(from: existing)
            confirmationState = .loaded(existing)
            return
        }

        // Для notFound секция не отображается — загрузка не нужна
        guard result.status != .notFound else { return }

        // Проверяем исходные данные: распознавание и кэш целевых страниц
        guard let recognition = item.recognition, recognition.isValid,
              let targetURLs = storage.loadTargetURLs(forBaseURL: AppConfig.recyclingWebsiteURL),
              !targetURLs.isEmpty else {
            confirmationState = .unavailable
            return
        }

        do {
            // Шаг 1: локальный сбор упоминаний предмета на целевых страницах
            let mentions = try await ConfirmationCollector.shared
                .collectMentions(for: recognition, on: targetURLs)

            // Шаг 2: анализ упоминаний в Claude AI
            let confirmation = try await ConfirmationService.shared
                .makeConfirmation(
                    from: mentions,
                    recognition: recognition,
                    verdict: result.status
                )

            applyCorrectionIfNeeded(from: confirmation)
            confirmationState = .loaded(confirmation)
            saveConfirmationToHistory(confirmation)
        } catch {
            // Пользователь ушёл с экрана — задача отменена, ошибку не показываем
            guard !Task.isCancelled else { return }
            confirmationState = .unavailable
        }
    }

    /// Применяет коррекцию вердикта, если Claude нашёл противоречие (СП4.1).
    /// Бейдж меняется с анимацией, под ним появляется плашка-пояснение
    private func applyCorrectionIfNeeded(from confirmation: Confirmation) {
        guard let corrected = confirmation.correctedStatus,
              corrected != result.status else { return }
        withAnimation {
            correctedStatus = corrected
        }
    }

    /// Дозапись полученного confirmation в запись истории.
    /// Статус сохраняется с учётом коррекции — история хранит итоговый вердикт
    private func saveConfirmationToHistory(_ confirmation: Confirmation) {
        guard let entryID = historyEntryID else { return }
        var updatedResult = result
        updatedResult.status = currentStatus
        updatedResult.confirmation = confirmation
        storage.updateHistoryResult(entryID: entryID, result: updatedResult)
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
    
    /// Цвет, соответствующий текущему статусу (с учётом коррекции)
    private var statusColor: Color {
        switch currentStatus {
        case .recyclable:
            return .green
        case .notRecyclable:
            return .red
        case .notFound:
            return .orange
        }
    }

    /// SF Symbol, соответствующий текущему статусу (с учётом коррекции)
    private var statusSystemImage: String {
        switch currentStatus {
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
                sourceURL: "https://example-recycling-site.com",
                confirmation: Confirmation(
                    citation: "Plastic bottles, jars, jugs, tubs and buckets go in your blue recycling bin.",
                    exceptions: "No exceptions mentioned",
                    preparation: "Rinse the bottle; caps are OK if screwed on."
                )
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
