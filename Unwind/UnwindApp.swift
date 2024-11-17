import SwiftUI
import GoogleMaps
import GooglePlaces

@main
struct UnwindApp: App {
    init() {
        GMSServices.provideAPIKey(Secrets.googleMapsApiKey)
        GMSPlacesClient.provideAPIKey(Secrets.googleMapsApiKey)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
