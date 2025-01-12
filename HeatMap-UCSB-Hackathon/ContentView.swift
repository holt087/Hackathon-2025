import SwiftUI

struct ContentView: View {
    var body: some View {
        MapViewWrapper()
            .edgesIgnoringSafeArea(.all) // This makes the map full screen
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
