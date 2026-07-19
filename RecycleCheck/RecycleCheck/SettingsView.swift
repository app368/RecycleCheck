import SwiftUI

// MARK: - Экран настроек
// Пользователь может указать URL сайта переработки
// и email для отправки запросов.
// При сохранении нового URL автоматически запускается
// обнаружение целевых страниц (СП3.1).

struct SettingsView: View {
    
    @State private var websiteURL: String = ""
    @State private var requestEmail: String = ""

    /// Всплывающий зелёный баннер-подтверждение (вместо смены текста
    /// кнопки Save на «Saved»)
    @State private var toastMessage: String?

    /// Состояние обнаружения целевых страниц. Индикатор загрузки —
    /// отдельный оверлей поверх всего экрана (см. body), не часть Form —
    /// раньше он жил внутри Section и зависел от соседних состояний
    /// (текст поля, баннер, алерт), из-за чего иногда не показывался
    @State private var isDiscovering = false
    @State private var discoveryResult: String?
    @State private var showDiscoveryError = false
    @State private var discoveryErrorTitle: String = ""
    @State private var discoveryErrorDetail: String = ""


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
                        .onSubmit { focusedField = nil }

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
                Text("The website where the app searches for recyclable items. You can replace it with your state or local recycling program website for local data.")
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
                        // Без textContentType(.emailAddress) — панель
                        // QuickType-подсказок для email мешала курсору
                        // двигаться внутри текста (известный баг iOS)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .lineLimit(2...4)
                        .onSubmit { focusedField = nil }

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
                    if let result = discoveryResult, !isDiscovering {
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
                        Text("No data yet. Tap Refresh below to load it.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Принудительное обновление кэша без смены URL.
                    // Скрываем клавиатуру — иначе секция с индикатором
                    // может оказаться под ней, и пользователь решит, что
                    // приложение зависло
                    Button {
                        focusedField = nil
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
        // Панель Done занимает реальное место над клавиатурой,
        // поэтому не перекрывает текстовое поле.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focusedField != nil {
                keyboardDismissBar
                    // Свободная полоса между полем и панелью,
                    // чтобы при вводе текста не было тесно.
                    .padding(.top, 14)
            }
        }
        // Свой закреплённый заголовок вместо системного large title,
        // который сворачивается при скролле
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)

                // Баннер-подтверждение сохранения — появляется поверх
                // контента и сам исчезает, кнопка Save при этом не меняется
                if let toastMessage {
                    Label(toastMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: toastMessage)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Save — в навбаре справа, закреплена и не уезжает при скролле.
            // Всегда одинаковый вид — подтверждение показывает баннер выше
            ToolbarItem(placement: .topBarTrailing) {
                saveToolbarButton
            }
        }
        .onAppear {
            loadSettings()
        }
        // Индикатор загрузки — отдельный слой поверх ВСЕГО экрана,
        // не часть Form/Section. Единственная зависимость — isDiscovering,
        // никакие поля, баннеры и алерты на него не влияют
        .overlay {
            if isDiscovering {
                ZStack {
                    Color.green.opacity(0.12)
                        .ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                        Text("Reading recycling info...")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.green.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8)
                }
            }
        }
        // Без отдельного технического заголовка «Rules update failed» —
        // первое предложение самого сообщения становится заголовком
        // алерта, второе (если есть) — телом
        .alert(discoveryErrorTitle, isPresented: $showDiscoveryError) {
            Button("OK", role: .cancel) { }
        } message: {
            if !discoveryErrorDetail.isEmpty {
                Text(discoveryErrorDetail)
            }
        }
    }
    
    // MARK: - Кнопка Save в навбаре

    /// Полупрозрачная панель над клавиатурой. В отличие от
    /// ToolbarItem(placement: .keyboard), safeAreaInset учитывается
    /// в компоновке Form и не накладывается на поля.
    private var keyboardDismissBar: some View {
        HStack {
            Spacer()
            Button("Done") {
                focusedField = nil
            }
            .fontWeight(.semibold)
            .foregroundStyle(.green)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .background(Color(.systemBackground).opacity(0.75))
    }

    /// Save в правом верхнем углу — вид не меняется при нажатии,
    /// подтверждение показывает отдельный баннер под заголовком
    private var saveToolbarButton: some View {
        Button {
            saveSettings()
        } label: {
            Text("Save")
                .fontWeight(.semibold)
                // Шире по горизонтали — прямоугольник, а не овал
                .padding(.horizontal, 20)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .tint(.green)
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

    /// Save только сохраняет поля — обновление базы правил больше не
    /// запускается автоматически (пользователь мог не заметить, что идёт
    /// сетевой запрос на пару минут, пока Save/Refresh неактивны без
    /// видимого индикатора). Пользователь жмёт Refresh сам, осознанно
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

        // Если URL изменился — сбрасываем кэш и базу правил старого сайта.
        // Новую сборку запускает только сам пользователь кнопкой Refresh
        let urlChanged = newURL != previousURL && !newURL.isEmpty
        if urlChanged {
            storage.clearTargetURLsCache()
            storage.clearSiteRules()
            discoveryResult = nil
        }

        showToast(urlChanged ? "Website address updated and saved" : "Settings saved")
    }

    // MARK: - Всплывающий баннер-подтверждение

    /// Показывает баннер под заголовком на пару секунд, с анимацией
    /// появления/исчезновения
    private func showToast(_ message: String) {
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                toastMessage = nil
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
                    showToast("Recycling data refreshed")
                }
            } catch {
                await MainActor.run {
                    isDiscovering = false
                    let friendly = friendlyError(from: error)
                    discoveryErrorTitle = friendly.title
                    discoveryErrorDetail = friendly.message
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
