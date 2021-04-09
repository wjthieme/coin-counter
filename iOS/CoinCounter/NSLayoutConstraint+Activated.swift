//
//  Constraint+Activate.swift
//  CoreML
//
//  Created by Wilhelm Thieme on 20/12/2018.
//  Copyright © 2019 Ministerie van Economische Zaken. All rights reserved.
//

import UIKit

extension NSLayoutConstraint {
    @discardableResult func activated(_ prio: UILayoutPriority = .required) -> NSLayoutConstraint {
        self.priority = prio
        self.isActive = true
        return self
    }

}
