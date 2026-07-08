import SwiftUI

// MARK: - Экран результатов проверки (СП4, списочная архитектура П4)
// Отображает готовый вердикт по базе списков (VerdictService, П3):
// — статус: да (recyclable) / нет (notRecyclable) / неясно (notFound)
// — подтверждающий пункт с сайта (для да/нет)
// — фото предмета
// Для «неясно» — пояснение и два действия: запрос по email или открыть сайт.

struct ResultView: View {

    /// Проверяемый предмет (из СП1 + СП2)
    let item: RecycleItem

    /// Готовый результат вердикта (из П3) — статус и подтверждающий пункт
    let result: SearchResult

    /// ID записи истории — сохранён для совместимости с местом вызова;
    /// в списочной архитектуре вердикт приходит готовым, дозапись не нужна
    var historyEntryID: UUID? = nil

    /// Флаг показа страницы источника (подтверждающий пункт) внутри приложения
    @State private var showSourcePage = false

    /// Флаг показа сайта переработки при исходе «неясно»
    @State private var showWebsite = false

    /// Флаг перехода к отправке email (СП5)
    @State private var showEmailComposer = false

    @Environment(\.dismiss) private var dismiss

    private let storage = StorageService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                
                // MARK: - Иконка статуса
                
                statusIcon
                
                // MARK: - Название предмета
                
                Text(item.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    // Долгое нажатие — системное меню: Copy / Translate / Share
                    .textSelection(.enabled)
                
                // MARK: - Статус пригодности

                statusBadge
                
                // MARK: - Фото предмета
                
                itemPhoto
                
                // MARK: - Подтверждение вердикта (для да/нет)

                confirmationSection

                // MARK: - Пояснение для исхода «неясно»

                unclearSection

                // MARK: - Ссылка на источник (страница подтверждающего пункта)

                sourceLink

                // MARK: - Кнопки действий

                actionsSection
            }
            .padding()
        }
        .navigationTitle("Result")
        .navigationBarTitleDisplayMode(.inline)

        // MARK: - Переход к отправке email (СП5)

        .navigationDestination(isPresented: $showEmailComposer) {
            SuggestItemView(item: item)
        }

        // MARK: - Страница подтверждающего пункта внутри приложения

        .sheet(isPresented: $showSourcePage) {
            if let url = sourcePageURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }

        // MARK: - Сайт переработки при исходе «неясно»

        .sheet(isPresented: $showWebsite) {
            if let url = websiteURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
    
    // MARK: - Иконка статуса (большая, по центру)

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusColor.opacity(0.15))
                .frame(width: 100, height: 100)

            Image(systemName: statusSystemImage)
                .font(.system(size: 44))
                .foregroundStyle(statusColor)
        }
        .padding(.top, 8)
    }

    // MARK: - Бейдж со статусом (да / нет / неясно)

    private var statusBadge: some View {
        Text(result.status.displayText)
            .font(.headline)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(statusColor.opacity(0.1))
            .clipShape(Capsule())
    }
    
    // MARK: - Фото предмета
    
    @ViewBuilder
    private var itemPhoto: some View {
        if let fileName = item.photoFileName,
           let image = storage.loadPhoto(named: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
    
    // MARK: - Секция подтверждения вердикта (для да/нет)
    // Подтверждение = дословный пункт списка + секция; приходит готовым
    // в результате вердикта (П3). Для «неясно» подтверждать нечего

    @ViewBuilder
    private var confirmationSection: some View {
        if let confirmation = result.confirmation {
            ConfirmationSectionView(state: .loaded(confirmation))
        }
    }

    // MARK: - Пояснение для исхода «неясно»
    // Приложение не смогло определить пригодность по спискам сайта.
    // Предлагаем два пути: запрос по email или самостоятельно зайти на сайт

    @ViewBuilder
    private var unclearSection: some View {
        if result.status == .notFound {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    Text("What you can do")
                } icon: {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.title3)
                .fontWeight(.semibold)

                Text("The app couldn't determine whether this item is recyclable from the website's lists. To find out, you can send a request to the website's team or open the website and check it yourself.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Кнопка «Source» — ссылка спрятана под неё

    /// URL страницы подтверждающего пункта (если строка корректна)
    private var sourcePageURL: URL? {
        guard let urlString = result.sourceURL else { return nil }
        return URL(string: urlString)
    }

    /// URL сайта переработки — для кнопки «Open website» при исходе «неясно»
    private var websiteURL: URL? {
        URL(string: AppConfig.recyclingWebsiteURL)
    }

    @ViewBuilder
    private var sourceLink: some View {
        if sourcePageURL != nil {
            Button {
                showSourcePage = true
            } label: {
                Label("Source", systemImage: "safari")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Кнопки действий

    private var actionsSection: some View {
        VStack(spacing: 12) {

            // Исход «неясно» — два пути уточнения: запрос по email и открыть сайт
            if result.status == .notFound {
                Button {
                    showEmailComposer = true
                } label: {
                    Label("Suggest adding this item", systemImage: "envelope.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    showWebsite = true
                } label: {
                    Label("Open website", systemImage: "safari")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(websiteURL == nil)
            }

            // Кнопка возврата на главный экран
            Button {
                // Возвращаемся к корневому экрану
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.gray.opacity(0.15))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Вспомогательные свойства для стилизации по статусу

    /// Цвет, соответствующий статусу вердикта
    private var statusColor: Color {
        switch result.status {
        case .recyclable:
            return .green
        case .notRecyclable:
            return .red
        case .notFound:
            return .orange
        }
    }

    /// SF Symbol, соответствующий статусу вердикта
    private var statusSystemImage: String {
        switch result.status {
        case .recyclable:
            return "checkmark.circle.fill"
        case .notRecyclable:
            return "xmark.circle.fill"
        case .notFound:
            return "questionmark.circle.fill"
        }
    }
}

#Preview("Recyclable") {
    NavigationStack {
        ResultView(
            item: RecycleItem(userDescription: "plastic water bottle"),
            result: SearchResult(
                status: .recyclable,
                sourceURL: "https://example-recycling-site.com",
                confirmation: Confirmation(
                    citation: "Plastic bottles and jars with a neck",
                    exceptions: "must be 2 inches by 2 inches or larger",
                    preparation: "Rinse. Caps are OK if screwed on.",
                    sourceSection: "Allowed plastic items"
                )
            )
        )
    }
}

#Preview("Not recyclable") {
    NavigationStack {
        ResultView(
            item: RecycleItem(userDescription: "glass mug"),
            result: SearchResult(
                status: .notRecyclable,
                sourceURL: "https://example-recycling-site.com",
                confirmation: Confirmation(
                    citation: "NO drinking glasses, dishware, or drinkware of any kind.",
                    exceptions: "Not applicable",
                    preparation: "Not applicable",
                    sourceSection: "What’s NOT allowed"
                )
            )
        )
    }
}

#Preview("Unclear") {
    NavigationStack {
        ResultView(
            item: RecycleItem(userDescription: "old sneakers"),
            result: SearchResult(status: .notFound)
        )
    }
}
