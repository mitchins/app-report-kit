import AppReportKit
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct FeedbackForm: View {
    @StateObject private var model: FeedbackFormViewModel

    private let copy: FeedbackFormCopy
    private let style: FeedbackFormStyle
    private let screenContext: String?

    init(
        model: FeedbackFormViewModel,
        copy: FeedbackFormCopy = .standard,
        style: FeedbackFormStyle = .standard,
        screenContext: String? = nil
    ) {
        _model = StateObject(wrappedValue: model)
        self.copy = copy
        self.style = style
        self.screenContext = screenContext
    }

    public init(
        client: AppReportClient,
        initialKind: FeedbackReportKind = .bug,
        showsSeverityPicker: Bool? = nil,
        screenContext: String? = nil,
        copy: FeedbackFormCopy = .standard,
        style: FeedbackFormStyle = .standard,
        policy: FeedbackFormPolicy? = nil
    ) {
        let resolvedPolicy = policy ?? .standard
        let policyWithSeverity = resolvedPolicy.with(showsSeverityPicker: showsSeverityPicker)
        self.init(
            model: FeedbackFormViewModel(
                submitter: client,
                initialKind: initialKind,
                copy: copy,
                screenContext: screenContext,
                supportOptions: .disabled,
                policy: policyWithSeverity,
                deliveryHandler: nil
            ),
            copy: copy,
            style: style,
            screenContext: screenContext
        )
    }

    public init(
        submitter: any FeedbackSubmitting,
        initialKind: FeedbackReportKind = .bug,
        showsSeverityPicker: Bool? = nil,
        screenContext: String? = nil,
        copy: FeedbackFormCopy = .standard,
        style: FeedbackFormStyle = .standard,
        supportOptions: FeedbackFormSupportOptions? = nil,
        deliveryHandler: FeedbackDeliveryHandler? = nil,
        policy: FeedbackFormPolicy? = nil
    ) {
        let resolvedSupportOptions = supportOptions
            ?? (submitter as? any FeedbackFormSupportProviding)?.feedbackFormSupportOptions
            ?? .disabled
        let resolvedPolicy = policy
            ?? (submitter as? any FeedbackFormPolicyProviding)?.feedbackFormPolicy
            ?? .standard
        let routeAwarePolicy = (submitter as? any FeedbackSubmissionRouteProviding)?.feedbackSubmissionRoute == .email
            ? resolvedPolicy.with(
                emailOptions: .init(allowsEmail: false, requiresEmail: false)
            )
            : resolvedPolicy
        let policyWithSeverity = routeAwarePolicy.with(showsSeverityPicker: showsSeverityPicker)

        self.init(
            model: FeedbackFormViewModel(
                submitter: submitter,
                initialKind: initialKind,
                copy: copy,
                screenContext: screenContext,
                supportOptions: resolvedSupportOptions,
                policy: policyWithSeverity,
                deliveryHandler: deliveryHandler
            ),
            copy: copy,
            style: style,
            screenContext: screenContext
        )
    }

    public var body: some View {
        Form {
            Section(copy.reportSectionTitle) {
                if model.showsKindPicker {
                    Picker(copy.kindLabel, selection: $model.kind) {
                        ForEach(model.kindOptions, id: \.self) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                    .accessibilityIdentifier("appreportkit.kind-picker")
                }

                if model.showsSeverityPicker {
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

                if model.showsEmailField {
                    TextField(copy.emailPlaceholder, text: $model.email)
                        .accessibilityIdentifier("appreportkit.email-field")
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                }

                if model.showsTechnicalDetailsToggle {
                    Toggle(copy.includeTechnicalDetailsLabel, isOn: $model.includeTechnicalDetails)
                        .accessibilityIdentifier("appreportkit.include-technical-details-toggle")
                }

                if model.showsScreenshotToggle {
                    Toggle(copy.includeScreenshotLabel, isOn: $model.includeScreenshot)
                        .accessibilityIdentifier("appreportkit.include-screenshot-toggle")

                    if model.includeScreenshot, !model.screenshotPreviews.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.screenshotPreviews) { screenshot in
                                HStack(alignment: .top, spacing: 10) {
                                    if let screenshotImage = makeFeedbackFormImage(from: screenshot.data) {
                                        screenshotImage
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 80, alignment: .center)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                            .clipped()
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(screenshot.filename)
                                            .font(.caption)
                                            .lineLimit(1)

                                        Text(screenshot.contentType)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)

                                        Button("Remove") {
                                            model.removeScreenshot(screenshot.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .accessibilityIdentifier("appreportkit.remove-screenshot-button")
                                    }

                                    Spacer()
                                }
                                Divider()
                            }
                        }
                        .accessibilityIdentifier("appreportkit.screenshot-preview")
                    }
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
                        Text(model.submitButtonTitle)
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

private func makeFeedbackFormImage(from data: Data) -> Image? {
    #if os(iOS)
    UIImage(data: data).map { Image(uiImage: $0) }
    #elseif os(macOS)
    NSImage(data: data).map { Image(nsImage: $0) }
    #else
    nil
    #endif
}
