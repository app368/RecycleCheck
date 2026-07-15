import SwiftUI

// MARK: - Экран профиля пользователя (СП6)
// Опциональный ввод и редактирование реквизитов: имя, email, телефон.
// Данные хранятся локально на устройстве через StorageService.
// Email используется для автозаполнения при отправке запроса (СП5).

struct ProfileView: View {
    
    @State private var name: String = ""
    @State private var email: String = ""

    /// Алерт подтверждения очистки данных профиля
    @State private var showClearAlert = false

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
                Text("These two fields are optional. They can be used to send messages to the source website and receive responses.")
                    .font(.subheadline)
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
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
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
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
