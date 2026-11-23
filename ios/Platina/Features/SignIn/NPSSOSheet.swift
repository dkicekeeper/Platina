import SwiftUI
import DesignTokens
import DesignComponents
import PSNKit

/// The manual sign-in: the person gets the NPSSO token in Safari and pastes it here. The way in
/// when Sony's page will not work inside the app.
struct NPSSOSheet: View {
    let onSubmit: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var input = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var token: String? { PSNAuth.normalizedNPSSO(input) }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "npsso.title"),
            saveTitle: String(localized: "npsso.submit"),
            isSaveDisabled: token == nil,
            isSaving: isSaving,
            onSave: submit,
            onCancel: { dismiss() }
        ) {
            FormSection(header: String(localized: "npsso.steps.header")) {
                UniversalRow(
                    String(localized: "npsso.step1"),
                    icon: "1.circle",
                    accessory: .action { openURL(PSNAuth.webSignInURL) }
                )
                UniversalRow(
                    String(localized: "npsso.step2"),
                    icon: "2.circle",
                    accessory: .action { openURL(PSNAuth.ssoCookieURL) }
                )
                UniversalRow(String(localized: "npsso.step3"), icon: "3.circle")
            }

            FormSection(
                header: String(localized: "npsso.field.header"),
                footer: String(localized: "npsso.field.footer")
            ) {
                FormTextField(
                    text: $input,
                    placeholder: String(localized: "npsso.field.placeholder"),
                    style: .rowMultiline(min: 2, max: 4),
                    errorMessage: errorMessage
                )
            }
        }
    }

    private func submit() {
        guard let token else { return }
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await onSubmit(token)
                dismiss()
            } catch {
                errorMessage = error.userMessage
            }
        }
    }
}
