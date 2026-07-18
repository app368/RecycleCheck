import SwiftUI

// MARK: - Экран настроек
// Пользователь может указать URL сайта переработки
// и email для отправки запросов.
// При сохранении нового URL автоматически запускается
// обнаружение целевых страниц (СП3.1).

struct SettingsView: View {
    
    @State private var websiteURL: String = ""
    @State private var requestEmail: String = ""

    /// Всплывающий баннер (подтверждение — зелёный, ошибка — красный).
    /// Заменяет и смену текста кнопки Save на «Saved», и системный
    /// .alert для ошибок Refresh — модальный алерт на этом экране
    /// после закрытия оставлял Form в состоянии, где ProgressView
    /// индикатора при следующем Refresh не появлялся на экране (баг
    /// подтверждён отдельным тестом, причина не выяснена — обходим)
    @State private var toast: Toast?

    private struct Toast: Equatable {
        let message: String
        let isError: Bool
    }

    /// Состояние обнаружения целевых страниц
    @State private var isDiscovering = false
    @State private var discoveryResult: String?


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
                // контента и сам исчезает, кнопка Save при этом не меняется.
                // Анимация — только на самом баннере, не на всей Form,
                // иначе она может задевать другие изменения состояния
                // (например, индикатор Refresh), если они происходят
                // близко по времени
                if let toast {
                    Label(toast.message, systemImage: toast.isError
                          ? "exclamationmark.triangle.fill"
                          : "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(toast.isError ? .red : .green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.25), value: toast)
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
    }
    
    // MARK: - Кнопка Save в навбаре

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

    // MARK: - Всплывающий баннер

    /// Показывает баннер под заголовком с анимацией появления/исчезновения.
    /// Ошибки висят дольше обычного подтверждения — их нужно успеть прочитать
    private func showToast(_ message: String, isError: Bool = false) {
        toast = Toast(message: message, isError: isError)
        Task {
            try? await Task.sleep(for: .seconds(isError ? 5 : 2.5))
            await MainActor.run {
                toast = nil
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
                    let message = friendly.message.isEmpty
                        ? friendly.title
                        : "\(friendly.title). \(friendly.message)"
                    showToast(message, isError: true)
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
