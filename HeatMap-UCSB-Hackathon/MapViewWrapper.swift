import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseFirestore

struct MapViewWrapper: UIViewRepresentable {
    @StateObject private var locationManager = LocationManager()
    
    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions(
            resourceOptions: ResourceOptions(accessToken: "pk.eyJ1IjoiZW1tZXR0ZnVuc3RvbiIsImEiOiJjbTVzbjJoZDEwb2o4MmxwbGxyZndvejd3In0.6LtI5A_OiRBniV0QzMauBA"),
            cameraOptions: CameraOptions(
                center: CLLocationCoordinate2D(latitude: 34.4140, longitude: -119.8489),
                zoom: 14.0
            ),
            styleURI: .streets
        )
        
        let mapView = MapView(frame: .zero, mapInitOptions: options)
        
        // Enable location tracking
        mapView.location.options.puckType = .puck2D()
        locationManager.startUpdating()
        
        // Add heat map layer when style is loaded
        mapView.mapboxMap.onNext(event: .styleLoaded) { _ in
            self.addHeatmapLayer(to: mapView)
        }
        
        return mapView
    }
    
    private func addHeatmapLayer(to mapView: MapView) {
        // Create a heat map layer
        var heatmapLayer = HeatmapLayer(id: "heatmap")
        heatmapLayer.source = "locations"
        
        // Configure heat map properties for precise building-sized visualization
        heatmapLayer.heatmapWeight = .constant(1.0)
        heatmapLayer.heatmapIntensity = .constant(1.0)
        heatmapLayer.heatmapRadius = .constant(10)  // Smaller radius for building-sized precision
        
        // Color configuration:
        // - No color (transparent) for 0 people
        // - Yellow for 1 person
        // - Red for more than 1 person
        heatmapLayer.heatmapColor = .expression(Expression(
            operator: "step",
            arguments: [
                Expression(operator: "heatmap-density"),
                Expression(operator: "rgba", arguments: [0, 0, 0, 0]),  // Transparent
                0.1,  // Threshold for 1 person
                Expression(operator: "rgba", arguments: [255, 255, 0, 0.7]),  // Yellow
                0.5,  // Threshold for more than 1 person
                Expression(operator: "rgba", arguments: [255, 0, 0, 0.7])  // Red
            ]
        ))
        
        // Add the layer to the map
        do {
            try mapView.mapboxMap.style.addLayer(heatmapLayer)
            loadLocationData(for: mapView)
        } catch {
            print("Error adding heatmap layer: \(error)")
        }
    }
    
    private func loadLocationData(for mapView: MapView) {
        let db = Firestore.firestore()
        
        // Query the last hour of location data
        let hourAgo = Date().addingTimeInterval(-3600)
        
        db.collection("locations")
            .whereField("timestamp", isGreaterThan: hourAgo)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("Error loading locations: \(error)")
                    return
                }
                
                guard let documents = snapshot?.documents else { return }
                
                // Convert documents to GeoJSON features
                let features = documents.compactMap { doc -> Feature? in
                    guard let lat = doc.data()["latitude"] as? Double,
                          let lon = doc.data()["longitude"] as? Double else {
                        return nil
                    }
                    
                    return Feature(geometry: .point(Point(CLLocationCoordinate2D(latitude: lat, longitude: lon))))
                }
                
                // Create a feature collection
                let featureCollection = FeatureCollection(features: features)
                
                // Add the source to the map
                var source = GeoJSONSource()
                source.data = .featureCollection(featureCollection)
                
                do {
                    try mapView.mapboxMap.style.addSource(source, id: "locations")
                } catch {
                    print("Error adding source: \(error)")
                }
            }
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
    }
}

// Location Manager class
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let db = Firestore.firestore()  // Initialize Firestore
    private let userId = UUID().uuidString  // Generate unique user ID
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.requestAlwaysAuthorization()
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = true
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    func startUpdating() {
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.location = location
        
        // Store location data in Firestore
        let locationData: [String: Any] = [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "timestamp": Date(),
            "userId": userId,
            "accuracy": location.horizontalAccuracy
        ]
        
        // Add to Firestore with better error handling and verification
        db.collection("locations").addDocument(data: locationData) { [weak self] error in
            if let error = error {
                print("❌ Error saving location: \(error.localizedDescription)")
            } else {
                print("✅ Location saved successfully!")
                
                // Verify the save by reading the last entry
                self?.verifyLastLocation()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            print("Always authorization granted")
            startUpdating()
        case .authorizedWhenInUse:
            print("When in use authorization granted - requesting always authorization")
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("Location access denied or restricted")
        case .notDetermined:
            print("Location authorization not determined")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    // Add this new function to verify data storage
    private func verifyLastLocation() {
        db.collection("locations")
            .whereField("userId", isEqualTo: userId)
            .order(by: "timestamp", descending: true)
            .limit(to: 1)
            .getDocuments { snapshot, error in
                if let error = error {
                    print("❌ Error verifying location: \(error.localizedDescription)")
                    return
                }
                
                guard let document = snapshot?.documents.first else {
                    print("❌ No location document found")
                    return
                }
                
                print("✅ Verified location data:")
                print("📍 Latitude: \(document.data()["latitude"] ?? "unknown")")
                print("📍 Longitude: \(document.data()["longitude"] ?? "unknown")")
                print("🕒 Timestamp: \(document.data()["timestamp"] ?? "unknown")")
            }
    }
}
