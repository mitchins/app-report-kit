import SwiftUI

public struct FeedbackFormStyle {
    public var foregroundColor: Color?
    public var backgroundColor: Color?
    public var accentColor: Color?
    public var font: Font?

    public init(
        foregroundColor: Color? = nil,
        backgroundColor: Color? = nil,
        accentColor: Color? = nil,
        font: Font? = nil
    ) {
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.accentColor = accentColor
        self.font = font
    }

    public static let `default` = FeedbackFormStyle()
}

