import SwiftUI

// MARK: - Главный экран приложения
// Точка входа пользователя: кнопка проверки предмета,
// навигация к истории, профилю и настройкам.

struct ContentView: View {
    
    /// Флаг перехода к экрану захвата предмета (СП1)
    @State private var showCapture = false

    /// true, если база правил сайта ещё не собрана (первый запуск —
    /// подсказка сходить в Settings и нажать Update)
    @State private var needsFirstRefresh = false

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

                // MARK: - Подсказка первого запуска — база правил не собрана

                if needsFirstRefresh {
                    firstLaunchHint
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
            .onAppear {
                checkFirstLaunchState()
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

    // MARK: - Подсказка первого запуска

    private var firstLaunchHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Setup needed", systemImage: "exclamationmark.circle.fill")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.orange)

            Text("To start checking items, open Settings and tap \"Update recycling data\" at the bottom of the page. This loads the recycling data from the source website.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 32)
    }

    // MARK: - Проверка состояния базы правил

    /// База правил считается собранной, если для текущего сайта есть
    /// сохранённые данные (StorageService), независимо от их даты
    private func checkFirstLaunchState() {
        let rules = StorageService.shared.loadSiteRules(forBaseURL: AppConfig.recyclingWebsiteURL)
        needsFirstRefresh = (rules == nil)
    }
}

#Preview {
    ContentView()
}
