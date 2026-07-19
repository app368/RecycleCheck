import SwiftUI

// MARK: - Экран деталей записи истории (СП7.2)
// Показывает полную информацию о проверке:
// фото предмета, описание (распознанное ИИ, могло быть отредактировано
// пользователем на экране распознавания), статус, доказательство с сайта,
// дата, отправка email.

struct HistoryDetailView: View {

    /// Запись из истории проверок
    let entry: CheckHistoryEntry

    /// Флаг показа страницы источника внутри приложения
    @State private var showSourcePage = false

    /// Флаг показа сайта переработки, если конкретной ссылки на источник нет
    @State private var showWebsite = false

    /// Флаг перехода к отправке email (СП5)
    @State private var showEmailComposer = false

    /// Якоря верха/низа контента — для плавающей стрелки скролла
    private let topAnchorID = "top"
    private let bottomAnchorID = "bottom"

    /// true, когда скролл дошёл до конца страницы — стрелка меняет
    /// направление на «вверх»
    @State private var isAtBottom = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: - Описание предмета (AI-распознавание) — первым
                        descriptionsSection
                            .id(topAnchorID)

                        // MARK: - Фотография предмета
                        photoSection

                        // MARK: - Статус проверки
                        statusSection

                        // MARK: - Подтверждение вердикта (СП4.1) или старый evidence
                        confirmationOrEvidenceSection

                        // MARK: - Информация о проверке
                        infoSection

                        // Маркер конца контента: как только он попадает
                        // в зону видимости, значит проскроллили до низа —
                        // стрелка разворачивается вверх. Надёжнее ручного
                        // расчёта смещений через onScrollGeometryChange
                        Color.clear
                            .frame(height: 12)
                            .id(bottomAnchorID)
                            .onScrollVisibilityChange(threshold: 0.5) { visible in
                                // Анимация смены направления — на самой
                                // иконке (фиксированная длительность,
                                // симметрично в обе стороны), а не пружиной
                                // withAnimation с «хвостом»
                                isAtBottom = visible
                            }
                    }
                    .padding()
                }
                // Плавающая стрелка — эффект жидкого стекла (родной для
                // iOS 26) с откликом на нажатие, справа над кнопками
                // действий; вниз, пока есть что скроллить, вверх — когда
                // дошли до конца страницы. arrow.down/up — со «стержнем»
                // (хвостиком), не просто уголок chevron
                .overlay(alignment: .bottomTrailing) {
                    ScrollJumpButton(
                        isAtBottom: isAtBottom,
                        tint: statusColor
                    ) {
                        withAnimation {
                            proxy.scrollTo(
                                isAtBottom ? topAnchorID : bottomAnchorID,
                                anchor: isAtBottom ? .top : .bottom
                            )
                        }
                    }
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
                }
            }

            // MARK: - Кнопки действий — у нижней границы экрана (как ResultView)

            actionsSection
        }
        .pinnedLargeNavigationTitle("Check Details")

        // MARK: - Переход к отправке email (СП5)

        .navigationDestination(isPresented: $showEmailComposer) {
            SuggestItemView(item: entry.item, historyEntryID: entry.id)
        }

        // MARK: - Страница источника внутри приложения

        .sheet(isPresented: $showSourcePage) {
            if let url = sourcePageURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }

        // MARK: - Сайт переработки, если конкретной ссылки на источник нет

        .sheet(isPresented: $showWebsite) {
            if let url = websiteURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Секция фотографии

    private var photoSection: some View {
        Group {
            if let fileName = entry.item.photoFileName,
               let image = StorageService.shared.loadPhoto(named: fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 270)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    // Тап открывает фото на весь экран с зумом
                    .zoomablePhoto(image)
            } else {
                // Заглушка, если фото нет
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 200)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Секция статуса
    
    private var statusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.title2)
            Text(statusText)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .foregroundStyle(statusColor)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Секция описания предмета (AI-распознавание, СП2)

    @ViewBuilder
    private var descriptionsSection: some View {
        if let text = entry.item.displaySearchText, !text.isEmpty {
            DetailCard(
                title: "Item description",
                icon: "brain",
                content: text,
                emphasized: true
            )
        }
    }
    
    // MARK: - Подтверждение вердикта (СП4.1)

    /// Единый путь для всех записей: секция подтверждения + свёрнутый evidence.
    /// Если confirmation в записи нет (догрузка не удалась или запись старая) —
    /// показываем «Confirmation unavailable», evidence остаётся доступен ниже.
    /// В истории догрузки нет: показываем то, что было сохранено при проверке.
    @ViewBuilder
    private var confirmationOrEvidenceSection: some View {
        // Для notFound подтверждения не бывает — секцию не показываем
        if let result = entry.result, result.status != .notFound {
            if let confirmation = result.confirmation {
                ConfirmationSectionView(state: .loaded(confirmation), tint: statusColor)
            } else {
                ConfirmationSectionView(state: .unavailable, tint: statusColor)
            }
        }

        // Сырой evidence — заметная кнопка с разворачиванием, где он есть
        if let evidence = entry.result?.evidence, !evidence.isEmpty {
            RawEvidenceDisclosure(evidence: evidence)
        }
    }
    
    // MARK: - Секция информации
    
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Дата проверки
            InfoRow(
                label: "Checked",
                value: entry.checkedAt.formatted(
                    .dateTime.day().month(.wide).year().hour().minute()
                )
            )
            
            // Статус отправки email (СП5)
            InfoRow(
                label: "Email sent",
                value: entry.emailSent ? "Yes" : "No"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Источник (СП7.2)

    /// URL страницы источника (если строка корректна)
    private var sourcePageURL: URL? {
        guard let urlString = entry.result?.sourceURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }

    /// URL сайта переработки (главная) — запасной вариант, если у записи
    /// нет конкретной ссылки на источник
    private var websiteURL: URL? {
        URL(string: AppConfig.recyclingWebsiteURL)
    }

    // MARK: - Кнопки действий — запрос по email + переход на сайт
    // (тот же паттерн, что на ResultView): «Open source page», если есть
    // конкретная ссылка, иначе «Visit website»

    private var actionsSection: some View {
        VStack(spacing: 10) {
            actionButton(title: "Send a question by email", icon: "envelope.fill") {
                showEmailComposer = true
            }

            if sourcePageURL != nil {
                actionButton(title: "Open source page", icon: "safari") {
                    showSourcePage = true
                }
            } else {
                actionButton(title: "Visit website", icon: "safari") {
                    showWebsite = true
                }
                .disabled(websiteURL == nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// Кнопка действия в едином стиле: заливка цветом статуса, белый текст
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

    // MARK: - Вспомогательные свойства статуса
    
    private var statusIcon: String {
        switch entry.result?.status {
        case .recyclable:
            return "checkmark.circle.fill"
        case .notRecyclable:
            return "xmark.circle.fill"
        case .notFound, .none:
            return "questionmark.circle.fill"
        }
    }
    
    private var statusText: String {
        entry.result?.status.displayText ?? "Not checked"
    }
    
    private var statusColor: Color {
        entry.result?.status.color ?? .blue
    }
}

// MARK: - Карточка с деталями

/// Переиспользуемая карточка для отображения блока информации
struct DetailCard: View {
    let title: String
    let icon: String
    let content: String

    /// По центру, заголовок крупнее/ярче, значение — приглушённее.
    /// Для Item description на HistoryDetailView
    var emphasized: Bool = false

    var body: some View {
        VStack(alignment: emphasized ? .center : .leading, spacing: 8) {
            // Заголовок карточки — крупнее и ярче при emphasized;
            // без иконки (не Label, а обычный Text)
            Group {
                if emphasized {
                    Text(title)
                } else {
                    Label(title, systemImage: icon)
                }
            }
            .font(emphasized ? .headline : .caption)
            .foregroundStyle(emphasized ? .primary : .secondary)
            .fontWeight(emphasized ? .bold : .medium)
            .frame(maxWidth: .infinity, alignment: emphasized ? .center : .leading)

            // Содержимое — при emphasized чуть ярче обычного .secondary,
            // но всё ещё вторично по отношению к заголовку
            Text(content)
                .font(.body)
                .foregroundStyle(emphasized ? Color.primary.opacity(0.75) : .primary)
                .multilineTextAlignment(emphasized ? .center : .leading)
                // Долгое нажатие — системное меню: Copy / Translate / Share
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: emphasized ? .center : .leading)
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Строка информации

/// Строка «Метка: Значение»
struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)
            Spacer()
            Text(value)
                .font(.subheadline)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack {
        HistoryDetailView(
            entry: CheckHistoryEntry(
                item: RecycleItem(recognition: ItemRecognition(
                    category: .item, material: "plastic", itemType: "bottle", contentsUse: ["beverage"]
                )),
                result: SearchResult(
                    status: .recyclable,
                    evidence: "Plastic bottles (PET #1) are widely accepted in curbside recycling programs."
                )
            )
        )
    }
}
