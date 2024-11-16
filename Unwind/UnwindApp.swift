import SwiftUI
import GoogleMaps

@main
struct UnwindApp: App {
    init() {
        GMSServices.provideAPIKey("AIzaSyADhMicOhsBGNtiyx6O6zzFy-j-cUa-wgc")
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
