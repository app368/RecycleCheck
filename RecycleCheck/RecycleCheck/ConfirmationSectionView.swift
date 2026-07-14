import SwiftUI
import Translation

// MARK: - Секция подтверждения вердикта
// Переиспользуемый компонент для ResultView и HistoryDetailView.
// Показывает подтверждение вердикта: дословный пункт списка сайта
// и секцию, где он найден. Красится в цвет вердикта (tint).
// Поддерживает три состояния: загрузка, готово, недоступно.

/// Состояние секции подтверждения
enum ConfirmationState: Equatable {
    /// Идёт сбор упоминаний и анализ (Collector + Service)
    case loading

    /// Подтверждение получено
    case loaded(Confirmation)

    /// Получить подтверждение не удалось
    case unavailable
}

struct ConfirmationSectionView: View {

    /// Текущее состояние секции
    let state: ConfirmationState

    /// Цвет вердикта страницы: зелёный (да) / красный (нет);
    /// в него красятся иконки и цитата
    var tint: Color = .green

    var body: some View {
        // Заголовка «Confirmation» нет: сама цитата и есть подтверждение
        Group {
            switch state {
            case .loading:
                loadingView
            case .loaded(let confirmation):
                subsections(for: confirmation)
            case .unavailable:
                unavailableView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Индикатор загрузки

    private var loadingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Looking for confirmation…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding()
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Сообщение о недоступности

    private var unavailableView: some View {
        Text("Confirmation unavailable")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
            .background(.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Подтверждение: только цитата с сайта
    // Концепция «простого ответа»: приложение отвечает на один вопрос —
    // пригоден предмет или нет. Условия и подготовка сознательно не показываем
    // (это увело бы к разбору текстов и усложнению приложения).
    //
    // Структура карточки (макет Justin 13.07.2026):
    // иконка цитаты в левом верхнем углу; по центру «Citation from list:»
    // и название секции курсивом; сама цитата — крупно, bold, в цвете
    // вердикта; кнопка перевода — в правом нижнем углу

    private func subsections(for confirmation: Confirmation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Строка-заголовок: иконка цитаты слева, титул по центру,
            // кнопка перевода в правом верхнем углу
            ZStack {
                HStack {
                    Image(systemName: "text.quote")
                        .foregroundStyle(tint)
                    Spacer()
                    if #available(iOS 17.4, *) {
                        TranslateButton(text: confirmation.citation, tint: tint)
                    }
                }
                Text("Citation from list")
                    .font(.subheadline)
            }

            // Название секции сайта — по центру, курсив + bold, в цвете вердикта
            if let section = confirmation.sourceSection {
                Text("\(section):")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .italic()
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // Сама цитата — bold, чёрная, по центру, в кавычках
            Text("\u{201C}\(confirmation.citation)\u{201D}")
                .font(.body)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                // Долгое нажатие — системное меню: Copy / Translate / Share
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .background(.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Кнопка «Show raw evidence» (сырой текст с сайта)
// Оформлена как заметная кнопка-карточка с разворачиванием.
// Используется в ResultView и HistoryDetailView.

struct RawEvidenceDisclosure: View {

    /// Сырой текст-доказательство с сайта
    let evidence: String

    /// Развёрнуто ли содержимое
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(evidence)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    // Долгое нажатие — системное меню: Copy / Share
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Кнопка перевода — системное окно перевода абзаца
                if #available(iOS 17.4, *) {
                    HStack {
                        Spacer()
                        TranslateButton(text: evidence)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Show raw evidence", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)
        }
        .tint(.blue)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Кнопка перевода текста
// Открывает системное окно перевода (Translation framework, iOS 17.4+).
// Тот же UI, что открывает опция Translate из меню выделения текста.

@available(iOS 17.4, *)
struct TranslateButton: View {

    /// Текст, который будет переведён
    let text: String

    /// Цвет иконки (в блоке подтверждения — цвет вердикта)
    var tint: Color = .blue

    /// Флаг показа системного окна перевода
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "translate")
                .font(.subheadline)
                .foregroundStyle(tint)
        }
        .translationPresentation(isPresented: $isPresented, text: text)
    }
}

// MARK: - Превью

#Preview("Raw evidence button") {
    RawEvidenceDisclosure(
        evidence: "Plastic bottles (PET #1) are widely accepted in curbside recycling programs. Rinse and remove the cap before placing in the recycling bin."
    )
    .padding()
}

#Preview("Loaded — recyclable") {
    ScrollView {
        ConfirmationSectionView(
            state: .loaded(Confirmation(
                citation: "Cartons (milk, juice, soup; empty and dry) go in your blue recycling bin.",
                sourceSection: "Allowed paper items"
            ))
        )
        .padding()
    }
}

#Preview("Loaded — not recyclable") {
    ScrollView {
        ConfirmationSectionView(
            state: .loaded(Confirmation(
                citation: "NO drinking glasses, dishware, or drinkware of any kind.",
                sourceSection: "What’s NOT allowed"
            ))
        )
        .padding()
    }
}

#Preview("Loading") {
    ConfirmationSectionView(state: .loading)
        .padding()
}

#Preview("Unavailable") {
    ConfirmationSectionView(state: .unavailable)
        .padding()
}
