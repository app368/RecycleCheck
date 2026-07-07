import SwiftUI

// MARK: - Экран профиля пользователя (СП6)
// Опциональный ввод и редактирование реквизитов: имя, email, телефон.
// Данные хранятся локально на устройстве через StorageService.
// Email используется для автозаполнения при отправке запроса (СП5).

struct ProfileView: View {
    
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var showSavedAlert = false
    
    /// Фокус для управления клавиатурой
    @FocusState private var focusedField: Field?
    
    private enum Field {
        case name, email, phone
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private let storage = StorageService.shared
    
    var body: some View {
        Form {
            // MARK: - Секция с полями ввода
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .name)
                
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .email)
                
                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: .phone)
            } header: {
                Text("Your details")
            } footer: {
                Text("Optional. Your email will be used as a return address when submitting items for review.")
            }
            
            // MARK: - Кнопка сохранения
            Section {
                Button {
                    saveProfile()
                } label: {
                    HStack {
                        Spacer()
                        Text("Save")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
            
            // MARK: - Кнопка очистки данных
            Section {
                Button(role: .destructive) {
                    clearProfile()
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
        .toolbar {
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
        .alert("Saved", isPresented: $showSavedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your profile has been saved.")
        }
    }
    
    // MARK: - Загрузка профиля из локального хранилища
    
    private func loadProfile() {
        let profile = storage.loadProfile()
        name = profile.name ?? ""
        email = profile.email ?? ""
        phone = profile.phone ?? ""
    }
    
    // MARK: - Сохранение профиля в локальное хранилище
    
    private func saveProfile() {
        let profile = UserProfile(
            name: name.isEmpty ? nil : name,
            email: email.isEmpty ? nil : email,
            phone: phone.isEmpty ? nil : phone
        )
        storage.saveProfile(profile)
        showSavedAlert = true
    }
    
    // MARK: - Очистка всех данных профиля
    
    private func clearProfile() {
        name = ""
        email = ""
        phone = ""
        storage.saveProfile(.empty)
    }
}

#Preview {
    NavigationStack {
        ProfileView()
    }
}
