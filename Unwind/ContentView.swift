import SwiftUI
import GoogleMaps
import GooglePlaces

// MARK: - Models
struct Place: Identifiable, Codable, Equatable {
    var id: String { recordId }
    let recordId: String
    let googleMapsId: String?
    
    enum CodingKeys: String, CodingKey {
        case googleMapsId = "Google Maps ID"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.googleMapsId = try? container.decodeIfPresent(String.self, forKey: .googleMapsId)
        self.recordId = ""
    }
    
    init(recordId: String, googleMapsId: String?) {
        self.recordId = recordId
        self.googleMapsId = googleMapsId
    }
    
    static func == (lhs: Place, rhs: Place) -> Bool {
        return lhs.recordId == rhs.recordId && lhs.googleMapsId == rhs.googleMapsId
    }
}

struct AirtableResponse: Codable {
    let records: [AirtableRecord]
}

struct AirtableRecord: Codable {
    let id: String
    let fields: AirtableFields
    
    func toPlace() -> Place {
        Place(recordId: id, googleMapsId: fields.googleMapsId)
    }
}

struct AirtableFields: Codable {
    let googleMapsId: String?
    
    enum CodingKeys: String, CodingKey {
        case googleMapsId = "Google Maps ID"
    }
}

// MARK: - ViewModel
class MapViewModel: ObservableObject {
    @Published var places: [Place] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let airtablePAT = Secrets.airtablePAT
    private let baseId = Secrets.airtableBaseId
    private let tableName = "Places"
    
    func fetchPlaces() {
        print("Fetching places...")
        isLoading = true
        error = nil
        
        guard let url = URL(string: "https://api.airtable.com/v0/\(baseId)/\(tableName)") else {
            error = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(airtablePAT)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error.localizedDescription
                    print("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self?.error = "No data received"
                    print("No data received")
                    return
                }
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Raw response: \(jsonString)")
                }
                
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(AirtableResponse.self, from: data)
                    
                    self?.places = response.records.map { $0.toPlace() }
                    
                    for place in self?.places ?? [] {
                        print("Record ID: \(place.id)")
                        if let gmId = place.googleMapsId {
                            print("Has Google Maps ID: \(gmId)")
                        } else {
                            print("No Google Maps ID")
                        }
                    }
                    
                    print("Successfully decoded \(response.records.count) places")
                    
                    let placesWithGoogleMapsId = self?.places.filter { $0.googleMapsId != nil }.count ?? 0
                    print("Places with Google Maps ID: \(placesWithGoogleMapsId)")
                    print("Places without Google Maps ID: \(response.records.count - placesWithGoogleMapsId)")
                    
                } catch {
                    self?.error = "Decoding error: \(error.localizedDescription)"
                    print("Decoding error: \(error)")
                    
                    if let decodingError = error as? DecodingError {
                        switch decodingError {
                        case .keyNotFound(let key, let context):
                            print("Missing key: \(key.stringValue)")
                            print("Context: \(context.debugDescription)")
                        case .valueNotFound(let type, let context):
                            print("Missing value of type: \(type)")
                            print("Context: \(context.debugDescription)")
                        case .typeMismatch(let type, let context):
                            print("Type mismatch: expected \(type)")
                            print("Context: \(context.debugDescription)")
                        case .dataCorrupted(let context):
                            print("Data corrupted: \(context.debugDescription)")
                        @unknown default:
                            print("Unknown decoding error")
                        }
                    }
                }
            }
        }.resume()
    }
}

// MARK: - Views
struct MapViewContainer: UIViewRepresentable {
    let places: [Place]
    @Binding var selectedPlace: Place?

    func makeUIView(context: Context) -> GMSMapView {
        print("Creating map view...")
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
        print("\nUpdating map view with \(places.count) places...")
        mapView.clear()

        for place in places {
            guard let placeId = place.googleMapsId else {
                print("Skipping place with no Google Maps ID")
                continue
            }

            print("Fetching place details for Google Maps ID: \(placeId)")

            let fields: GMSPlaceField = [.coordinate, .name, .formattedAddress]

            GMSPlacesClient.shared().fetchPlace(
                fromPlaceID: placeId,
                placeFields: fields,
                sessionToken: nil
            ) { gmsPlace, error in
                if let error = error {
                    print("❌ Error fetching place for ID \(placeId): \(error.localizedDescription)")
                    return
                }

                guard let gmsPlace = gmsPlace else {
                    print("❌ No place found for ID \(placeId)")
                    return
                }

                print("✅ Successfully fetched place: \(gmsPlace.name ?? "Unnamed")")
                print("  - Coordinates: (\(gmsPlace.coordinate.latitude), \(gmsPlace.coordinate.longitude))")
                print("  - Address: \(gmsPlace.formattedAddress ?? "No address")")

                DispatchQueue.main.async {
                    let marker = GMSMarker()
                    marker.position = gmsPlace.coordinate
                    marker.title = gmsPlace.name
                    marker.snippet = gmsPlace.formattedAddress
                    marker.map = mapView
                    marker.icon = GMSMarker.markerImage(with: .systemBlue)
                    marker.userData = place
                    print("📍 Added marker for \(gmsPlace.name ?? "Unnamed")")
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }

    class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: MapViewContainer

        init(parent: MapViewContainer) {
            self.parent = parent
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let place = marker.userData as? Place {
                parent.selectedPlace = place
            }
            return true
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    @State private var selectedPlace: Place? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) {
            MapViewContainer(places: viewModel.places, selectedPlace: $selectedPlace)
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
            
            if let selectedPlace = selectedPlace {
                PlaceDetailsCard(place: selectedPlace, selectedPlace: $selectedPlace)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}

struct PlaceDetailsCard: View {
    let place: Place
    @Binding var selectedPlace: Place? // Add binding to control dismissal
    @State private var dragOffset = CGSize.zero
    
    var body: some View {
        VStack(spacing: 12) {
            // Handle bar for visual affordance - now draggable
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            
            // Place details
            VStack(alignment: .leading, spacing: 8) {
                Text("Record ID: \(place.recordId)")
                    .font(.headline)
                
                if let googleMapsId = place.googleMapsId {
                    Text("Google Maps ID: \(googleMapsId)")
                        .font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: UIScreen.main.bounds.height / 4)
        .background(
            Color(UIColor.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .edgesIgnoringSafeArea(.bottom)
        )
        .shadow(radius: 8)
        .offset(y: max(0, dragOffset.height)) // Only allow downward drag
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = gesture.translation
                }
                .onEnded { gesture in
                    if gesture.translation.height > 100 { // Threshold for dismissal
                        withAnimation(.spring()) {
                            selectedPlace = nil // Dismiss the card
                        }
                    } else {
                        withAnimation(.spring()) {
                            dragOffset = .zero // Reset position if not dismissed
                        }
                    }
                }
        )
        .animation(.spring(), value: dragOffset)
    }
}
