import SwiftUI
import GoogleMaps
import GooglePlaces

// Model matching your Airtable schema with field IDs
struct Place: Identifiable, Codable {
    let id: Int
    let googleMapsId: String
    let name: String
    let address: String
    let neighborhood: [String]
    let borough: String
    
    enum CodingKeys: String, CodingKey {
        case id = "fldjGU5XFNQZvSRTw"
        case googleMapsId = "fldRrE7awVnQaBpxf"
        case name = "fldCewXJVSQjNqcGD"
        case address = "fldY1hXTZdbu0w8R0"
        case neighborhood = "fldWOLkzhbkgeyW4P"
        case borough = "fldwqiKbbOneZCUbk"
    }
}

class MapViewModel: ObservableObject {
    @Published var places: [Place] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let airtablePAT = Secrets.airtablePAT  // Changed from airtableApiKey
    private let baseId = Secrets.airtableBaseId
    private let tableName = "Places"
    
    func fetchPlaces() {
        print("Fetching places...")
        isLoading = true
        error = nil
        
        guard let url = URL(string: "https://api.airtable.com/v0/\(baseId)/\(tableName)") else {
            error = "Invalid URL"
            isLoading = false
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        // Update the Authorization header for PAT
        request.setValue("Bearer \(airtablePAT)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            print("Got response...")
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error.localizedDescription
                    print("Error: \(error)")
                    return
                }
                
                guard let data = data else {
                    self?.error = "No data received"
                    print("No data received")
                    return
                }
                
                // Print raw response for debugging
                print("Raw response: \(String(data: data, encoding: .utf8) ?? "No data")")
                
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(AirtableResponse.self, from: data)
                    self?.places = response.records.map { $0.fields }
                    print("Got \(response.records.count) places")
                } catch {
                    self?.error = "Decoding error: \(error.localizedDescription)"
                    print("Decoding error: \(error)")
                }
            }
        }.resume()
    }
}

struct AirtableResponse: Codable {
    let records: [AirtableRecord]
}

struct AirtableRecord: Codable {
    let fields: Place
}

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    
    var body: some View {
        ZStack {
            MapViewContainer(places: viewModel.places)
                .ignoresSafeArea()
                .onAppear {
                    viewModel.fetchPlaces()
                }
            
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.2))
            }
            
            if let error = viewModel.error {
                VStack {
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.subheadline)
                }
                .padding()
                .background(Color.white)
                .cornerRadius(8)
                .shadow(radius: 4)
            }
        }
    }
}

struct MapViewContainer: UIViewRepresentable {
    let places: [Place]
    
    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition(latitude: 40.7128,
                                     longitude: -74.0060,
                                     zoom: 12)
        
        let mapOptions = GMSMapViewOptions()
        mapOptions.camera = camera
        
        let mapView = GMSMapView(options: mapOptions)
        mapView.delegate = context.coordinator
        return mapView
    }
    
    func updateUIView(_ mapView: GMSMapView, context: Context) {
        // Clear existing markers
        mapView.clear()
        
        // Add markers for each place
        places.forEach { place in
            let placeProperties = ["coordinate", "name", "formattedAddress"]
            let request = GMSFetchPlaceRequest(placeID: place.googleMapsId,
                                             placeProperties: placeProperties,
                                             sessionToken: nil)
            
            GMSPlacesClient.shared().fetchPlace(with: request) { gmsPlace, error in
                if let error = error {
                    print("Lookup place id error for \(place.name): \(error.localizedDescription)")
                    return
                }
                
                guard let gmsPlace = gmsPlace else {
                    print("No place found for \(place.name)")
                    return
                }
                
                DispatchQueue.main.async {
                    let marker = GMSMarker()
                    marker.position = gmsPlace.coordinate
                    marker.title = place.name
                    marker.snippet = place.address
                    marker.userData = place
                    marker.map = mapView
                    
                    // Customize marker appearance
                    marker.icon = GMSMarker.markerImage(with: .systemBlue)
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: MapViewContainer
        
        init(_ parent: MapViewContainer) {
            self.parent = parent
        }
        
        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let place = marker.userData as? Place {
                print("Tapped: \(place.name) in \(place.borough)")
                // You can add custom tap behavior here
            }
            return false
        }
    }
}
