import SwiftUI

// MARK: - Экран настроек
// Пользователь может указать URL сайта переработки
// и email для отправки запросов.
// При сохранении нового URL автоматически запускается
// обнаружение целевых страниц (СП3.1).

struct SettingsView: View {
    
    @State private var websiteURL: String = ""
    @State private var requestEmail: String = ""
    @State private var showSavedAlert = false
    
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
                Text("Request email")
            } footer: {
                Text("Email address for submitting items not found on the website.")
            }
            
            // MARK: - Статус обнаружения страниц
            
            if isDiscovering || discoveryResult != nil {
                Section {
                    if isDiscovering {
                        // Индикатор прогресса обнаружения
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Discovering pages...")
                                .foregroundStyle(.secondary)
                        }
                    } else if let result = discoveryResult {
                        // Результат обнаружения
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(result)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Page discovery")
                }
            }
            
            // MARK: - Кнопка сохранения
            Section {
                Button {
                    saveSettings()
                } label: {
                    HStack {
                        Spacer()
                        Text("Save")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isDiscovering)
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
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Settings have been saved.")
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
        
        // Показываем кэшированный результат обнаружения, если есть
        if let cached = storage.loadTargetURLs(forBaseURL: websiteURL) {
            discoveryResult = "\(cached.count) pages found"
        }
    }
    
    // MARK: - Сохранение настроек
    
    private func saveSettings() {
        let newURL = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousURL = AppConfig.recyclingWebsiteURL
        
        UserDefaults.standard.set(newURL, forKey: "settings_website_url")
        UserDefaults.standard.set(requestEmail, forKey: "settings_request_email")
        focusedField = nil
        
        // Если URL изменился — запускаем обнаружение целевых страниц
        if newURL != previousURL && !newURL.isEmpty {
            storage.clearTargetURLsCache()
            startDiscovery(for: newURL)
        } else {
            showSavedAlert = true
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
                    discoveryResult = "\(targetURLs.count) pages found"
                    showSavedAlert = true
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
