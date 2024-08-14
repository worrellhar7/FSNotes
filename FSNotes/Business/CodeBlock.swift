//
//  CodeBlock.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 8/28/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import AppKit

class CodeBlock: NSTextBlock {
    override func drawBackground(withFrame frameRect: NSRect, in controlView: NSView, characterRange charRange: NSRange, layoutManager: NSLayoutManager) {
        let selectionPath = NSBezierPath.init(roundedRect: frameRect, xRadius: 5, yRadius: 5)

        NotesTextProcessor.codeBackground.setFill()
        selectionPath.fill()
    }

    override func rectForLayout(at startingPoint: NSPoint, in rect: NSRect, textContainer: NSTextContainer, characterRange charRange: NSRange) -> NSRect {
        var res = super.rectForLayout(at: startingPoint, in: rect, textContainer: textContainer, characterRange: charRange)
        res.size.width = rect.size.width
        return res
    }
}
