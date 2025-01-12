import SwiftUI
import MapboxMaps
import FirebaseFirestore
import FirebaseCore

struct ContentView: View {
    var body: some View {
        MapViewWrapper()
            .edgesIgnoringSafeArea(.all)
    }
}

struct MapViewWrapper: UIViewRepresentable {
    @StateObject private var locationManager = LocationDataManager()
    private let db = Firestore.firestore()
    private var firestoreListener: ListenerRegistration?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

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
        
        // Center the map on UCSB campus
        let ucsbCoordinate = CLLocationCoordinate2D(latitude: 34.4140, longitude: -119.8489)
        let cameraOptions = CameraOptions(center: ucsbCoordinate, zoom: 15.0)
        mapView.camera.fly(to: cameraOptions, duration: 1.0)
        
        // Setup map after loading
        mapView.mapboxMap.onNext(.mapLoaded) { _ in
            setupHeatmapLayer(for: mapView)
            listenToFirebaseUpdates(mapView: mapView)
        }
        
        return mapView
    }


    func updateUIView(_ uiView: MapView, context: Context) {
    // Update camera if user's location changes
    if let currentLocation = locationManager.currentLocation {
        let coordinate = currentLocation.coordinate
        let camera = CameraOptions(
            center: coordinate,
            zoom: 15.0
        )
        
        // Only update if significant change in location
        if shouldUpdateCamera(currentLocation: coordinate, mapCenter: uiView.mapboxMap.cameraState.center) {
            uiView.camera.ease(to: camera, duration: 0.5)
        }
    }
    
    // Optionally refresh heatmap data periodically
    refreshHeatmapData(mapView: uiView)
    }   

    // Helper functions for updateUIView
    private func shouldUpdateCamera(currentLocation: CLLocationCoordinate2D, mapCenter: CLLocationCoordinate2D) -> Bool {
        // Calculate distance between current map center and new location
        let currentPoint = CLLocation(latitude: currentLocation.latitude, longitude: currentLocation.longitude)
        let mapCenterPoint = CLLocation(latitude: mapCenter.latitude, longitude: mapCenter.longitude)
        
        // Only update if moved more than 20 meters
        return currentPoint.distance(from: mapCenterPoint) > 20
    }

    private func refreshHeatmapData(mapView: MapView) {
        // Fetch latest data from Firebase if needed
        db.collection("locations")
            .whereField("timestamp", isGreaterThan: Date().addingTimeInterval(-300)) // Last 5 minutes
            .getDocuments { snapshot, error in
                guard let documents = snapshot?.documents else { return }
                
                let features = documents.compactMap { document -> Feature? in
                    guard let geoPoint = document.data()["location"] as? GeoPoint,
                        let groupSize = document.data()["groupSize"] as? Double else {
                        return nil
                    }
                    
                    let coordinate = CLLocationCoordinate2D(
                        latitude: geoPoint.latitude,
                        longitude: geoPoint.longitude
                    )
                    
                    return Feature(
                        geometry: .point(Point(coordinate)),
                        properties: ["magnitude": .number(groupSize)]
                    )
                }
                
                updateHeatmapSource(features: features, mapView: mapView)
        }
    }
        

    private func setupHeatmapLayer(for mapView: MapView) {
        // Create initial empty source
        var source = GeoJSONSource()
        source.data = .featureCollection(FeatureCollection(features: []))
        
        // Add source to map
        try? mapView.mapboxMap.style.addSource(source, id: "heat-source")
        
        // Configure heatmap layer
        var heatmapLayer = HeatmapLayer(id: "heat-layer")
        heatmapLayer.source = "heat-source"
        
        // Style the heatmap
        heatmapLayer.heatmapWeight = .expression(Exp(.interpolate) {
            Exp(.linear)
            Exp(.get) { "magnitude" }
            0
            0
            10
            1
        })

        heatmapLayer.heatmapIntensity = .constant(1)
        heatmapLayer.heatmapRadius = .constant(25)
        heatmapLayer.heatmapColor = .expression(Exp(.interpolate) {
            Exp(.linear)
            Exp(.heatmapDensity)
            0
            .rgba(33, 102, 172, 0)    // Light blue
            0.2
            .rgba(103, 169, 207, 0.6)  // Medium blue
            0.4
            .rgba(209, 229, 240, 0.7)  // Light blue
            0.6
            .rgba(253, 219, 199, 0.8)  // Light red
            0.8
            .rgba(239, 138, 98, 0.9)   // Medium red
            1
            .rgba(178, 24, 43, 1)      // Dark red
        })
        
        try? mapView.mapboxMap.style.addLayer(heatmapLayer)
    }

    func cleanup() {
        firestoreListener?.remove()
    }

    private func listenToFirebaseUpdates(mapView: MapView) {
        db.collection("locations")
            .addSnapshotListener { querySnapshot, error in
                guard let documents = querySnapshot?.documents else {
                    print("Error fetching documents: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                // Convert Firebase data to GeoJSON source
                let source = createSourceFromFirebase(documents)
                
                // Update the source on the map
                try? mapView.mapboxMap.style.updateGeoJSONSource(
                    withId: "heat-source",
                    geoJSON: source.data ?? .featureCollection(FeatureCollection(features: []))
                )
            }
    }
}

private func updateHeatmapSource(features: [Feature], mapView: MapView) {
    let featureCollection = FeatureCollection(features: features)
    do {
        try mapView.mapboxMap.style.updateGeoJSONSource(
            withId: "heat-source",
            geoJSON: .featureCollection(featureCollection)
        )
    } catch {
        print("Failed to update heatmap source: \(error)")
    }
}

class Coordinator: NSObject {
    weak var parent: MapViewWrapper?
    
    init(_ parent: MapViewWrapper) {
        self.parent = parent
        super.init()
    }
}

class LocationDataManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private var locationManager = CLLocationManager()
    @Published var currentLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

extension MapViewWrapper {
    func addGroupLocation(coordinate: CLLocationCoordinate2D, groupSize: Double) {
        db.collection("locations").addDocument(data: [
            "location": GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude),
            "groupSize": groupSize,
            "timestamp": FieldValue.serverTimestamp()
        ]) { error in
            if let error = error {
                print("Error adding location: \(error.localizedDescription)")
            }
        }
    }
    
func removeOldLocations(olderThan hours: Int = 24) {
    let timestamp = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
    
    db.collection("locations")
        .whereField("timestamp", isLessThan: timestamp)
        .getDocuments { snapshot, error in
            guard let documents = snapshot?.documents else { return }
            
            for document in documents {
                document.reference.delete()
            }
        }
}

    
}
