import SwiftUI
import Translation

// MARK: - Секция подтверждения вердикта (СП4.1, шаг 3)
// Переиспользуемый компонент для ResultView и HistoryDetailView.
// Отображает структурированное подтверждение из трёх подразделов:
// Citation from website / Exceptions / How to prepare.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // MARK: - Заголовок секции

            Label {
                Text("Confirmation")
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            }
            .font(.title3)
            .fontWeight(.semibold)

            // MARK: - Содержимое по состоянию

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
    // (это увело бы к разбору текстов и усложнению приложения)

    @ViewBuilder
    private func subsections(for confirmation: Confirmation) -> some View {
        // Дословный пункт с сайта; под ним секция сайта, если известна
        subsection(
            title: "Citation from website",
            icon: "text.quote",
            color: .blue,
            text: confirmation.citation,
            caption: confirmation.sourceSection.map { "From: \($0)" }
        )
    }

    /// Один подраздел: заголовок с цветной иконкой, кнопка перевода
    /// и текст на подложке. caption — необязательная подпись под текстом
    /// (например секция сайта, откуда взята цитата)
    private func subsection(
        title: String,
        icon: String,
        color: Color,
        text: String,
        caption: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text(title)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(color)
                }
                .font(.subheadline)
                .fontWeight(.semibold)

                Spacer()

                // Кнопка перевода — системное окно перевода абзаца
                if #available(iOS 17.4, *) {
                    TranslateButton(text: text)
                }
            }

            Text(text)
                .font(.body)
                // Долгое нажатие — системное меню: Copy / Translate / Share
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Подпись-источник (секция сайта)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    /// Флаг показа системного окна перевода
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "translate")
                .font(.subheadline)
                .foregroundStyle(.blue)
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
                exceptions: "No exceptions mentioned",
                preparation: "Empty and dry the carton before placing it in the bin."
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
                exceptions: "Not applicable",
                preparation: "Not applicable"
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
