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
    let neighborhood: [String]
    
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
        case neighborhood = "Neighborhood"
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
    
    static func getCategoryDescription(from place: GMSPlace) -> String? {
        let commonTypes = ["point_of_interest", "establishment", "food", "restaurant", "store"]
        if let specificType = place.types?.first(where: { !commonTypes.contains($0) }) {
            let formattedType = specificType
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            print("Found specific type for \(place.name ?? "Unknown"): \(formattedType)")
            return formattedType
        }
        print("No specific type found for \(place.name ?? "Unknown"), types: \(place.types ?? [])")
        return nil
    }
}

// MARK: - ViewModel
class MapViewModel: ObservableObject {
    @Published var events: [Event] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var showingActiveOnly = false
    @Published var selectedNeighborhoods: Set<String> = []
    @Published var isNeighborhoodFilterExpanded = false
    
    private let airtablePAT = Secrets.airtablePAT
    private let baseId = Secrets.airtableBaseId
    private let eventsTableId = "tblepy4NKexAxYMfi"
    
    var uniqueNeighborhoods: [String] {
        let allNeighborhoods = Set(events.flatMap { $0.fields.neighborhood })
        return Array(allNeighborhoods).sorted()
    }
    
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
                }
            }
        }.resume()
    }
    
    func filteredEvents() -> [Event] {
        var filtered = events
        
        if showingActiveOnly {
            filtered = filtered.filter { $0.fields.isActive == "Yes" }
        }
        
        if !selectedNeighborhoods.isEmpty {
            filtered = filtered.filter { event in
                !Set(event.fields.neighborhood).isDisjoint(with: selectedNeighborhoods)
            }
        }
        
        return filtered
    }
}

// MARK: - Views
struct RatingStarsView: View {
    let rating: Double
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                let value = rating - Double(index)
                Group {
                    if value >= 0.8 {
                        Image(systemName: "star.fill")
                    } else if value >= 0.3 {
                        Image(systemName: "star.leadinghalf.filled")
                    } else {
                        Image(systemName: "star")
                    }
                }
            }
        }
        .foregroundColor(.yellow)
        .font(.system(size: 12))
        .onAppear {
            print("Rendering stars for rating: \(rating)")
        }
    }
}

struct MapViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: MapViewModel
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
        
        let filteredEvents = viewModel.filteredEvents()
        
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
                    categoryDescription: PlaceDetails.getCategoryDescription(from: gmsPlace),
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
                .font(.system(size: 15, weight: .medium))
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

struct NeighborhoodFilterButton: View {
    @ObservedObject var viewModel: MapViewModel
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Filter button container
            Button(action: {
                withAnimation {
                    viewModel.isNeighborhoodFilterExpanded.toggle()
                }
            }) {
                HStack {
                    Text(buttonTitle)
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(viewModel.isNeighborhoodFilterExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(!viewModel.selectedNeighborhoods.isEmpty ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(!viewModel.selectedNeighborhoods.isEmpty ? .blue : .black)
            
            // Dropdown overlay
            if viewModel.isNeighborhoodFilterExpanded {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.uniqueNeighborhoods, id: \.self) { neighborhood in
                                Button(action: {
                                    withAnimation {
                                        if viewModel.selectedNeighborhoods.contains(neighborhood) {
                                            viewModel.selectedNeighborhoods.remove(neighborhood)
                                        } else {
                                            viewModel.selectedNeighborhoods.insert(neighborhood)
                                        }
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        if viewModel.selectedNeighborhoods.contains(neighborhood) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        } else {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.clear)
                                        }
                                        
                                        Text(neighborhood)
                                            .font(.system(size: 15, weight: viewModel.selectedNeighborhoods.contains(neighborhood) ? .semibold : .regular))
                                            .foregroundColor(viewModel.selectedNeighborhoods.contains(neighborhood) ? .blue : .primary)
                                        
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(.top, 12)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 150)
                    
                    if !viewModel.selectedNeighborhoods.isEmpty {
                        Divider()
                        Button(action: {
                            withAnimation {
                                viewModel.selectedNeighborhoods.removeAll()
                                viewModel.isNeighborhoodFilterExpanded = false
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "xmark.circle.fill")
                                Text("Clear Filter")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal)
                    }
                }
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.2), radius: 4)
                .offset(y: 45)
                .frame(maxWidth: 280)
            }
        }
    }
    
    private var buttonTitle: String {
        if viewModel.selectedNeighborhoods.isEmpty {
            return "Neighborhood"
        } else if viewModel.selectedNeighborhoods.count == 1 {
            return viewModel.selectedNeighborhoods.first ?? ""
        } else {
            return "\(viewModel.selectedNeighborhoods.count) Selected"
        }
    }
}

struct GoogleMapsButton: View {
    let googleMapsId: String
    
    var body: some View {
        Button(action: {
            openInGoogleMaps()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                Text("View in Google Maps")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(UIColor.systemGray6))
            .foregroundColor(.blue)
            .cornerRadius(10)
        }
        .padding(.horizontal)
        .buttonStyle(PressableButtonStyle())
    }
    
    private func openInGoogleMaps() {
        let urlString = "https://www.google.com/maps/place/?q=place_id:\(googleMapsId)"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
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
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color.gray.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(details.name)
                            .font(.system(size: 24, weight: .bold))
                            .lineLimit(2)

                        if let categoryDescription = details.categoryDescription {
                            Text(categoryDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let rating = details.rating {
                            HStack(spacing: 4) {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 16, weight: .medium))
                                RatingStarsView(rating: rating)
                            }
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
                    
                    GoogleMapsButton(googleMapsId: googleMapsId)
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
        ZStack {
            // Map layer
            MapViewContainer(
                viewModel: viewModel,
                selectedPlace: $selectedPlace
            )
            .ignoresSafeArea()
            .onAppear {
                viewModel.fetchData()
            }
            
            // Filter buttons layer - simplified structure
            VStack {
                HStack(spacing: 12) {
                    FilterButton(isActive: $viewModel.showingActiveOnly)
                    NeighborhoodFilterButton(viewModel: viewModel)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Spacer()
                
                if let (googleMapsId, details) = selectedPlace {
                    PlaceDetailsCard(
                        googleMapsId: googleMapsId,
                        details: details,
                        selectedPlace: $selectedPlace
                    )
                }
            }
            
            // Loading and error overlays
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
