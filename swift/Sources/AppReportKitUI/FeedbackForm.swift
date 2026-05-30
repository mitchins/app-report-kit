import AppReportKit
import SwiftUI

public struct FeedbackForm: View {
    @StateObject private var model: FeedbackFormViewModel

    private let copy: FeedbackFormCopy
    private let style: FeedbackFormStyle
    private let showsSeverityPicker: Bool
    private let screenContext: String?

    public init(
        client: AppReportClient,
        initialKind: FeedbackReportKind = .bug,
        showsSeverityPicker: Bool = true,
        screenContext: String? = nil,
        copy: FeedbackFormCopy = .default,
        style: FeedbackFormStyle = .default
    ) {
        _model = StateObject(
            wrappedValue: FeedbackFormViewModel(
                client: client,
                initialKind: initialKind,
                copy: copy,
                screenContext: screenContext
            )
        )
        self.copy = copy
        self.style = style
        self.showsSeverityPicker = showsSeverityPicker
        self.screenContext = screenContext
    }

    public var body: some View {
        Form {
            Section(copy.reportSectionTitle) {
                Picker(copy.kindLabel, selection: $model.kind) {
                    ForEach(FeedbackReportKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.capitalized).tag(kind)
                    }
                }

                if showsSeverityPicker {
                    Picker(copy.severityLabel, selection: $model.severity) {
                        ForEach(FeedbackSeverity.allCases, id: \.self) { severity in
                            Text(severity.rawValue.capitalized).tag(severity)
                        }
                    }
                }

                if let screenContext, !screenContext.isEmpty {
                    HStack {
                        Text(copy.contextLabel)
                        Spacer()
                        Text(screenContext)
                            .foregroundStyle(.secondary)
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
                        }

                        TextEditor(text: $model.notes)
                            .frame(minHeight: 140)
                    }
                }

                TextField(copy.emailPlaceholder, text: $model.email)
                    #if os(iOS)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
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
            }

            if model.isSubmitted {
                Text(copy.successMessage)
                    .foregroundStyle(.green)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
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
