import ClockKit
import SwiftUI

struct ClockApp: App {
    init() { ClockNotifications.install() }

    var body: some Scene {
        WindowGroup { ClockRoot() }
    }
}

ClockApp.main()
