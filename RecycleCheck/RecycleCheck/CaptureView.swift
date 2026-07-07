import SwiftUI

// MARK: - Экран захвата предмета (СП1)
// Двухэтапный процесс распознавания:
// Этап 1 (грубый отсев): фото → AI классифицирует → item / bulky / otherObjects / unclear
// Если item → Этап 2 (детальное): карточка с material/itemType/contentsUse → поиск
// Если не item → плашка с сообщением + кнопка «Try another photo»

struct CaptureView: View {
    
    /// Выбранное фото предмета
    @State private var capturedImage: UIImage?
    
    /// Результат распознавания от AI
    @State private var recognition: ItemRecognition?
    
    /// Редактируемые поля карточки распознавания (только для category == .item)
    @State private var editMaterial: String = ""
    @State private var editItemType: String = ""
    @State private var editContentsUse: String = ""
    
    /// Управление показом камеры / галереи
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    
    /// Флаг перехода к экрану результатов (СП4)
    @State private var showResults = false
    
    /// Созданный предмет для передачи в следующие суб-процессы
    @State private var recycleItem: RecycleItem?
    
    /// Состояние загрузки
    @State private var isRecognizing = false
    @State private var isSearching = false
    
    /// Текст ошибки для отображения пользователю
    @State private var errorMessage: String?
    @State private var showError = false
    
    /// Результат поиска на сайте (СП3) — передаётся в экран результатов (СП4)
    @State private var searchResult: SearchResult?
    
    /// Фокус для управления клавиатурой
    @FocusState private var focusedField: RecognitionField?
    
    /// Перечисление полей для управления фокусом
    enum RecognitionField {
        case material, itemType, contentsUse
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private let storage = StorageService.shared
    private let visionService = VisionService.shared
    private let scrapingService = WebScrapingService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - Область фотографии
                
                photoSection
                
                // MARK: - Кнопки выбора источника фото (до распознавания)
                
                if recognition == nil && !isRecognizing {
                    sourceButtons
                }
                
                // MARK: - Кнопка распознавания (Шаг 1)
                
                if capturedImage != nil && recognition == nil && !isRecognizing {
                    recognizeButton
                }
                
                // MARK: - Индикатор распознавания
                
                if isRecognizing {
                    recognizingIndicator
                }
                
                // MARK: - Результат распознавания
                
                if let recognition = recognition {
                    if recognition.isApplicable {
                        // Категория item → карточка с редактированием + кнопка Search
                        recognitionCard
                        searchButton
                        
                        // ВРЕМЕННО: тест ConfirmationCollector (СП4.1)
                        testCollectorButton
                    } else {
                        // Категория bulky / otherObjects / unclear → плашка с сообщением
                        rejectionCard(recognition: recognition)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Check an item")
        .navigationBarTitleDisplayMode(.large)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
            
            // Кнопка сброса — позволяет начать заново
            if recognition != nil || capturedImage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Reset") {
                        resetAll()
                    }
                }
            }
        }
        
        // MARK: - Модальные окна камеры и галереи
        
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                capturedImage = image
                recognition = nil
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(sourceType: .photoLibrary) { image in
                capturedImage = image
                recognition = nil
            }
        }
        
        // MARK: - Переход к результатам (СП4)
        
        .navigationDestination(isPresented: $showResults) {
            if let item = recycleItem, let result = searchResult {
                ResultView(item: item, result: result)
            }
        }
        
        // MARK: - Уведомление об ошибке
        
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Something went wrong. Please try again.")
        }
    }
    
    // MARK: - Секция фотографии
    
    private var photoSection: some View {
        Group {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    )
                    // Кнопка смены фото — только до распознавания
                    .overlay(alignment: .topTrailing) {
                        if recognition == nil && !isRecognizing {
                            Button {
                                capturedImage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .padding(8)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.1))
                    .frame(height: 220)
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.secondary)
                            Text("Take or select a photo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }
    
    // MARK: - Кнопки камеры и галереи
    
    private var sourceButtons: some View {
        HStack(spacing: 16) {
            Button {
                showCamera = true
            } label: {
                Label("Camera", systemImage: "camera")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.green.opacity(0.1))
                    .foregroundStyle(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
            
            Button {
                showPhotoLibrary = true
            } label: {
                Label("Gallery", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    
    // MARK: - Кнопка распознавания
    
    private var recognizeButton: some View {
        Button {
            startRecognition()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain")
                Text("Recognize item")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.green)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Индикатор распознавания
    
    private var recognizingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(.green)
            Text("Recognizing...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    
    // MARK: - Карточка распознавания для category == .item (редактируемая)
    
    private var recognitionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Заголовок карточки
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Item recognized")
                    .font(.headline)
                Spacer()
                Button {
                    recognition = nil
                } label: {
                    Text("Retake")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            Text("Review and edit if needed:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Поле: Материал
            VStack(alignment: .leading, spacing: 4) {
                Text("Material type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                TextField("e.g. plastic, glass, metal...", text: $editMaterial)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .material)
            }
            
            // Поле: Название предмета
            VStack(alignment: .leading, spacing: 4) {
                Text("Item name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                TextField("e.g. bottle, container, bag...", text: $editItemType)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .itemType)
            }
            
            // Поле: Содержимое / назначение
            VStack(alignment: .leading, spacing: 4) {
                Text("Contents / Intended use")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
                TextField("e.g. beverage, food, dairy, cleaning...", text: $editContentsUse)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .contentsUse)
                Text("Separate with commas")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Плашка отказа для bulky / otherObjects / unclear
    
    private func rejectionCard(recognition: ItemRecognition) -> some View {
        VStack(spacing: 16) {
            // Иконка категории
            Image(systemName: rejectionIcon(for: recognition.category))
                .font(.system(size: 36))
                .foregroundStyle(rejectionColor(for: recognition.category))
            
            // Сообщение
            Text(recognition.rejectionMessage ?? "")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            
            // Кнопка «Попробовать другое фото»
            Button {
                resetAll()
            } label: {
                Label("Try another photo", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.green)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    /// Иконка для плашки отказа
    private func rejectionIcon(for category: RecognitionCategory) -> String {
        switch category {
        case .bulky:
            return "shippingbox.fill"
        case .otherObjects:
            return "photo.badge.exclamationmark"
        case .unclear:
            return "eye.slash.fill"
        case .item:
            return "checkmark.circle.fill"
        }
    }
    
    /// Цвет для плашки отказа
    private func rejectionColor(for category: RecognitionCategory) -> Color {
        switch category {
        case .bulky:
            return .orange
        case .otherObjects:
            return .blue
        case .unclear:
            return .gray
        case .item:
            return .green
        }
    }
    
    // MARK: - Кнопка поиска (Шаг 2, только для item)
    
    private var searchButton: some View {
        Button {
            startSearch()
        } label: {
            HStack(spacing: 8) {
                if isSearching {
                    ProgressView()
                        .tint(.white)
                    Text("Searching website...")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSearch && !isSearching ? .green : .gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSearch || isSearching)
    }
    
    /// Можно ли запускать поиск — хотя бы itemType заполнен
    private var canSearch: Bool {
        !editItemType.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    // MARK: - ВРЕМЕННО: Кнопка теста ConfirmationCollector (СП4.1)
    // Удалить после проверки сервиса.
    
    private var testCollectorButton: some View {
        Button {
            runConfirmationCollectorTest()
        } label: {
            Label("Test Collector", systemImage: "ladybug")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(.orange.opacity(0.15))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(!canSearch)
    }
    
    // MARK: - ВРЕМЕННО: Тестовая функция ConfirmationCollector (СП4.1)
    // Запускает сбор упоминаний на тех же целевых URL, что используются
    // для основного поиска, и печатает результаты в консоль Xcode.
    // Использует finalRecognition, собранный из отредактированных полей —
    // так же, как это делает startSearch.
    
    private func runConfirmationCollectorTest() {
        // Получаем текущий URL сайта переработки из настроек
        let baseURL = AppConfig.recyclingWebsiteURL
        
        // Получаем кэшированные целевые URL для этого сайта
        guard let targetURLs = storage.loadTargetURLs(forBaseURL: baseURL),
              !targetURLs.isEmpty else {
            print("⚠️ ConfirmationCollector test: no target URLs in cache")
            return
        }
        
        // Собираем finalRecognition из отредактированных полей —
        // та же логика, что в startSearch
        let materialValue = editMaterial.trimmingCharacters(in: .whitespaces).lowercased()
        let contents = editContentsUse
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        
        let testRecognition = ItemRecognition(
            category: .item,
            material: materialValue == "not applicable" ? "N/A" : materialValue,
            itemType: editItemType.trimmingCharacters(in: .whitespaces).lowercased(),
            contentsUse: contents.isEmpty ? ["N/A"] : contents
        )
        
        print("\n🟡 ConfirmationCollector test started")
        print("   Item: \(testRecognition.displayName)")
        print("   Material: \(testRecognition.material), Type: \(testRecognition.itemType)")
        print("   Contents: \(testRecognition.contentsUse.joined(separator: ", "))")
        print("   Target URLs: \(targetURLs.count)")
        
        Task {
            do {
                let startTime = Date()
                let mentions = try await ConfirmationCollector.shared
                    .collectMentions(for: testRecognition, on: targetURLs)
                let elapsed = Date().timeIntervalSince(startTime)
                
                print("\n🟢 Collected \(mentions.count) mentions in \(String(format: "%.2f", elapsed))s")
                
                // Сводка по объёму
                let totalChars = mentions.reduce(0) { $0 + $1.text.count }
                let totalScore = mentions.reduce(0) { $0 + $1.score }
                print("   Total characters: \(totalChars)")
                print("   Total score: \(totalScore)")
                
                // Подробности по каждому упоминанию
                for (i, mention) in mentions.enumerated() {
                    print("\n   [\(i + 1)] score=\(mention.score), \(mention.text.count) chars")
                    print("       source: \(mention.sourceURL)")
                    let preview = mention.text.prefix(250)
                    let suffix = mention.text.count > 250 ? "..." : ""
                    print("       text: \(preview)\(suffix)")
                }
                
                print("\n🟡 ConfirmationCollector test finished\n")
                
                // MARK: Тест ConfirmationService — анализ упоминаний через Claude AI
                
                // Для теста используем фиктивный вердикт RECYCLABLE.
                // В боевом режиме сюда придёт реальный вердикт из СП3.
                // Если хочешь протестировать NOT RECYCLABLE — замени .recyclable
                // на .notRecyclable и проверь, что exceptions/preparation
                // станут "Not applicable".
                let testVerdict: RecycleStatus = .recyclable
                
                print("🟡 ConfirmationService test started")
                print("   Verdict (test): \(testVerdict.rawValue)")
                
                let confirmationStartTime = Date()
                
                do {
                    let confirmation = try await ConfirmationService.shared
                        .makeConfirmation(
                            from: mentions,
                            recognition: testRecognition,
                            verdict: testVerdict
                        )
                    let confirmationElapsed = Date().timeIntervalSince(confirmationStartTime)
                    
                    print("\n🟢 Confirmation received in \(String(format: "%.2f", confirmationElapsed))s")
                    print("\n   📌 Citation:")
                    print("      \(confirmation.citation)")
                    print("\n   ⚠️  Exceptions:")
                    print("      \(confirmation.exceptions)")
                    print("\n   🛠  Preparation:")
                    print("      \(confirmation.preparation)")
                    
                    print("\n🟡 ConfirmationService test finished\n")
                } catch {
                    print("\n🔴 ConfirmationService test failed: \(error.localizedDescription)\n")
                }
            } catch {
                print("\n🔴 ConfirmationCollector test failed: \(error.localizedDescription)\n")
            }
        }
    }
    
    // MARK: - Шаг 1: Распознавание фото через Vision API (СП2)
    
    private func startRecognition() {
        guard let image = capturedImage else { return }
        
        isRecognizing = true
        
        Task {
            do {
                let result = try await visionService.recognizeItem(image: image)
                
                await MainActor.run {
                    recognition = result
                    
                    // Заполняем редактируемые поля только для category == .item
                    if result.isApplicable {
                        editMaterial = result.displayMaterial
                        editItemType = result.itemType
                        editContentsUse = result.displayContentsUse
                    }
                    
                    isRecognizing = false
                }
            } catch {
                await MainActor.run {
                    isRecognizing = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
    
    // MARK: - Шаг 2: Поиск на сайте (СП3)
    
    private func startSearch() {
        guard let image = capturedImage else { return }
        
        isSearching = true
        focusedField = nil
        
        Task {
            // Собираем финальное описание из отредактированных полей
            let materialValue = editMaterial.trimmingCharacters(in: .whitespaces).lowercased()
            let contents = editContentsUse
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            
            let finalRecognition = ItemRecognition(
                category: .item,
                material: materialValue == "not applicable" ? "N/A" : materialValue,
                itemType: editItemType.trimmingCharacters(in: .whitespaces).lowercased(),
                contentsUse: contents.isEmpty ? ["N/A"] : contents
            )
            
            // Сохраняем фото в локальное хранилище
            let photoFileName = storage.savePhoto(image)
            
            // Создаём предмет для проверки
            let item = RecycleItem(
                recognition: finalRecognition,
                photoFileName: photoFileName
            )
            
            // MARK: Поиск на сайте (СП3)
            
            var result: SearchResult
            
            do {
                result = try await scrapingService.searchItem(item)
            } catch {
                await MainActor.run {
                    isSearching = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
                return
            }
            
            // MARK: Сохраняем в историю и переходим к результатам (СП4)
            
            let historyEntry = CheckHistoryEntry(item: item, result: result)
            storage.addHistoryEntry(historyEntry)
            
            await MainActor.run {
                isSearching = false
                recycleItem = item
                searchResult = result
                showResults = true
            }
        }
    }
    
    // MARK: - Сброс всего для нового фото
    
    private func resetAll() {
        capturedImage = nil
        recognition = nil
        editMaterial = ""
        editItemType = ""
        editContentsUse = ""
        recycleItem = nil
        searchResult = nil
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
