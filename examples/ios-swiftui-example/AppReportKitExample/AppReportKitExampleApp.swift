import AppReportKit
import AppReportKitUI
import SwiftUI

@main
struct AppReportKitExampleApp: App {
    private let client = ExampleClientFactory.makeClient()

    var body: some Scene {
        WindowGroup {
            ContentView(client: client)
        }
    }
}
