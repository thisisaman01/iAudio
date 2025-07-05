//
//  SceneDelegate.swift
//  iAudio
//
//  Created by AMAN K.A on 04/07/25.
//

import UIKit
import SwiftData

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    
    var window: UIWindow?
    var modelContainer: ModelContainer?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        
        // Configure SwiftData with proper error handling
        do {
            let schema = Schema([
                RecordingSession.self,
                AudioSegment.self,
                TranscriptionResult.self
            ])
            
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
            
            print("✅ SwiftData ModelContainer initialized successfully")
            
        } catch {
            print("❌ Failed to initialize SwiftData: \(error)")
            print("Error details: \(error.localizedDescription)")
            
            // Fallback: Try with just the basic models
            do {
                modelContainer = try ModelContainer(for: RecordingSession.self)
                print("✅ SwiftData ModelContainer initialized with fallback")
            } catch {
                print("❌ Complete SwiftData initialization failure: \(error)")
                // Continue without SwiftData - app will show appropriate errors
            }
        }
        
        // Create root view controller
        let recordingViewController = RecordingSessionsViewController()
        let navigationController = UINavigationController(rootViewController: recordingViewController)
        
        // Set model context if available
        if let container = modelContainer {
            recordingViewController.modelContext = container.mainContext
            print("✅ ModelContext set on root view controller")
        } else {
            print("⚠️ No ModelContext available - data features will be disabled")
        }
        
        window.rootViewController = navigationController
        self.window = window
        window.makeKeyAndVisible()
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
    }
    
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
    }
    
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
    }
    
    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
    }
    
    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Save any changes if needed
        if let context = modelContainer?.mainContext {
            do {
                try context.save()
                print("✅ Context saved on background")
            } catch {
                print("❌ Failed to save context: \(error)")
            }
        }
    }
}
