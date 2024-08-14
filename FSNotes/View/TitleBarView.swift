//
//  TitleBarView.swift
//  FSNotes
//
//  Created by BUDDAx2 on 10/27/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa

class TitleBarView: NSView {
    
    var onMouseEnteredClosure: (()->())?
    var onMouseExitedClosure: (()->())?
    
    override func awakeFromNib() {
        
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil))
    }
    
    override func layout() {
        super.layout()
        
        self.trackingAreas.forEach { [weak self] area in
            self?.removeTrackingArea(area)
        }
        
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil))
    }
    
    override func mouseEntered(with event: NSEvent) {
        onMouseEnteredClosure?()
    }
    
    override func mouseExited(with event: NSEvent) {
        onMouseExitedClosure?()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            self.window?.windowController?.maximizeWindow()
        }
    }
    
}
