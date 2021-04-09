//
//  Exchanger.swift
//  CoinCounter
//
//  Created by Wilhelm Thieme on 11/08/2019.
//  Copyright © 2019 Sogeti Nederland B.V. All rights reserved.
//

import Foundation

fileprivate let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("exchangeRates.json")

class Rates: Codable {
    let rates: [String: Float]
    let base: String
    let date: String
    
    init(contentsOf url: URL) throws {
        let data = try Data(contentsOf: url)
        let obj = try JSONDecoder().decode(Rates.self, from: data)
        rates = obj.rates
        base = obj.base
        date = obj.date
    }
    
    func write(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
}

class Exchanger {
    private static let shared = Exchanger()
    private var rates: Rates?
    
    private init() {
        rates = try? Rates(contentsOf: fileURL)
        loadRates()
    }
    
    private func loadRates() {
        guard let url = URL(string: "https://api.exchangeratesapi.io/latest") else { return }
        URLSession.shared.dataTask(with: url, completionHandler: { (data, response, error) in
            guard let data = data else { return }
            guard let rates = try? JSONDecoder().decode(Rates.self, from: data) else { return }
            self.rates = rates
            try? rates.write(to: fileURL)
        }).resume()
    }
    
    @discardableResult static func initialize() -> Rates? { return shared.rates }
    
    static func exchange(_ amount: Float, from id1: String, to id2: String) -> Float? {
        if id1 == id2 { return amount }
        guard let rates = shared.rates else { return nil }
        
        if id1 == rates.base {
            guard let f2 = rates.rates[id2] else { return nil }
            return amount * f2
        } else if id2 == rates.base {
            guard let f1 = rates.rates[id1] else { return nil }
            return amount / f1
        } else {
            guard let f1 = rates.rates[id1] else { return nil }
            guard let f2 = rates.rates[id2] else { return nil }
            return f2/f1 * amount
        }
    }
    
}
