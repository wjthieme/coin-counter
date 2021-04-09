//
//  AppDelegate.swift
//  CoinCounter
//
//  Created by Wilhelm Thieme on 11/08/2019.
//  Copyright © 2019 Sogeti Nederland B.V. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    //Coins: https://www.leftovercurrency.com

    var window: UIWindow?


    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        Exchanger.initialize()
        
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = ViewController()
        window?.makeKeyAndVisible()
        
        return true
    }

}

