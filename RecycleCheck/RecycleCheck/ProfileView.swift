import SwiftUI
import UniformTypeIdentifiers

// MARK: - Экран профиля пользователя (СП6)
// Опциональный ввод и редактирование реквизитов: имя, email, телефон.
// Данные хранятся локально на устройстве через StorageService.
// Email используется для автозаполнения при отправке запроса (СП5).

struct ProfileView: View {
    
    @State private var name: String = ""
    @State private var email: String = ""

    /// Алерт подтверждения очистки данных профиля
    @State private var showClearAlert = false

    /// Подсказка у заголовка Email — про автоподстановку отправителя
    @State private var showEmailHint = false

    // MARK: - Состояние резервной копии (экспорт / импорт)

    /// Идёт сборка архива / восстановление из архива
    @State private var isExporting = false
    @State private var isImporting = false

    /// Готовый файл копии и показ меню «Поделиться»
    @State private var exportedURL: URL?
    @State private var showShareSheet = false

    /// Выбор файла копии и подтверждение замены данных
    @State private var showImporter = false
    @State private var pendingImportURL: URL?
    @State private var showImportConfirm = false

    /// Сообщение о результате экспорта / импорта
    @State private var showBackupAlert = false
    @State private var backupAlertTitle = ""
    @State private var backupAlertMessage = ""

    /// Тип файла копии — Apple Archive (.aar)
    private static let backupFileType = UTType(filenameExtension: "aar") ?? .data

    /// Фокус для управления клавиатурой
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, email
    }

    @Environment(\.dismiss) private var dismiss

    private let storage = StorageService.shared

    var body: some View {
        Form {
            // MARK: - Две отдельные секции — по одному полю в каждой.
            // Название поля — заголовок секции (серый фон), само поле —
            // единственная строка секции (белый фон).
            // Небольшой отступ от заголовка страницы — через пустой
            // Spacer над названием поля в header (строка Form не
            // сжимается меньше системного минимума, а header — сжимается)
            Section {
                HStack {
                    TextField("", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .name)

                    if !name.isEmpty {
                        Button {
                            name = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 6)
                    Text("User Name")
                        .fontWeight(.bold)
                }
            }

            Section {
                HStack {
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)

                    if !email.isEmpty {
                        Button {
                            email = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Email")
                    .fontWeight(.bold)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("These two fields are optional. They can be used to send messages to the source website and receive responses.")
                        .font(.subheadline)

                    Button {
                        showEmailHint = true
                    } label: {
                        Label("How the sender address works", systemImage: "info.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showEmailHint) {
                        Text("If this address is already set up as an account in the Mail app, it will be used automatically as the sender when you send a question. Otherwise, you'll need to enter the sender address manually.")
                            .font(.subheadline)
                            .multilineTextAlignment(.leading)
                            .padding()
                            .frame(width: 260)
                            // Без fixedSize popover не досчитывает высоту
                            // под перенесённый текст и обрезает его
                            .fixedSize(horizontal: false, vertical: true)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }

            // MARK: - Резервная копия: экспорт и импорт всех данных
            Section {
                Button {
                    exportData()
                } label: {
                    HStack {
                        Label("Export data", systemImage: "square.and.arrow.up")
                        Spacer()
                        if isExporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting || isImporting)

                Button {
                    showImporter = true
                } label: {
                    HStack {
                        Label("Import data", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isExporting || isImporting)
            } header: {
                Text("Data")
            } footer: {
                Text("Back up checks, photos and settings to a file, or restore them from a backup.")
            }

            // MARK: - Кнопка очистки данных — отделена от пояснительного
            // текста пустой секцией-разделителем
            Section {
                Color.clear
                    .frame(height: 20)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            .listSectionSpacing(0)

            Section {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Clear all data")
                        Spacer()
                    }
                }
            }
        }
        .pinnedLargeNavigationTitle("Profile")
        // Скрываем системную стрелку «назад» — она дублирует Cancel
        // (оба варианта закрывают экран без сохранения)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Cancel — слева, прозрачный фон, зелёный текст: выход без сохранения
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
            }

            // Save — справа, зелёная капсула с белым текстом.
            // borderedProminent + tint — как кнопка Save на экране Settings,
            // без лишней системной подложки, которая возникает у .plain
            // при собственном background+clipShape
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveProfile()
                    dismiss()
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.green)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            loadProfile()
        }
        // Алерт: очистка данных профиля (тот же шаблон, что в HistoryView)
        .alert("Clear all data?",
               isPresented: $showClearAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear all data", role: .destructive) {
                clearProfile()
            }
        } message: {
            Text("The user name and email will be removed from this app.")
        }
        // Меню «Поделиться» для готового файла копии
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        // Выбор файла копии для импорта
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [Self.backupFileType]) { result in
            handlePickedFile(result)
        }
        // Подтверждение: импорт заменяет все данные
        .alert("Replace all data?", isPresented: $showImportConfirm) {
            Button("Cancel", role: .cancel) {
                discardPendingImport()
            }
            Button("Replace", role: .destructive) {
                importData()
            }
        } message: {
            Text("Current checks and photos will be replaced by the backup.")
        }
        // Результат экспорта / импорта
        .alert(backupAlertTitle, isPresented: $showBackupAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupAlertMessage)
        }
    }
    
    // MARK: - Загрузка профиля из локального хранилища
    
    private func loadProfile() {
        let profile = storage.loadProfile()
        name = profile.name ?? ""
        email = profile.email ?? ""
    }

    // MARK: - Сохранение профиля в локальное хранилище

    private func saveProfile() {
        let profile = UserProfile(
            name: name.isEmpty ? nil : name,
            email: email.isEmpty ? nil : email
        )
        storage.saveProfile(profile)
    }

    // MARK: - Очистка всех данных профиля

    private func clearProfile() {
        name = ""
        email = ""
        storage.saveProfile(.empty)
    }

    // MARK: - Экспорт: архив всех данных → меню «Поделиться»

    private func exportData() {
        isExporting = true
        Task {
            do {
                exportedURL = try await BackupService.shared.makeBackup()
                showShareSheet = true
            } catch {
                showBackupResult(title: "Export failed", message: error.localizedDescription)
            }
            isExporting = false
        }
    }

    // MARK: - Импорт: файл выбран → копия к себе → подтверждение

    private func handlePickedFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }

        // Доступ к файлу вне песочницы приложения — только на время копирования
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let copy = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: copy)
        do {
            try FileManager.default.copyItem(at: url, to: copy)
            pendingImportURL = copy
            showImportConfirm = true
        } catch {
            showBackupResult(title: "Import failed", message: error.localizedDescription)
        }
    }

    /// Подтверждено — заменяем данные содержимым копии
    private func importData() {
        guard let url = pendingImportURL else { return }
        isImporting = true
        Task {
            do {
                try await BackupService.shared.restoreBackup(from: url)
                // Имя и email на экране — из восстановленного профиля
                loadProfile()
                showBackupResult(title: "Import complete",
                                 message: "Your checks, photos and settings have been restored.")
            } catch {
                showBackupResult(title: "Import failed", message: error.localizedDescription)
            }
            discardPendingImport()
            isImporting = false
        }
    }

    /// Удаляет временную копию выбранного файла
    private func discardPendingImport() {
        if let url = pendingImportURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingImportURL = nil
    }

    private func showBackupResult(title: String, message: String) {
        backupAlertTitle = title
        backupAlertMessage = message
        showBackupAlert = true
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
