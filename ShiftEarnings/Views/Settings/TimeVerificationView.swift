import SwiftUI

struct TimeVerificationView: View {
    let container: AppContainer
    @State private var result: TimeVerificationResult?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Проверка выполняется только после нажатия кнопки. Она не меняет системное время и не влияет на расчёт заработка, который продолжает использовать время iPhone.")
                    .foregroundStyle(.secondary)
            }

            if let result {
                Section("Результат") {
                    LabeledContent("Время устройства", value: AppFormatters.dateTime(result.deviceTime, timeZone: displayTimeZone))
                    LabeledContent("Проверенное время", value: AppFormatters.dateTime(result.verifiedTime, timeZone: displayTimeZone))
                    LabeledContent("Расхождение", value: AppFormatters.signedDifference(result.differenceSeconds))
                    LabeledContent("Источник", value: result.source)
                }
                Section {
                    Text("Знак расхождения показывает: время устройства − проверенное интернет-время.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    verify()
                } label: {
                    HStack {
                        if isLoading { ProgressView() }
                        Label(isLoading ? "Проверяем…" : "Сверить время", systemImage: "network")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
            }
        }
        .navigationTitle("Сверить время")
        .navigationBarTitleDisplayMode(.inline)
        .appErrorAlert($errorMessage)
    }

    private var displayTimeZone: TimeZone {
        container.repository.currentConfiguration()?.timeZone ?? .current
    }

    private func verify() {
        isLoading = true
        Task {
            do {
                result = try await container.timeVerificationService.verify()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
