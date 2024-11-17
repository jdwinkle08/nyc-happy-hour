import SwiftUI
import GoogleMaps
import GooglePlaces

// MARK: - Models
struct EventFields: Codable {
    let eventId: Int
    let place: [String]
    let placeName: [String]
    let day: String
    let startTime: String
    let endTime: String
    let isActive: String
    let description: String?
    let googleMapsId: [String]
    
    enum CodingKeys: String, CodingKey {
        case eventId = "Event ID"
        case place = "Place"
        case placeName = "Place Name"
        case day = "Day"
        case startTime = "Start Time"
        case endTime = "End Time"
        case isActive = "Happy Hour Active"
        case description = "Description"
        case googleMapsId = "Google Maps ID"
    }
}

struct Event: Identifiable, Codable {
    let id: String
    let createdTime: String
    let fields: EventFields
}

struct EventsResponse: Codable {
    let records: [Event]
}

struct PlaceDetails {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let rating: Double?
    let types: [String]
    let photo: GMSPlacePhotoMetadata?
    let formattedAddress: String?
    let categoryDescription: String?
    var eventDescription: String?
}

// MARK: - ViewModel
class MapViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showingActiveOnly = false
    
    private let airtablePAT = Secrets.airtablePAT
    private let baseId = Secrets.airtableBaseId
    private let eventsTableId = "tblepy4NKexAxYMfi"
    
    func fetchData() {
        fetchEvents()
    }
    
    private func fetchEvents() {
        print("Fetching events...")
        isLoading = true
        error = nil
        
        guard let url = URL(string: "https://api.airtable.com/v0/\(baseId)/\(eventsTableId)") else {
            error = "Invalid URL"
            isLoading = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(airtablePAT)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.error = error.localizedDescription
                    print("Network error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self?.error = "No data received"
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    let response = try decoder.decode(EventsResponse.self, from: data)
                    self?.events = response.records
                    print("Successfully fetched \(response.records.count) events")
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
    let events: [Event]
    let showingActiveOnly: Bool
    @Binding var selectedPlace: (String, PlaceDetails)?

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
        print("\nUpdating map view...")
        mapView.clear()
        
        let filteredEvents = showingActiveOnly ?
            events.filter { $0.fields.isActive == "Yes" } :
            events
        
        let uniqueGoogleMapsIds = Set(filteredEvents.flatMap { $0.fields.googleMapsId })
        print("Showing \(uniqueGoogleMapsIds.count) places on map")
        
        for googleMapsId in uniqueGoogleMapsIds {
            print("Fetching place details for Google Maps ID: \(googleMapsId)")

            let fields: GMSPlaceField = [.coordinate, .name, .types, .rating, .photos, .formattedAddress]

            GMSPlacesClient.shared().fetchPlace(
                fromPlaceID: googleMapsId,
                placeFields: fields,
                sessionToken: nil
            ) { gmsPlace, error in
                if let error = error {
                    print("❌ Error fetching place for ID \(googleMapsId): \(error.localizedDescription)")
                    return
                }

                guard let gmsPlace = gmsPlace else {
                    print("❌ No place found for ID \(googleMapsId)")
                    return
                }

                let event = filteredEvents.first { $0.fields.googleMapsId.contains(googleMapsId) }

                let details = PlaceDetails(
                    name: gmsPlace.name ?? "Unknown",
                    coordinate: gmsPlace.coordinate,
                    rating: Double(gmsPlace.rating),
                    types: gmsPlace.types ?? [],
                    photo: gmsPlace.photos?.first,
                    formattedAddress: gmsPlace.formattedAddress,
                    categoryDescription: gmsPlace.types?.first?.replacingOccurrences(of: "_", with: " ").capitalized,
                    eventDescription: event?.fields.description
                )

                DispatchQueue.main.async {
                    let marker = GMSMarker()
                    marker.position = details.coordinate
                    marker.title = details.name
                    marker.snippet = details.formattedAddress
                    marker.map = mapView
                    marker.icon = GMSMarker.markerImage(with: .systemBlue)
                    marker.userData = (googleMapsId: googleMapsId, details: details)
                    print("📍 Added marker for \(details.name)")
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
            if let (googleMapsId, details) = marker.userData as? (googleMapsId: String, details: PlaceDetails) {
                parent.selectedPlace = (googleMapsId, details)
            }
            return true
        }
    }
}

struct FilterButton: View {
    @Binding var isActive: Bool
    
    var body: some View {
        Button(action: { isActive.toggle() }) {
            Text("Happening Now")
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(isActive ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                )
                .foregroundColor(isActive ? .blue : .black)
        }
    }
}

struct PlaceDetailsCard: View {
    let googleMapsId: String
    let details: PlaceDetails
    @Binding var selectedPlace: (String, PlaceDetails)?
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

                        if let categoryDescription = details.categoryDescription {
                            Text(categoryDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let image = placeImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Happy Hour Deals:")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text(details.eventDescription ?? "(Still learning happy hour deals...)")
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
    @State private var selectedPlace: (String, PlaceDetails)? = nil
    
    var body: some View {
        ZStack(alignment: .bottom) { // Keeps the bottom alignment for PlaceDetailsCard
            MapViewContainer(
                events: viewModel.events,
                showingActiveOnly: viewModel.showingActiveOnly,
                selectedPlace: $selectedPlace
            )
            .ignoresSafeArea()
            .onAppear {
                viewModel.fetchData()
            }
            
            GeometryReader { geometry in
                VStack {
                    // Filter button placed directly below the safe area
                    HStack {
                        FilterButton(isActive: $viewModel.showingActiveOnly)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, geometry.safeAreaInsets.top) // Exact safe area top inset
                    
                    Spacer()
                }
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
            
            if let (googleMapsId, details) = selectedPlace {
                PlaceDetailsCard(
                    googleMapsId: googleMapsId,
                    details: details,
                    selectedPlace: $selectedPlace
                )
                .transition(.move(edge: .bottom))
            }
        }
    }
}
