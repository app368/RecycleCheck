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
            VStack(spacing: 14) {

                // MARK: - Название предмета (первым)

                Text(item.displayName)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    // Долгое нажатие — системное меню: Copy / Translate / Share
                    .textSelection(.enabled)

                // MARK: - Фото предмета

                itemPhoto

                // MARK: - Строка результата (текст + маленькая иконка, в цвете)

                resultLine

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

        // MARK: - «Done» в правом верхнем углу — возврат на главный экран

        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        // Немного вытянута по ширине
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                        .background(.blue)
                        .clipShape(Capsule())
                }
                // Убираем стандартную подложку кнопки навбара —
                // иначе синяя капсула сидит внутри белого фона
                .buttonStyle(.plain)
            }
        }

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
    
    // MARK: - Строка результата (да / нет / неясно)
    // Компактная строка вместо большой иконки: текст ответа + маленькая
    // иконка в размер строки, вся в цвете вердикта

    private var resultLine: some View {
        Label {
            Text(result.status.displayText)
        } icon: {
            Image(systemName: statusSystemImage)
        }
        .font(.headline)
        .foregroundStyle(statusColor)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    // MARK: - Фото предмета
    // Уменьшено ради экономии места (зум фото — в списке доработок)

    @ViewBuilder
    private var itemPhoto: some View {
        if let fileName = item.photoFileName,
           let image = storage.loadPhoto(named: fileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 130)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)
                )
                // Тап открывает фото на весь экран с зумом
                .zoomablePhoto(image)
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

    // MARK: - Пояснение для исхода «неясно» (две секции, в синем)
    // «What does this mean» — что произошло; «What you can do» — рекомендация

    @ViewBuilder
    private var unclearSection: some View {
        if result.status == .notFound {
            VStack(alignment: .leading, spacing: 10) {
                unclearCard(
                    title: "What does this mean",
                    icon: "questionmark.circle.fill",
                    text: "The app couldn't determine whether this item is recyclable from the website's lists."
                )
                unclearCard(
                    title: "What you can do",
                    icon: "lightbulb.fill",
                    text: "To find out, you can send a request to the website's team or open the website and check it yourself."
                )
            }
        }
    }

    /// Одна секция экрана «неясно»: заголовок с синей иконкой и текст.
    /// Компактная: заголовок в размер subheadline, меньше отступы
    private func unclearCard(title: String, icon: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
                    .foregroundStyle(.primary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(statusColor)
            }
            .font(.subheadline)
            .fontWeight(.semibold)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(statusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                    .background(statusColor.opacity(0.12))
                    .foregroundStyle(statusColor)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Кнопки действий (только для «неясно»; «Done» — в навбаре)
    // Два пути уточнения: запрос по email и открыть сайт. Оба в одном стиле,
    // в цвете вердикта

    @ViewBuilder
    private var actionsSection: some View {
        if result.status == .notFound {
            VStack(spacing: 10) {
                actionButton(title: "Send a request by email", icon: "envelope.fill") {
                    showEmailComposer = true
                }

                actionButton(title: "Open website", icon: "safari") {
                    showWebsite = true
                }
                .disabled(websiteURL == nil)
            }
            .padding(.top, 4)
        }
    }

    /// Кнопка действия в едином стиле: заливка цветом вердикта, белый текст
    private func actionButton(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(statusColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    // MARK: - Вспомогательные свойства для стилизации по статусу

    /// Цвет, соответствующий статусу вердикта:
    /// да — зелёный, нет — красный, неясно — синий
    private var statusColor: Color {
        switch result.status {
        case .recyclable:
            return .green
        case .notRecyclable:
            return .red
        case .notFound:
            return .blue
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
