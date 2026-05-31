import AppReportKit
import AppReportKitUI
import SwiftUI

struct ContentView: View {
    let client: AppReportClient

    var body: some View {
        NavigationView {
            FeedbackForm(
                client: client,
                initialKind: .bug,
                showsSeverityPicker: true,
                screenContext: "InvoiceEditor",
                copy: .standard,
                style: .standard
            )
            .navigationTitle("Send Feedback")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(.stack)
    }
}
