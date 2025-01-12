import SwiftUI
import MapboxMaps

struct MapViewWrapper: UIViewRepresentable {
    func makeUIView(context: Context) -> MapView {
        let options = MapInitOptions(
            resourceOptions: ResourceOptions(accessToken: "pk.eyJ1IjoiZW1tZXR0ZnVuc3RvbiIsImEiOiJjbTVzbjJoZDEwb2o4MmxwbGxyZndvejd3In0.6LtI5A_OiRBniV0QzMauBA"),
            styleURI: .streets
        )
        
        let mapView = MapView(frame: .zero, mapInitOptions: options)
        
        // Center the map on UCSB campus
        let ucsbCoordinate = CLLocationCoordinate2D(latitude: 34.4140, longitude: -119.8489)
        let cameraOptions = CameraOptions(center: ucsbCoordinate, zoom: 15.0)
        mapView.camera.fly(to: cameraOptions, duration: 1.0)
        
        return mapView
    }
    
    func updateUIView(_ uiView: MapView, context: Context) {
        // Updates can be handled here
    }
}
