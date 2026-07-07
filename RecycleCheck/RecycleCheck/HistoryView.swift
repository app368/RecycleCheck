import SwiftUI

// MARK: - Экран истории проверок (СП7.1 + СП7.3)
// Отображает список всех проверок пользователя.
// Поддерживает удаление: свайп (одна), Edit Mode (несколько), Delete All (все).
// Навигация к деталям записи — по тапу (СП7.2).

struct HistoryView: View {
    
    /// Массив записей истории
    @State private var history: [CheckHistoryEntry] = []
    
    /// Набор выбранных записей в режиме редактирования
    @State private var selectedEntries: Set<UUID> = []
    
    /// Режим редактирования списка (множественный выбор)
    @State private var editMode: EditMode = .inactive
    
    /// Флаг показа алерта подтверждения удаления всех записей
    @State private var showDeleteAllAlert = false
    
    /// Флаг показа алерта подтверждения удаления выбранных записей
    @State private var showDeleteSelectedAlert = false
    
    var body: some View {
        Group {
            if history.isEmpty {
                // MARK: - Заглушка для пустой истории
                emptyStateView
            } else {
                // MARK: - Список записей (СП7.1)
                historyListView
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            // Кнопка Edit/Done — только если есть записи
            if !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .environment(\.editMode, $editMode)
        .onAppear {
            loadHistory()
        }
    }
    
    // MARK: - Заглушка для пустой истории
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No checks yet")
                .font(.title3)
                .foregroundStyle(.secondary)
            
            Text("Your check history will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
    }
    
    // MARK: - Список записей
    
    private var historyListView: some View {
        List(selection: $selectedEntries) {
            // MARK: - Секция записей
            ForEach(history) { entry in
                NavigationLink {
                    // Переход к деталям записи (СП7.2)
                    HistoryDetailView(entry: entry)
                } label: {
                    HistoryRowView(entry: entry)
                }
            }
            .onDelete(perform: deleteBySwipe)
            
            // MARK: - Кнопки удаления внизу списка
            Section {
                // Удаление выбранных — видна только в режиме Edit
                if editMode == .active {
                    Button(role: .destructive) {
                        showDeleteSelectedAlert = true
                    } label: {
                        Label("Delete selected (\(selectedEntries.count))",
                              systemImage: "trash")
                    }
                    .disabled(selectedEntries.isEmpty)
                }
                
                // Удаление всех — видна всегда
                Button(role: .destructive) {
                    showDeleteAllAlert = true
                } label: {
                    Label("Delete all", systemImage: "trash.fill")
                }
            }
        }
        .listStyle(.insetGrouped)
        // Алерт: удаление всех записей
        .alert("Delete all history?",
               isPresented: $showDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) {
                deleteAll()
            }
        } message: {
            Text("This will permanently remove all \(history.count) entries and their photos.")
        }
        // Алерт: удаление выбранных записей
        .alert("Delete selected entries?",
               isPresented: $showDeleteSelectedAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete (\(selectedEntries.count))", role: .destructive) {
                deleteSelected()
            }
        } message: {
            Text("This will permanently remove \(selectedEntries.count) selected entries and their photos.")
        }
    }
    
    // MARK: - Загрузка истории из хранилища
    
    private func loadHistory() {
        history = StorageService.shared.loadHistory()
    }
    
    // MARK: - Удаление свайпом (одна запись) (СП7.3)
    
    private func deleteBySwipe(at offsets: IndexSet) {
        for index in offsets {
            let entry = history[index]
            StorageService.shared.deleteHistoryEntry(id: entry.id)
        }
        loadHistory()
    }
    
    // MARK: - Удаление выбранных записей (СП7.3)
    
    private func deleteSelected() {
        StorageService.shared.deleteHistoryEntries(ids: selectedEntries)
        selectedEntries.removeAll()
        editMode = .inactive
        loadHistory()
    }
    
    // MARK: - Удаление всех записей (СП7.3)
    
    private func deleteAll() {
        StorageService.shared.deleteAllHistory()
        selectedEntries.removeAll()
        editMode = .inactive
        loadHistory()
    }
}

// MARK: - Строка списка истории

/// Одна строка в списке: миниатюра, название, статус, дата
struct HistoryRowView: View {
    
    let entry: CheckHistoryEntry
    
    var body: some View {
        HStack(spacing: 12) {
            // Миниатюра фото
            photoThumbnail
            
            // Информация о проверке
            VStack(alignment: .leading, spacing: 4) {
                // Название предмета
                Text(entry.item.displayName)
                    .font(.body)
                    .lineLimit(1)
                
                // Статус проверки
                statusBadge
                
                // Дата проверки
                Text(entry.checkedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Миниатюра фотографии
    
    private var photoThumbnail: some View {
        Group {
            if let fileName = entry.item.photoFileName,
               let image = StorageService.shared.loadPhoto(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray6))
        )
    }
    
    // MARK: - Бейдж статуса
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .font(.caption)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(statusColor)
    }
    
    /// Иконка статуса
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
    
    /// Текст статуса
    private var statusText: String {
        entry.result?.status.rawValue ?? "Not checked"
    }
    
    /// Цвет статуса
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

#Preview {
    NavigationStack {
        HistoryView()
    }
}
