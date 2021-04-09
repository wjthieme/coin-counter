//
//  Money.swift
//  CoinCounter
//
//  Created by Wilhelm Thieme on 11/08/2019.
//  Copyright © 2019 Sogeti Nederland B.V. All rights reserved.
//

import Foundation

struct Money {
    let currency: String
    let amount: Float
    let id: String
    
    init?(_ id: String) {
        self.id = id
        guard let split = Money.split(id) else { return nil }
        self.currency = split.0
        self.amount = split.1
    }
    
    func exchanged(to id2: String) -> Float? {
        return Exchanger.exchange(amount, from: currency, to: id2)
    }
    
    var localizedString: String? { return Money.localizedString(id) }
    func exchangedAndLocalized(to id2: String) -> String? {
        guard let exchanged = exchanged(to: id2) else { return nil }
        return Money.localizedString("\(id2)\(exchanged)")
    }
    
    var imagePath: String? { return Bundle.main.path(forResource: id, ofType: "jpg", inDirectory: "Currency/\(currency)") }
    
    //MARK: Static
    
    static func split(_ id: String) -> (String, Float)? {
        let splitIndex = id.index(id.startIndex, offsetBy: 3)
        let currency = String(id[id.startIndex..<splitIndex])
        guard let amount = Float(String(id[splitIndex..<id.endIndex])) else { return nil }
        return (currency, amount)
    }
    
    static func localizedString(_ id: String) -> String? {
        guard let split = split(id) else { return nil }
        
        let components = [NSLocale.Key.currencyCode.rawValue: split.0]
        let localeIdentifier = NSLocale.localeIdentifier(fromComponents: components)
        let locale = Locale(identifier: localeIdentifier)
        let currency = locale.currencySymbol ?? ""
        
        let formatter = NumberFormatter()
        formatter.minimumIntegerDigits = 1
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        
        let amount = formatter.string(from: NSNumber(value: split.1)) ?? ""
        
        return "\(currency) \(amount)"
    }
    
    
}
