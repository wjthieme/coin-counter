//
//  MoneyView.swift
//  CoinCounter
//
//  Created by Wilhelm Thieme on 12/08/2019.
//  Copyright © 2019 Sogeti Nederland B.V. All rights reserved.
//

import UIKit

class MoneyView: UIView {
    
    override var canBecomeFirstResponder: Bool { return true }
    
    var closeAction: (() -> Void)?
    var closeAnimations: (() -> Void)?
    var shakeAction: (() -> Void)?
    
    private var bottomConstraint: NSLayoutConstraint?
    
    private let closeButton = UIButton()
    private let imageView = UIImageView()
    private let originalLabel = UILabel()
    private let convertedLabel = UILabel()
    
    private let officialCurrency = UILabel()
    private let officialLabel = UILabel()
    private let acceptedIn = UILabel()
    private let acceptedLabel = UILabel()
    
    init(_ money: Money) {
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        layer.cornerRadius = .cornerWidth
        
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "close_icon"), for: .normal)
        closeButton.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        closeButton.tintColor = .black
        addSubview(closeButton)
        closeButton.topAnchor.constraint(equalTo: topAnchor, constant: .padding).activated()
        closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.padding).activated()
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.image = UIImage(contentsOfFile: money.imagePath ?? "")
        addSubview(imageView)
        imageView.topAnchor.constraint(equalTo: topAnchor, constant: .padding).activated()
        imageView.centerXAnchor.constraint(equalTo: centerXAnchor).activated()
        imageView.heightAnchor.constraint(equalToConstant: .padding*6).activated()
        imageView.widthAnchor.constraint(equalTo: imageView.heightAnchor).activated()
        
        originalLabel.translatesAutoresizingMaskIntoConstraints = false
        originalLabel.text = money.localizedString
        originalLabel.textAlignment = .left
        addSubview(originalLabel)
        originalLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: .padding).activated()
        originalLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: .padding*2).activated()
        
        convertedLabel.translatesAutoresizingMaskIntoConstraints = false
        if money.currency != "EUR" { convertedLabel.text = money.exchangedAndLocalized(to: "EUR") }
        convertedLabel.textAlignment = .right
        addSubview(convertedLabel)
        convertedLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: .padding).activated()
        convertedLabel.leadingAnchor.constraint(equalTo: originalLabel.trailingAnchor).activated()
        convertedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.padding*2).activated()
        
        officialCurrency.translatesAutoresizingMaskIntoConstraints = false
        officialCurrency.text = NSLocalizedString("officialLabel", comment: "")
        officialCurrency.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        addSubview(officialCurrency)
        officialCurrency.topAnchor.constraint(equalTo: originalLabel.bottomAnchor, constant: .padding).activated()
        officialCurrency.leadingAnchor.constraint(equalTo: leadingAnchor, constant: .padding*2).activated()
        officialCurrency.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.padding*2).activated()
        
        officialLabel.translatesAutoresizingMaskIntoConstraints = false
        officialLabel.text = NSLocalizedString("\(money.currency)Official", comment: "")
        officialLabel.numberOfLines = 0
        addSubview(officialLabel)
        officialLabel.topAnchor.constraint(equalTo: officialCurrency.bottomAnchor).activated()
        officialLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: .padding*2).activated()
        officialLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.padding*2).activated()
        
        acceptedIn.translatesAutoresizingMaskIntoConstraints = false
        acceptedIn.text = NSLocalizedString("acceptedLabel", comment: "")
        acceptedIn.font = UIFont.boldSystemFont(ofSize: UIFont.labelFontSize)
        addSubview(acceptedIn)
        acceptedIn.topAnchor.constraint(equalTo: officialLabel.bottomAnchor, constant: .padding).activated()
        acceptedIn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: .padding*2).activated()
        acceptedIn.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.padding*2).activated()
        
        acceptedLabel.translatesAutoresizingMaskIntoConstraints = false
        acceptedLabel.text = NSLocalizedString("\(money.currency)Accepted", comment: "")
        acceptedLabel.numberOfLines = 0
        addSubview(acceptedLabel)
        acceptedLabel.topAnchor.constraint(equalTo: acceptedIn.bottomAnchor).activated()
        acceptedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: .padding*2).activated()
        acceptedLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -.padding*2).activated()
        acceptedLabel.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -.padding - .cornerWidth).activated()
        
        
//        heightAnchor.constraint(equalToConstant: 200).activated()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    @objc private func closePressed() {
        animateOut(animations: closeAnimations, completion: closeAction)
    }
    
    //MARK: Animations
    
    func animateIn(with view: UIView?, animations: (() -> Void)? = nil) {
        guard let view = view else { return }
        view.addSubview(self)
        becomeFirstResponder()
        
        leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: .padding).activated()
        trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -.padding).activated()
        bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: .cornerWidth).activated(.defaultHigh)
        bottomConstraint = topAnchor.constraint(equalTo: view.bottomAnchor).activated()
        
        DispatchQueue.main.async {
            self.bottomConstraint?.isActive = false
            UIView.animate(withDuration: 0.3, animations: {
                view.layoutIfNeeded()
                animations?()
            })
        }
    }
    
    func animateOut(animations: (() -> Void)? = nil, completion: (() -> Void)? = nil) {
        guard let view = superview else { removeFromSuperview(); return }
        bottomConstraint?.isActive = true
        UIView.animate(withDuration: 0.3, animations: {
            view.layoutIfNeeded()
            animations?()
        }, completion: { _ in
            self.removeFromSuperview()
            self.resignFirstResponder()
            completion?()
        })
    }
    
    //MARK: Shake Gesture

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        shakeAction?()
    }

}
