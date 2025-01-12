import SwiftUI
import MapboxMaps
import CoreLocation

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
        
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
    }
}

// Location Manager class
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
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
        print("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
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
