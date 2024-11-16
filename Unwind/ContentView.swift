import SwiftUI
import GoogleMaps

struct ContentView: View {
    var body: some View {
        MapViewContainer()
    }
}

struct MapViewContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(latitude: 40.7128,
                                     longitude: -74.0060,
                                     zoom: 12)
        
        let mapOptions = GMSMapViewOptions()
        mapOptions.camera = camera
        
        let mapView = GMSMapView(options: mapOptions)
        return mapView
    }
    
    func updateUIView(_ uiView: GMSMapView, context: Context) {}
}
