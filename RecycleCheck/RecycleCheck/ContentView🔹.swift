import SwiftUI

// MARK: - Главный экран приложения
// Точка входа пользователя: кнопка проверки предмета,
// навигация к истории, профилю и настройкам.

struct ContentView: View {
    
    /// Флаг перехода к экрану захвата предмета (СП1)
    @State private var showCapture = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                
                Spacer()
                
                // MARK: - Логотип и описание
                
                VStack(spacing: 12) {
                    Image(systemName: "arrow.3.trianglepath")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    
                    Text("RecycleCheck")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Check if an item is recyclable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // MARK: - Кнопка проверки предмета → СП1
                
                Button {
                    showCapture = true
                } label: {
                    Label("Check an item", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
            }
            .navigationDestination(isPresented: $showCapture) {
                CaptureView()
            }
            .toolbar {
                // MARK: - Навигация в историю (СП7) — слева
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                    }
                }
                
                // MARK: - Навигация в профиль (СП6) и настройки — справа
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        Image(systemName: "person.circle")
                            .font(.title3)
                    }
                    
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title3)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
