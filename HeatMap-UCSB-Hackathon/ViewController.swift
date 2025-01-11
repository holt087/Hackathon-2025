import UIKit
import MapboxMaps

class ViewController: UIViewController {
    private var mapView: MapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // The token will be automatically read from Info.plist
        let options = MapInitOptions()
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        view.addSubview(mapView)
    }
} 
