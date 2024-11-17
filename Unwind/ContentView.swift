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

struct PlaceDetails {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let rating: Double?
    let types: [String]
    let photo: GMSPlacePhotoMetadata? // This will store the main photo
    let formattedAddress: String?
    let categoryDescription: String?
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
                    print("Successfully decoded \(response.records.count) places")
                } catch {
                    self?.error = "Decoding error: \(error.localizedDescription)"
                    print("Decoding error: \(error)")
                }
            }
        }.resume()
    }
}

// MARK: - Views
struct MapViewContainer: UIViewRepresentable {
    let places: [Place]
    @Binding var selectedPlace: (Place, PlaceDetails)?

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

            let fields: GMSPlaceField = [.coordinate, .name, .types, .rating, .photos, .formattedAddress]

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

                // Retrieve the first photo (main photo)
                let mainPhoto = gmsPlace.photos?.first

                // Create PlaceDetails instance with main photo
                let details = PlaceDetails(
                    name: gmsPlace.name ?? "Unknown",
                    coordinate: gmsPlace.coordinate,
                    rating: Double(gmsPlace.rating),
                    types: gmsPlace.types ?? [],
                    photo: mainPhoto,
                    formattedAddress: gmsPlace.formattedAddress,
                    categoryDescription: gmsPlace.types?.first?.replacingOccurrences(of: "_", with: " ").capitalized
                )

                DispatchQueue.main.async {
                    let marker = GMSMarker()
                    marker.position = details.coordinate
                    marker.title = details.name
                    marker.snippet = details.formattedAddress
                    marker.map = mapView
                    marker.icon = GMSMarker.markerImage(with: .systemBlue)
                    marker.userData = (place, details)
                    print("📍 Added marker for \(details.name)")

                    // Optionally, fetch the photo image if you need to display it
                    if let photoMetadata = mainPhoto {
                        GMSPlacesClient.shared().loadPlacePhoto(photoMetadata) { photo, error in
                            if let error = error {
                                print("❌ Error loading photo for place \(details.name): \(error.localizedDescription)")
                                return
                            }
                            if let photo = photo {
                                // Use the photo UIImage here, e.g., you can display it on a custom marker or a callout
                                print("Successfully fetched main photo for \(details.name)")
                                // Example: Update the marker or callout with the photo if needed
                            }
                        }
                    }
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
            if let (place, details) = marker.userData as? (Place, PlaceDetails) {
                parent.selectedPlace = (place, details)
            }
            return true
        }
    }
}

struct PlaceDetailsCard: View {
    let place: Place
    let details: PlaceDetails
    @Binding var selectedPlace: (Place, PlaceDetails)?
    @State private var dragOffset = CGSize.zero
    @State private var placeImage: UIImage?
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            dragOffset = gesture.translation
                        }
                        .onEnded { gesture in
                            withAnimation(.spring()) {
                                if gesture.translation.height > 150 {
                                    // If dragged down significantly, close the card
                                    selectedPlace = nil
                                } else if gesture.translation.height < -50 {
                                    // If dragged up, expand the card
                                    isExpanded = true
                                    dragOffset = .zero
                                } else {
                                    // If dragged but not enough, toggle expand/collapse
                                    isExpanded.toggle()
                                    dragOffset = .zero
                                }
                            }
                        }
                )

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Title and rating section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details.name)
                            .font(.system(size: 24, weight: .bold))
                            .lineLimit(2)

                        if let rating = details.rating {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 16, weight: .medium))

                                HStack(spacing: 2) {
                                    ForEach(0..<5) { index in
                                        Image(systemName: index < Int(rating) ? "star.fill" : "star")
                                            .foregroundColor(.yellow)
                                            .font(.system(size: 12))
                                    }
                                }
                            }
                        }

                        // Fetch a more specific category or type
                        if let categoryDescription = details.categoryDescription {
                            Text(categoryDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Featured Photo Section
                    if let image = placeImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Happy Hour Deals Section (Placeholder Text)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Happy Hour Deals:")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("(happy hour description)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? UIScreen.main.bounds.height * 0.8 : UIScreen.main.bounds.height / 4)
        .background(
            Color(UIColor.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .edgesIgnoringSafeArea(.bottom)
        )
        .shadow(radius: 8)
        .offset(y: max(0, dragOffset.height))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = gesture.translation
                }
                .onEnded { gesture in
                    withAnimation(.spring()) {
                        if gesture.translation.height > 150 {
                            selectedPlace = nil
                        } else {
                            isExpanded = gesture.translation.height < -50
                            dragOffset = .zero
                        }
                    }
                }
        )
        .animation(.spring(), value: dragOffset)
        .onAppear {
            loadFeaturedPhoto()
        }
    }

    /// Fetches a more descriptive type or category for the place.
    private func getSpecificType() -> String? {
        let commonTypes = ["restaurant", "bar", "food", "point_of_interest"]
        let filteredTypes = details.types.filter { !commonTypes.contains($0) }
        return filteredTypes.first?.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Loads the featured photo for the place using the Google Places API.
private func loadFeaturedPhoto() {
        guard let photoMetadata = details.photo else { return }
        GMSPlacesClient.shared().loadPlacePhoto(photoMetadata) { image, error in
            if let error = error {
                print("Error loading featured photo: \(error.localizedDescription)")
                return
            }
            if let image = image {
                DispatchQueue.main.async {
                    self.placeImage = image
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = MapViewModel()
    @State private var selectedPlace: (Place, PlaceDetails)? = nil
    
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
            
            if let (place, details) = selectedPlace {
                PlaceDetailsCard(place: place, details: details, selectedPlace: $selectedPlace)
                    .transition(.move(edge: .bottom))
            }
        }
    }
}
