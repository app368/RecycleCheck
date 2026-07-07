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
            } header: {
                Text("Recycling website URL")
            } footer: {
                Text("The website where the app searches for recyclable items.")
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
            } header: {
                Text("Email for messages to the source website")
            } footer: {
                Text("Here you can specify the email address for submitting items not found on the website.")
            }
            
            // MARK: - Секция обнаружения страниц: статус кэша + Refresh

            if !websiteURL.isEmpty {
                Section {
                    if isDiscovering {
                        // Индикатор прогресса обнаружения
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Discovering pages...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let result = discoveryResult {
                        // Состояние кэша: количество страниц и дата сборки
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(result)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No pages discovered yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Принудительное обновление кэша без смены URL
                    Button {
                        startDiscovery(for: AppConfig.recyclingWebsiteURL)
                    } label: {
                        Label("Refresh source pages", systemImage: "arrow.clockwise")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.blue.opacity(0.1))
                            .foregroundStyle(.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .disabled(isDiscovering)
                } header: {
                    Text("Page discovery")
                } footer: {
                    Text("Re-discovers the website pages used for item search — refresh if the website content has changed.")
                }
            }

            // MARK: - Кнопка сохранения
            // Полноценная зелёная кнопка в стиле основных кнопок приложения
            Section {
                Button {
                    saveSettings()
                } label: {
                    Text("Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isDiscovering ? .gray : .green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .disabled(isDiscovering)
            } footer: {
                // Живое подтверждение: появляется на каждое нажатие
                // и само исчезает через пару секунд
                if let savedNote {
                    Label(savedNote, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
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
        .alert("Page discovery failed", isPresented: $showDiscoveryError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(discoveryErrorMessage)
        }
    }
    
    // MARK: - Загрузка текущих настроек
    
    private func loadSettings() {
        websiteURL = AppConfig.recyclingWebsiteURL
        requestEmail = AppConfig.requestEmail
        updateDiscoveryStatus()
    }

    // MARK: - Статус кэша целевых страниц

    /// Собирает строку состояния кэша: количество страниц + дата сборки.
    /// «6 pages found · updated Jul 7, 2026»
    private func updateDiscoveryStatus() {
        guard let cached = storage.loadTargetURLs(forBaseURL: AppConfig.recyclingWebsiteURL),
              !cached.isEmpty else {
            discoveryResult = nil
            return
        }
        var status = "\(cached.count) pages found"
        if let date = storage.targetURLsCacheDate() {
            status += " · updated \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        discoveryResult = status
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
        
        // Если URL изменился — запускаем обнаружение целевых страниц
        if newURL != previousURL && !newURL.isEmpty {
            storage.clearTargetURLsCache()
            discoveryResult = nil
            startDiscovery(for: newURL)
        } else {
            showSavedNote()
        }
    }

    // MARK: - Живое подтверждение сохранения

    /// Показывает «Settings saved» под кнопкой и прячет через пару секунд.
    /// Срабатывает на каждое нажатие — в отличие от статичной строки или алерта
    private func showSavedNote() {
        withAnimation {
            savedNote = "Settings saved"
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await MainActor.run {
                withAnimation {
                    savedNote = nil
                }
            }
        }
    }
    
    // MARK: - Запуск обнаружения целевых страниц (СП3.1)
    
    private func startDiscovery(for urlString: String) {
        isDiscovering = true
        discoveryResult = nil
        
        Task {
            do {
                let targetURLs = try await LinkDiscoveryService.shared
                    .discoverTargetPages(baseURLString: urlString)
                
                // Сохраняем в кэш
                storage.saveTargetURLs(targetURLs, forBaseURL: urlString)
                
                await MainActor.run {
                    isDiscovering = false
                    updateDiscoveryStatus()
                    showSavedNote()
                }
            } catch {
                await MainActor.run {
                    isDiscovering = false
                    discoveryErrorMessage = error.localizedDescription
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
