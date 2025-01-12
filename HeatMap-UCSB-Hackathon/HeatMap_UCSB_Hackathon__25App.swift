//
//  HeatMap_UCSB_Hackathon__25App.swift
//  HeatMap-UCSB Hackathon '25
//
//  Created by MacBookPro on 1/11/25.
//

import SwiftUI
import FireBaseCore

// create an app delegate
class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

@main
struct HeatMap_UCSB_Hackathon__25App: App {
    // register app delegate for Firebase setup
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
