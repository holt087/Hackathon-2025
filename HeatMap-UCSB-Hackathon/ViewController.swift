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

    // Add a new document with a generated ID
    do {
      let ref = try await db.collection("users").addDocument(data: [
        "first": "Ada",
        "last": "Lovelace",
        "born": 1815
      ])
      print("Document added with ID: \(ref.documentID)")
    } catch {
      print("Error adding document: \(error)")
    }

    // Add a second document with a generated ID.
    do {
    let ref = try await db.collection("users").addDocument(data: [
    "first": "Alan",
    "middle": "Mathison",
    "last": "Turing",
    "born": 1912
    ])
    print("Document added with ID: \(ref.documentID)")
    } catch {
    print("Error adding document: \(error)")
    }

    do {
      let snapshot = try await db.collection("users").getDocuments()
      for document in snapshot.documents {
        print("\(document.documentID) => \(document.data())")
      }
    } catch {
      print("Error getting documents: \(error)")
    }
} 
