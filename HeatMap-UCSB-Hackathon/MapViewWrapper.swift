import SwiftUI
import MapboxMaps
import CoreLocation
import FirebaseFirestore

struct MapViewWrapper: UIViewRepresentable {
    @StateObject private var locationManager = LocationManager()
    private let db = Firestore.firestore()
    
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
        
        // Add heat map when style is loaded
        mapView.mapboxMap.onNext(event: .styleLoaded) { _ in
            self.setupHeatmap(mapView)
        }
        
        return mapView
    }
    
    private func setupHeatmap(_ mapView: MapView) {
        print("🔄 Setting up heat map...")
        
        // Create a GeoJSON source with initial empty data
        var source = GeoJSONSource()
        source.data = .featureCollection(FeatureCollection(features: []))
        
        do {
            // Add source to the map
            try mapView.mapboxMap.style.addSource(source, id: "locations-source")
            print("✅ Added GeoJSON source")
            
            // Create and configure heat map layer
            var heatmapLayer = HeatmapLayer(id: "locations-heat")
            heatmapLayer.source = "locations-source"
            
            // Configure heat map properties with more visible settings
            heatmapLayer.heatmapRadius = .constant(30)  // Increased radius for better visibility
            heatmapLayer.heatmapOpacity = .constant(0.8)  // Increased opacity
            heatmapLayer.heatmapWeight = .constant(2.0)   // Increased weight
            heatmapLayer.heatmapIntensity = .constant(1.5)  // Increased intensity
            
            // Add layer to the map
            try mapView.mapboxMap.style.addLayer(heatmapLayer)
            print("✅ Added heat map layer")
            
            // Start listening for location updates
            startLocationUpdates(mapView)
        } catch {
            print("❌ Error setting up heat map: \(error)")
        }
    }
    
    private func startLocationUpdates(_ mapView: MapView) {
        print("🔄 Starting location updates...")
        
        // Listen to Firestore updates
        db.collection("locations")
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ Error listening to locations: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("❌ No documents found in locations collection")
                    return
                }
                
                print("📄 Found \(documents.count) location documents")
                
                // Convert locations to features
                let features = documents.compactMap { document -> Feature? in
                    guard let lat = document.data()["latitude"] as? Double,
                          let lon = document.data()["longitude"] as? Double else {
                        print("❌ Invalid location data in document: \(document.documentID)")
                        return nil
                    }
                    
                    print("📍 Processing location: lat: \(lat), lon: \(lon)")
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    return Feature(geometry: .point(Point(coordinate)))
                }
                
                print("🗺 Converting \(features.count) locations to heat map")
                
                // Update the source with new features
                let featureCollection = FeatureCollection(features: features)
                
                do {
                    // First, check if source exists
                    if (try? mapView.mapboxMap.style.sourceExists(withId: "locations-source")) == true {
                        try mapView.mapboxMap.style.updateGeoJSONSource(
                            withId: "locations-source",
                            geoJSON: .featureCollection(featureCollection)
                        )
                        print("✅ Heat map source updated with \(features.count) points")
                    } else {
                        print("❌ Source 'locations-source' not found")
                        // Try to recreate the source and layer
                        setupHeatmap(mapView)
                    }
                } catch {
                    print("❌ Error updating heat map: \(error)")
                }
            }
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        // Update logic if needed
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let db = Firestore.firestore()
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10 // Update every 10 meters
        
        // Request authorization first
        locationManager.requestAlwaysAuthorization()
        
        // Enable background updates
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
            "accuracy": location.horizontalAccuracy
        ]
        
        // Add to Firestore
        db.collection("locations").addDocument(data: locationData) { error in
            if let error = error {
                print("Error saving location: \(error.localizedDescription)")
            } else {
                print("Location saved successfully")
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
}