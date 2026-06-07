import AppReportKit
import SwiftUI

public struct FeedbackForm: View {
    @StateObject private var model: FeedbackFormViewModel

    private let copy: FeedbackFormCopy
    private let style: FeedbackFormStyle
    private let showsSeverityPicker: Bool
    private let screenContext: String?

    init(
        model: FeedbackFormViewModel,
        copy: FeedbackFormCopy = .standard,
        style: FeedbackFormStyle = .standard,
        showsSeverityPicker: Bool = true,
        screenContext: String? = nil
    ) {
        _model = StateObject(wrappedValue: model)
        self.copy = copy
        self.style = style
        self.showsSeverityPicker = showsSeverityPicker
        self.screenContext = screenContext
    }

    public init(
        client: AppReportClient,
        initialKind: FeedbackReportKind = .bug,
        showsSeverityPicker: Bool = true,
        screenContext: String? = nil,
        copy: FeedbackFormCopy = .standard,
        style: FeedbackFormStyle = .standard
    ) {
        self.init(
            model: FeedbackFormViewModel(
                submitter: client,
                initialKind: initialKind,
                copy: copy,
                screenContext: screenContext,
                supportOptions: .disabled,
                deliveryHandler: nil
            ),
            copy: copy,
            style: style,
            showsSeverityPicker: showsSeverityPicker,
            screenContext: screenContext
        )
    }

    public init(
        submitter: any FeedbackSubmitting,
        initialKind: FeedbackReportKind = .bug,
        showsSeverityPicker: Bool = true,
        screenContext: String? = nil,
        copy: FeedbackFormCopy = .standard,
        style: FeedbackFormStyle = .standard,
        supportOptions: FeedbackFormSupportOptions? = nil,
        deliveryHandler: FeedbackDeliveryHandler? = nil
    ) {
        let resolvedSupportOptions = supportOptions
            ?? (submitter as? any FeedbackFormSupportProviding)?.feedbackFormSupportOptions
            ?? .disabled

        self.init(
            model: FeedbackFormViewModel(
                submitter: submitter,
                initialKind: initialKind,
                copy: copy,
                screenContext: screenContext,
                supportOptions: resolvedSupportOptions,
                deliveryHandler: deliveryHandler
            ),
            copy: copy,
            style: style,
            showsSeverityPicker: showsSeverityPicker,
            screenContext: screenContext
        )
    }

    public var body: some View {
        Form {
            Section(copy.reportSectionTitle) {
                Picker(copy.kindLabel, selection: $model.kind) {
                    ForEach(FeedbackReportKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }
                .accessibilityIdentifier("appreportkit.kind-picker")

                if showsSeverityPicker {
                    Picker(copy.severityLabel, selection: $model.severity) {
                        ForEach(FeedbackSeverity.allCases, id: \.self) { severity in
                            Text(severity.rawValue.capitalized).tag(severity)
                        }
                    }
                    .accessibilityIdentifier("appreportkit.severity-picker")
                }

                if let screenContext, !screenContext.isEmpty {
                    HStack {
                        Text(copy.contextLabel)
                        Spacer()
                        Text(screenContext)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("appreportkit.context-value")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(copy.notesLabel)
                    ZStack(alignment: .topLeading) {
                        if model.notes.isEmpty {
                            Text(copy.notesPlaceholder)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $model.notes)
                            .frame(minHeight: 140)
                            .accessibilityIdentifier("appreportkit.notes-editor")
                    }
                }

                TextField(copy.emailPlaceholder, text: $model.email)
                    .accessibilityIdentifier("appreportkit.email-field")
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                if model.showsTechnicalDetailsToggle {
                    Toggle(copy.includeTechnicalDetailsLabel, isOn: $model.includeTechnicalDetails)
                        .accessibilityIdentifier("appreportkit.include-technical-details-toggle")
                }

                if model.showsScreenshotToggle {
                    Toggle(copy.includeScreenshotLabel, isOn: $model.includeScreenshot)
                        .accessibilityIdentifier("appreportkit.include-screenshot-toggle")
                }
            }

            Section {
                Button {
                    Task {
                        await model.submit()
                    }
                } label: {
                    if model.isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(copy.submitButtonTitle)
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("appreportkit.submit-button")
            }

            if model.isSubmitted {
                Text(copy.successMessage)
                    .foregroundStyle(.green)
                    .accessibilityIdentifier("appreportkit.success-message")
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("appreportkit.error-message")
            }
        }
        .appReportForeground(style.foregroundColor)
        .appReportBackground(style.backgroundColor)
        .appReportAccent(style.accentColor)
        .appReportFont(style.font)
    }
}

private extension View {
    @ViewBuilder
    func appReportForeground(_ color: Color?) -> some View {
        if let color {
            self.foregroundStyle(color)
        } else {
            self
        }
    }

    @ViewBuilder
    func appReportBackground(_ color: Color?) -> some View {
        if let color {
            self.background(color)
        } else {
            self
        }
    }

    @ViewBuilder
    func appReportAccent(_ color: Color?) -> some View {
        if let color {
            self.tint(color)
        } else {
            self
        }
    }

    @ViewBuilder
    func appReportFont(_ font: Font?) -> some View {
        if let font {
            self.font(font)
        } else {
            self
        }
    }
}
