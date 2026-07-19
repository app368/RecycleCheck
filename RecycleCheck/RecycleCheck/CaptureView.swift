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

    /// ID сохранённой записи истории — для дозаписи confirmation в ResultView (СП4.1)
    @State private var historyEntryID: UUID?

    /// Якоря и состояние плавающей стрелки на этапе описания предмета
    private let topAnchorID = "capture-top"
    private let bottomAnchorID = "capture-bottom"
    @State private var isAtBottom = false
    
    /// Фокус для управления клавиатурой
    @FocusState private var focusedField: RecognitionField?
    
    /// Перечисление полей для управления фокусом
    enum RecognitionField {
        case material, itemType, contentsUse
    }
    
    @Environment(\.dismiss) private var dismiss

    /// Акцентный цвет экрана распознавания — сиреневый: ассоциация с ИИ
    /// (Siri, Apple Intelligence). Все кнопки экрана — в нём; зелёный,
    /// красный и синий заняты экранами результата
    private let accent = Color(red: 0.62, green: 0.46, blue: 0.86)

    private let storage = StorageService.shared
    private let visionService = VisionService.shared

    private var isShowingItemDescription: Bool {
        recognition?.isApplicable == true
    }

    /// Заголовок отражает текущий этап одного и того же экрана:
    /// добавление фото, распознавание, затем описание предмета.
    private var pageTitle: LocalizedStringKey {
        if isShowingItemDescription {
            return "Item Description"
        }

        return capturedImage == nil ? "Take Photo" : "Recognize Item"
    }
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // До распознавания элементов мало — им свободнее (24);
                // с карточкой описания — плотнее (14), чтобы кнопка проверки
                // помещалась на экране вместе с фото
                VStack(spacing: recognition == nil ? 24 : 14) {

                    // MARK: - Область фотографии

                    photoSection
                        .id(topAnchorID)

                    // MARK: - Кнопки выбора источника фото (до распознавания)

                    if recognition == nil && !isRecognizing {
                        sourceButtons
                            // Дополнительный воздух между фото и кнопками источника
                            .padding(.top, 12)
                    }

                    // MARK: - Кнопка распознавания (Шаг 1)

                    if capturedImage != nil && recognition == nil && !isRecognizing {
                        recognizeButton
                            // Вдвое больше обычного отступа от кнопок Camera/Gallery
                            .padding(.top, 24)
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

                            // Маркер конца контента управляет направлением стрелки
                            Color.clear
                                .frame(height: 12)
                                .id(bottomAnchorID)
                                .onScrollVisibilityChange(threshold: 0.5) { visible in
                                    isAtBottom = visible
                                }
                        } else {
                            // Категория bulky / otherObjects / unclear → плашка с сообщением
                            rejectionCard(recognition: recognition)
                        }
                    }
                }
                .padding()
            }
            .overlay(alignment: .bottomTrailing) {
                if isShowingItemDescription && focusedField == nil {
                    ScrollJumpButton(
                        isAtBottom: isAtBottom,
                        tint: accent
                    ) {
                        withAnimation {
                            proxy.scrollTo(
                                isAtBottom ? topAnchorID : bottomAnchorID,
                                anchor: isAtBottom ? .top : .bottom
                            )
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            }
        }
        .pinnedLargeNavigationTitle(pageTitle)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
            
            // Кнопка замены фото — возвращает к выбору камеры или галереи.
            // Сиреневая капсула с белым текстом (как Done на экране результата)
            if recognition != nil || capturedImage != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        resetAll()
                    } label: {
                        Text("Replace Photo")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 6)
                            .background(accent)
                            .clipShape(Capsule())
                    }
                    // Без стандартной подложки навбара — иначе капсула
                    // сидит внутри белого фона
                    .buttonStyle(.plain)
                }
                .sharedBackgroundVisibility(.hidden)
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
                ResultView(item: item, result: result, historyEntryID: historyEntryID)
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
                    // До распознавания места много — фото крупнее;
                    // с карточкой описания — компактнее
                    .frame(maxHeight: recognition == nil ? 300 : 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // Тап открывает фото на весь экран с зумом.
                    // Подключено до оверлеев — кнопка смены фото сверху остаётся рабочей
                    .zoomablePhoto(image)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    )
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
                    .background(accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            Button {
                showPhotoLibrary = true
            } label: {
                Label("Gallery", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(accent)
                    .foregroundStyle(.white)
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
            .background(accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Индикатор распознавания
    
    private var recognizingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(accent)
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
        VStack(alignment: .leading, spacing: 12) {
            // Подсказка о редактировании — по центру, заметная.
            // Заголовок «Item recognized» убран: заполненное описание
            // само говорит о распознавании
            Text("You can edit this description")
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .center)

            // Пояснение про запятые — обычным шрифтом, по левому краю,
            // с отступом от строки выше
            Text("Separate multiple values with commas.")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            // Повторное распознавание — по центру под подсказкой:
            // фото остаётся, прежнее описание заменяется новым
            HStack {
                Spacer()
                Button {
                    recognition = nil
                    startRecognition()
                } label: {
                    Text("Recognize Again")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(accent)
                        .clipShape(Capsule())
                }
                Spacer()
            }

            // Поле: Материал
            VStack(alignment: .leading, spacing: 4) {
                Text("Material type")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("e.g. plastic, glass, metal...", text: $editMaterial)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .material)
            }
            .padding(.top, 16)

            // Поле: Название предмета
            VStack(alignment: .leading, spacing: 4) {
                Text("Item name")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("e.g. bottle, container, bag...", text: $editItemType)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .itemType)
            }

            // Поле: Содержимое / назначение
            VStack(alignment: .leading, spacing: 4) {
                Text("Contents / Intended use")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                TextField("e.g. beverage, food, dairy, cleaning...", text: $editContentsUse)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .focused($focusedField, equals: .contentsUse)
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
                    Text("Checking website…")
                } else {
                    Image(systemName: "magnifyingglass")
                    Text("Check for recycling")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(canSearch && !isSearching ? accent : .gray)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!canSearch || isSearching)
    }
    
    /// Можно ли запускать поиск — хотя бы itemType заполнен
    private var canSearch: Bool {
        !editItemType.trimmingCharacters(in: .whitespaces).isEmpty
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
                    let friendly = friendlyError(from: error)
                    errorMessage = friendly.message.isEmpty
                        ? friendly.title
                        : "\(friendly.title). \(friendly.message)"
                    showError = true
                }
            }
        }
    }

    // MARK: - Шаг 2: Вердикт по базе списков (П3)

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

            // MARK: Вердикт по базе списков (П3)
            // Сайт не читается: один вопрос к Claude «есть ли предмет в списках».
            // Единственная ошибка, которую показываем, — база ещё не собрана
            // (предложить Refresh); сетевые сбои внутри дают исход «неясно»

            let result: SearchResult

            do {
                result = try await VerdictService.shared.decideVerdict(for: finalRecognition)
            } catch {
                await MainActor.run {
                    isSearching = false
                    let friendly = friendlyError(from: error)
                    errorMessage = friendly.message.isEmpty
                        ? friendly.title
                        : "\(friendly.title). \(friendly.message)"
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
                historyEntryID = historyEntry.id
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
        historyEntryID = nil
        isAtBottom = false
    }
}

#Preview {
    NavigationStack {
        CaptureView()
    }
}
