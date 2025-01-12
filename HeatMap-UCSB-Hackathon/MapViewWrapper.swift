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
        
        // Query only recent locations (last 10 seconds)
        let tenSecondsAgo = Date().addingTimeInterval(-10) // 10 seconds
        
        db.collection("locations")
            .whereField("timestamp", isGreaterThan: tenSecondsAgo)
            .addSnapshotListener { querySnapshot, error in
                if let error = error {
                    print("❌ Error listening to locations: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = querySnapshot?.documents else {
                    print("❌ No documents found in locations collection")
                    return
                }
                
                print("📄 Found \(documents.count) recent location documents")
                
                // Convert locations to features
                let features = documents.compactMap { document -> Feature? in
                    guard let geoPoint = document.data()["location"] as? GeoPoint else {
                        return nil
                    }
                    
                    print("📍 Processing location: \(geoPoint)")
                    let coordinate = CLLocationCoordinate2D(
                        latitude: geoPoint.latitude,
                        longitude: geoPoint.longitude
                    )
                    return Feature(geometry: .point(Point(coordinate)))
                }
                
                // Update the source with new features
                let featureCollection = FeatureCollection(features: features)
                
                do {
                    try mapView.mapboxMap.style.updateGeoJSONSource(
                        withId: "locations-source",
                        geoJSON: .featureCollection(featureCollection)
                    )
                    
                    // Fixed: Get coordinates from the most recent point
                    if let mostRecent = features.last,
                       case let .point(point) = mostRecent.geometry {
                        mapView.camera.ease(
                            to: CameraOptions(
                                center: point.coordinates,
                                zoom: 14.0
                            ),
                            duration: 0.5
                        )
                    }
                    
                    print("✅ Heat map updated with \(features.count) recent points")
                } catch {
                    print("❌ Error updating heat map: \(error)")
                }
            }
        
        // Clean up old locations every 10 seconds
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            cleanOldLocations()
        }
    }
    
    private func cleanOldLocations() {
        let tenSecondsAgo = Date().addingTimeInterval(-10) // Changed from 300 to 10 seconds
        
        db.collection("locations")
            .whereField("timestamp", isLessThan: tenSecondsAgo)
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                for document in documents {
                    document.reference.delete()
                }
                print("🧹 Cleaned up \(documents.count) old locations")
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
        
        print("📱 Current user location updated:")
        print("   - Latitude: \(location.coordinate.latitude)")
        print("   - Longitude: \(location.coordinate.longitude)")
        
        // Create GeoPoint from coordinates
        let geoPoint = GeoPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        
        // Store location data in Firestore using GeoPoint
        let locationData: [String: Any] = [
            "location": geoPoint,
            "timestamp": Date(),
            "userId": "current_user",
            "accuracy": location.horizontalAccuracy
        ]
        
        // Add to Firestore
        db.collection("locations").addDocument(data: locationData) { error in
            if let error = error {
                print("❌ Error saving current user location: \(error.localizedDescription)")
            } else {
                print("✅ Current user location saved successfully")
                print("   Location saved as GeoPoint: \(geoPoint)")
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

}
