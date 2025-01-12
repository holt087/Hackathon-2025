import UIKit
import MapboxMaps
import FirebaseCore
import FirebaseFirestore

class ViewController: UIViewController {
    
    var db: Firestore!
    
    private var mapView: MapView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // The token will be automatically read from Info.plist
        let options = MapInitOptions()
        mapView = MapView(frame: view.bounds, mapInitOptions: options)
        view.addSubview(mapView)
        
        db = Firestore.firestore()
        
        let ref = Firestore.firestore().collection("users").addDocument(data: [
            "first": "Ada",
            "last": "Lovelace",
            "born": 1815
        ])
        print("Document added with ID: \(ref.documentID)")
    }
}
