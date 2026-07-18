import SwiftUI

// MARK: - Экран настроек
// Пользователь может указать URL сайта переработки
// и email для отправки запросов.
// При сохранении нового URL автоматически запускается
// обнаружение целевых страниц (СП3.1).

struct SettingsView: View {
    
    @State private var websiteURL: String = ""
    @State private var requestEmail: String = ""

    /// Немодальное подтверждение сохранения (вместо алерта «Saved»)
    @State private var savedNote: String?
    
    /// Состояние обнаружения целевых страниц
    @State private var isDiscovering = false
    @State private var discoveryResult: String?
    @State private var showDiscoveryError = false
    @State private var discoveryErrorMessage: String = ""
    
    /// Фокус для управления клавиатурой
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case url, email
    }
    
    private let storage = StorageService.shared

    var body: some View {
        Form {
            // MARK: - Секция сайта переработки
            Section {
                HStack(alignment: .top) {
                    TextField("", text: $websiteURL, axis: .vertical)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                        .lineLimit(3...5)

                    // Кнопка очистки поля
                    if !websiteURL.isEmpty {
                        Button {
                            websiteURL = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Лёгкая зелёная заливка поля
                .listRowBackground(Color.green.opacity(0.08))
            } header: {
                Text("Source recycling website URL")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            } footer: {
                Text("The website where the app searches for recyclable items. You can replace it with your state or local recycling program website for local rules.")
                    .font(.subheadline)
                    .italic()
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // MARK: - Секция email
            Section {
                HStack(alignment: .top) {
                    TextField("", text: $requestEmail, axis: .vertical)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .lineLimit(2...4)

                    // Кнопка очистки поля
                    if !requestEmail.isEmpty {
                        Button {
                            requestEmail = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Лёгкая зелёная заливка поля
                .listRowBackground(Color.green.opacity(0.08))
            } header: {
                Text("Email address of the source website")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            } footer: {
                Text("Enter the email address of the source website's team here. You can use it to ask a question about a specific item.")
                    .font(.subheadline)
                    .italic()
                    .padding(8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // MARK: - Секция обнаружения страниц: статус кэша + Refresh

            if !websiteURL.isEmpty {
                Section {
                    if isDiscovering {
                        // Индикатор прогресса обнаружения — заметный, зелёный
                        // (в тон кнопкам Save/Refresh на этом экране)
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                                .tint(.green)
                            Text("Reading recycling info...")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                    } else if let result = discoveryResult {
                        // Дата последнего получения данных — лёгкая зелёная заливка
                        // самой строки списка (как у текстовых полей), без
                        // вложенной формы поверх карточки секции
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(result)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(Color.green.opacity(0.08))
                    } else {
                        Text("No data yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Принудительное обновление кэша без смены URL
                    Button {
                        startDiscovery(for: AppConfig.recyclingWebsiteURL)
                    } label: {
                        // Яркая зелёная заливка — как кнопка Save
                        Label("Refresh source pages", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .disabled(isDiscovering)
                } header: {
                    Text("Recycling data freshness")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                } footer: {
                    Text("Refresh if the website content has changed. This may take a few minutes.")
                        .font(.subheadline)
                        .italic()
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

        }
        // Свой закреплённый заголовок вместо системного large title,
        // который сворачивается при скролле
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Save — в навбаре справа, закреплена и не уезжает при скролле.
            // Живое подтверждение: кнопка на 2,5 с превращается в «✓ Saved»
            ToolbarItem(placement: .topBarTrailing) {
                saveToolbarButton
            }

            // Кнопка скрытия клавиатуры
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            loadSettings()
        }
        .alert("Rules update failed", isPresented: $showDiscoveryError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(discoveryErrorMessage)
        }
    }
    
    // MARK: - Кнопка Save в навбаре

    /// Приглушённый тёмно-зелёный для состояния «Saved» —
    /// символизирует завершённость операции
    private let savedTint = Color(red: 0.24, green: 0.50, blue: 0.32)

    /// Save в правом верхнем углу. После нажатия на 2,5 секунды
    /// превращается в «✓ Saved» с приглушённой заливкой — реакция на каждое нажатие
    private var saveToolbarButton: some View {
        Button {
            // Защита от повторных нажатий, пока показывается «Saved»
            guard savedNote == nil else { return }
            saveSettings()
        } label: {
            // Одна кнопка с меняющимся содержимым, без анимации перехода —
            // иначе Save и Saved на мгновение видны одновременно
            HStack(spacing: 4) {
                if savedNote != nil {
                    Image(systemName: "checkmark")
                }
                Text(savedNote != nil ? "Saved" : "Save")
            }
            .fontWeight(.semibold)
            // Шире по горизонтали — прямоугольник, а не овал
            .padding(.horizontal, 20)
        }
        // Зелёная заливка с белым текстом; «Saved» — приглушённый тёмно-зелёный;
        // при блокировке — системно-серая
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .tint(savedNote != nil ? savedTint : .green)
        .disabled(isDiscovering)
    }

    // MARK: - Загрузка текущих настроек
    
    private func loadSettings() {
        websiteURL = AppConfig.recyclingWebsiteURL
        requestEmail = AppConfig.requestEmail
        updateDiscoveryStatus()
    }

    // MARK: - Статус данных о переработке
    // Пользователю важна только дата сбора (свежесть данных),
    // не количество страниц/правил — это деталь под капотом

    /// Собирает строку статуса: дата последнего сбора данных
    private func updateDiscoveryStatus() {
        // База правил (списочная архитектура)
        if let rules = storage.loadSiteRules(forBaseURL: AppConfig.recyclingWebsiteURL) {
            discoveryResult = "The app fetched this data from the source website on \(rules.builtAt.formatted(date: .abbreviated, time: .omitted))"
            return
        }

        // База ещё не собрана — показываем состояние старого кэша
        guard let cached = storage.loadTargetURLs(forBaseURL: AppConfig.recyclingWebsiteURL),
              !cached.isEmpty else {
            discoveryResult = nil
            return
        }
        if let date = storage.targetURLsCacheDate() {
            discoveryResult = "The app fetched this data from the source website on \(date.formatted(date: .abbreviated, time: .omitted))"
        } else {
            discoveryResult = nil
        }
    }
    
    // MARK: - Сохранение настроек
    
    private func saveSettings() {
        // Нормализуем URL: пользователь может вставить грязную ссылку
        // из браузера (utm-хвосты, «?», слэши) — храним каноничный вид
        let newURL = URLNormalizer.normalize(websiteURL)
        let previousURL = AppConfig.recyclingWebsiteURL

        // Показываем в поле то, что реально сохранили
        websiteURL = newURL

        UserDefaults.standard.set(newURL, forKey: "settings_website_url")
        UserDefaults.standard.set(requestEmail, forKey: "settings_request_email")
        focusedField = nil
        
        // Если URL изменился — сбрасываем кэш и базу правил старого сайта
        // и запускаем сборку для нового
        if newURL != previousURL && !newURL.isEmpty {
            storage.clearTargetURLsCache()
            storage.clearSiteRules()
            discoveryResult = nil
            startDiscovery(for: newURL)
        } else {
            showSavedNote()
        }
    }

    // MARK: - Живое подтверждение сохранения

    /// Переключает кнопку в состояние «✓ Saved» и возвращает через пару секунд.
    /// Смена мгновенная, без анимации — иначе оба состояния видны одновременно
    private func showSavedNote() {
        savedNote = "Settings saved"
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                savedNote = nil
            }
        }
    }
    
    // MARK: - Запуск конвейера сборки базы правил (П2.4)

    /// «Refresh source pages»: дискавери страниц со списками + AI-извлечение
    /// пунктов + сохранение базы. Кэш целевых URL сохраняется внутри конвейера
    private func startDiscovery(for urlString: String) {
        isDiscovering = true
        discoveryResult = nil

        Task {
            do {
                _ = try await SiteRulesBuilder.shared
                    .buildRules(baseURLString: urlString)

                await MainActor.run {
                    isDiscovering = false
                    updateDiscoveryStatus()
                    showSavedNote()
                }
            } catch {
                await MainActor.run {
                    isDiscovering = false
                    discoveryErrorMessage = friendlyErrorMessage(from: error)
                    showDiscoveryError = true
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
