//
//  TextFormatter.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 3/6/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

#if os(OSX)
    import Cocoa
    import Carbon.HIToolbox
    typealias Font = NSFont
    typealias TextView = EditTextView
    typealias Color = NSColor
#else
    import UIKit
    typealias Font = UIFont
    typealias TextView = EditTextView
    typealias Color = UIColor
#endif

public class TextFormatter {
    private var attributedString: NSMutableAttributedString
    private var attributedSelected: NSAttributedString
    private var type: NoteType
    private var textView: TextView
    private var note: Note
    private var storage: NSTextStorage
    private var selectedRange: NSRange
    private var range: NSRange
    private var newSelectedRange: NSRange?
    private var cursor: Int?
    
    private var prevSelectedString: NSAttributedString
    private var prevSelectedRange: NSRange
    
    private var isAutomaticQuoteSubstitutionEnabled: Bool = false
    private var isAutomaticDashSubstitutionEnabled: Bool = false
    
    init(textView: TextView, note: Note) {
        range = textView.selectedRange
        
        #if os(OSX)
            storage = textView.textStorage!
            attributedSelected = textView.attributedString()
            if textView.typingAttributes[.font] == nil {
                textView.typingAttributes[.font] = UserDefaultsManagement.noteFont
            }
        #else
            storage = textView.textStorage
            attributedSelected = textView.attributedText
        #endif
        
        self.attributedString = NSMutableAttributedString(attributedString: attributedSelected.attributedSubstring(from: range))
        self.selectedRange = NSRange(0..<attributedString.length)
        
        self.type = note.type
        self.textView = textView
        self.note = note
        
        prevSelectedRange = range
        prevSelectedString = storage.attributedSubstring(from: prevSelectedRange)
        
        #if os(OSX)
            self.isAutomaticQuoteSubstitutionEnabled = textView.isAutomaticQuoteSubstitutionEnabled
            self.isAutomaticDashSubstitutionEnabled = textView.isAutomaticDashSubstitutionEnabled
        
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
        #endif
    }
    
    func getString() -> NSMutableAttributedString {
        return attributedString
    }
    
    func bold() {
        if note.isMarkdown() {

            // UnBold if not selected
            if range.length == 0 {
                var resultFound = false
                let string = getAttributedString().string

                NotesTextProcessor.boldRegex.matches(string, range: NSRange(0..<string.count)) { (result) -> Void in
                    guard let range = result?.range else { return }

                    if range.intersection(self.range) != nil {
                        let boldAttributed = self.getAttributedString().attributedSubstring(from: range)

                        self.unBold(attributedString: boldAttributed, range: range)
                        resultFound = true
                    }
                }

                if resultFound {
                    return
                }
            }

            // UnBold selected
            if attributedString.string.contains("**") || attributedString.string.contains("__") {
                unBold(attributedString: attributedString, range: range)
                return
            }

            var selectRange = NSMakeRange(range.location + 2, 0)
            let string = attributedString.string
            let length = string.count

            if length != 0 {
                selectRange = NSMakeRange(range.location, length + 4)
            }

            insertText("**" + string + "**", selectRange: selectRange)
        }
        
        if type == .RichText {
            let newFont = toggleBoldFont(font: getTypingAttributes())
            
            #if os(iOS)
            guard self.attributedString.length > 0 else {
                self.setTypingAttributes(font: newFont)
                return
            }
            #endif
            
            textView.undoManager?.beginUndoGrouping()

            #if os(OSX)
                let string = NSMutableAttributedString(attributedString: attributedString)
                string.addAttribute(.font, value: newFont, range: selectedRange)
                self.insertText(string, replacementRange: range, selectRange: range)
                setTypingAttributes(font: newFont)
            #else
                let selectedRange = textView.selectedRange
                let selectedTextRange = textView.selectedTextRange!
                let selectedText = textView.textStorage.attributedSubstring(from: selectedRange)
            
                let mutableAttributedString = NSMutableAttributedString(attributedString: selectedText)
                mutableAttributedString.toggleBoldFont()
            
                textView.replace(selectedTextRange, withText: selectedText.string)
                textView.textStorage.replaceCharacters(in: selectedRange, with: mutableAttributedString)
                textView.selectedRange = selectedRange
            #endif

            textView.undoManager?.endUndoGrouping()
        }
    }
    
    func italic() {
        if note.isMarkdown() {

            // UnItalic if not selected
            if range.length == 0 {
                var resultFound = false
                let string = getAttributedString().string

                NotesTextProcessor.italicRegex.matches(string, range: NSRange(0..<string.count)) { (result) -> Void in
                    guard let range = result?.range else { return }

                    if range.intersection(self.range) != nil {
                        let italicAttributed = self.getAttributedString().attributedSubstring(from: range)

                        self.unItalic(attributedString: italicAttributed, range: range)
                        resultFound = true
                    }
                }

                if resultFound {
                    return
                }
            }

            // UnItalic
            if attributedString.string.contains("*") || attributedString.string.contains("_") {
                unItalic(attributedString: attributedString, range: range)
                return
            }

            var selectRange = NSMakeRange(range.location + 1, 0)
            let string = attributedString.string
            let length = string.count

            if length != 0 {
                selectRange = NSMakeRange(range.location, length + 2)
            }

            insertText("_" + string + "_", selectRange: selectRange)
        }
        
        if type == .RichText {
            let newFont = toggleItalicFont(font: getTypingAttributes())
            
            #if os(iOS)
            guard attributedString.length > 0 else {
                setTypingAttributes(font: newFont)
                return
            }
            #endif
            
            textView.undoManager?.beginUndoGrouping()
            #if os(OSX)
                let string = NSMutableAttributedString(attributedString: attributedString)
                string.addAttribute(.font, value: newFont, range: selectedRange)
                self.insertText(string, replacementRange: range, selectRange: range)
                setTypingAttributes(font: newFont)
            #else
                let selectedRange = textView.selectedRange
                let selectedTextRange = textView.selectedTextRange!
                let selectedText = textView.textStorage.attributedSubstring(from: selectedRange)
            
                let mutableAttributedString = NSMutableAttributedString(attributedString: selectedText)
                mutableAttributedString.toggleItalicFont()
            
                textView.replace(selectedTextRange, withText: selectedText.string)
                textView.textStorage.replaceCharacters(in: selectedRange, with: mutableAttributedString)
                textView.selectedRange = selectedRange
            #endif
            textView.undoManager?.endUndoGrouping()
        }
    }

    private func unBold(attributedString: NSAttributedString, range: NSRange) {
        let unBold = attributedString
            .string
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")

        let selectRange = NSRange(location: range.location, length: unBold.count)
        insertText(unBold, replacementRange: range, selectRange: selectRange)
    }

    private func unItalic(attributedString: NSAttributedString, range: NSRange) {
        let unItalic = attributedString
            .string
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")

        let selectRange = NSRange(location: range.location, length: unItalic.count)
        insertText(unItalic, replacementRange: range, selectRange: selectRange)
    }

    private func unStrike(attributedString: NSAttributedString, range: NSRange) {
        let unStrike = attributedString
            .string
            .replacingOccurrences(of: "~~", with: "")

        let selectRange = NSRange(location: range.location, length: unStrike.count)
        insertText(unStrike, replacementRange: range, selectRange: selectRange)
    }
    
    public func underline() {
        if note.type == .RichText {
            if (attributedString.length > 0) {
                #if os(iOS)
                    let selectedtTextRange = textView.selectedTextRange!
                #endif

                let selectedRange = textView.selectedRange
                let range = NSRange(0..<attributedString.length)

                if let underline = attributedString.attribute(.underlineStyle, at: 0, effectiveRange: nil) as? Int {
                    if underline == 1 {
                        attributedString.removeAttribute(.underlineStyle, range: range)
                    } else {
                        attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                        attributedString.addAttribute(.underlineColor, value: Colors.underlineColor, range: range)
                    }
                } else {
                    attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    attributedString.addAttribute(.underlineColor, value: Colors.underlineColor, range: range)
                }

                #if os(iOS)
                    self.textView.replace(selectedtTextRange, withText: attributedString.string)
                    self.textView.selectedRange = selectedRange
                #endif

                self.textView.undoManager?.beginUndoGrouping()
                self.storage.replaceCharacters(in: selectedRange, with: attributedString)
                self.textView.undoManager?.endUndoGrouping()

                self.textView.selectedRange = selectedRange
                return
            }
            
            #if os(OSX)
                if (textView.typingAttributes[.underlineStyle] == nil) {
                    attributedString.addAttribute(NSAttributedString.Key.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: selectedRange)


                    attributedString.addAttribute(.underlineColor, value: Colors.underlineColor, range: selectedRange)

                    
                    textView.typingAttributes[.underlineStyle] = 1
                } else {
                    textView.typingAttributes.removeValue(forKey: NSAttributedString.Key(rawValue: "NSUnderline"))
                }

                textView.insertText(attributedString, replacementRange: textView.selectedRange)
            #else
            if (textView.typingAttributes[.underlineStyle] == nil) {
                textView.typingAttributes[.underlineStyle] = 1
                } else {
                    textView.typingAttributes.removeValue(forKey: .underlineStyle)
                }
            #endif
        }
    }
    
    public func strike() {
        if note.type == .RichText {
            if (attributedString.length > 0) {
                #if os(iOS)
                    let selectedtTextRange = textView.selectedTextRange!
                #endif

                let selectedRange = textView.selectedRange
                let range = NSRange(0..<attributedString.length)

                if let underline = attributedString.attribute(.strikethroughStyle, at: 0, effectiveRange: nil) as? Int {
                    if underline == 2 {
                        attributedString.removeAttribute(.strikethroughStyle, range: range)
                    } else {
                        attributedString.addAttribute(.strikethroughStyle, value: 2, range: range)
                    }
                } else {
                    attributedString.addAttribute(.strikethroughStyle, value: 2, range: range)
                }

                #if os(iOS)
                    self.textView.replace(selectedtTextRange, withText: attributedString.string)
                #endif

                self.textView.undoManager?.beginUndoGrouping()
                self.storage.replaceCharacters(in: selectedRange, with: attributedString)
                self.textView.undoManager?.endUndoGrouping()

                self.textView.selectedRange = selectedRange
                return
            }
            
            #if os(OSX)
                if (textView.typingAttributes[.strikethroughStyle] == nil) {
                    attributedString.addAttribute(NSAttributedString.Key.strikethroughStyle, value: 2, range: selectedRange)
                    textView.typingAttributes[.strikethroughStyle] = 2
                } else {
                    textView.typingAttributes.removeValue(forKey: NSAttributedString.Key(rawValue: "NSStrikethrough"))
                }
            
                textView.insertText(attributedString, replacementRange: textView.selectedRange)
            #else
                if (textView.typingAttributes[.strikethroughStyle] == nil) {
                    textView.typingAttributes[.strikethroughStyle] = 2
                } else {
                    textView.typingAttributes.removeValue(forKey: .strikethroughStyle)
                }
            #endif
        }
        
        if note.isMarkdown() {

            // UnStrike if not selected
            if range.length == 0 {
                var resultFound = false
                let string = getAttributedString().string

                NotesTextProcessor.strikeRegex.matches(string, range: NSRange(0..<string.count)) { (result) -> Void in
                    guard let range = result?.range else { return }

                    if range.intersection(self.range) != nil {
                        let italicAttributed = self.getAttributedString().attributedSubstring(from: range)

                        self.unStrike(attributedString: italicAttributed, range: range)
                        resultFound = true
                    }
                }

                if resultFound {
                    return
                }
            }

            // UnStrike
            if attributedString.string.contains("~~") {
                unStrike(attributedString: attributedString, range: range)
                return
            }

            var selectRange = NSMakeRange(range.location + 2, 0)
            let string = attributedString.string
            let length = string.count

            if length != 0 {
                selectRange = NSMakeRange(range.location, length + 4)
            }

            insertText("~~" + string + "~~", selectRange: selectRange)
        }
    }
    
    public func tab() {
        guard let pRange = getParagraphRange() else { return }
        
        var padding = "\t"
        
        if UserDefaultsManagement.indentUsing == 0x01 {
            padding = "  "
        }

        if UserDefaultsManagement.indentUsing == 0x02 {
            padding = "    "
        }
        
        let mutable = NSMutableAttributedString(attributedString: getAttributedString().attributedSubstring(from: pRange)).unLoadCheckboxes()

        let string = mutable.string
        var result = String()
        var addsChars = 0

        let location = textView.selectedRange.location
        let length = textView.selectedRange.length

        var isFirstLine = true
        string.enumerateLines { (line, _) in
            result.append(padding + line + "\n")

            if isFirstLine {
                isFirstLine = false
            } else {
                addsChars += padding.count
            }
        }

        let selectRange = NSRange(location: location + padding.count, length: length + addsChars)
        
        let mutableResult = NSMutableAttributedString(string: result)
        mutableResult.loadCheckboxes()

        #if os(OSX)
            textView.textStorage?.removeAttribute(.todo, range: pRange)
        #else
            textView.textStorage.removeAttribute(.todo, range: pRange)

            // Fixes font size issue #1271
            let parFont = NotesTextProcessor.font
            let parRange = NSRange(location: 0, length:   mutableResult.length)
            mutableResult.addAttribute(.font, value: parFont, range: parRange)
        #endif

        insertText(mutableResult, replacementRange: pRange, selectRange: selectRange)
    }
    
    public func unTab() {
        guard let pRange = getParagraphRange() else { return }

        let mutable = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: pRange)).unLoadCheckboxes()
        let string = mutable.string

        var result = String()

        let location = textView.selectedRange.location
        let length = textView.selectedRange.length

        var padding = 0
        var dropChars = 0

        if string.starts(with: "\t") {
            padding = 1
        } else if string.starts(with: "  ") && UserDefaultsManagement.indentUsing == 0x01 {
            padding = 2
        } else if string.starts(with: "    ") {
            padding = 4
        }

        if padding == 0 {
            return
        }

        var isFirstLine = true
        
        string.enumerateLines { (line, _) in
            var line = line

            if !line.isEmpty {
                var firstCharsToDrop: Int?
                
                if line.first == "\t" {
                    firstCharsToDrop = 1
                } else if UserDefaultsManagement.indentUsing == 0x01 && line.starts(with: "  ") {
                    firstCharsToDrop = 2
                } else if line.starts(with: "    ") {
                    firstCharsToDrop = 4
                }
                
                if let x = firstCharsToDrop {
                    line = String(line.dropFirst(x))
                    
                    if length == 0 {
                        dropChars = 0
                    } else {
                        if isFirstLine {
                            isFirstLine = false
                        } else {
                            dropChars += x
                        }
                    }
                }
            }
            
            result.append(line + "\n")
        }

        let diffLocation = location - padding
        
        var selectLength = length - dropChars
        var selectLocation = diffLocation > 0 ? diffLocation : 0

        if selectLocation < pRange.location {
            selectLocation = pRange.location
        }

        if selectLength > result.count {
            selectLength = result.count
        }

        let selectRange = NSRange(location: selectLocation, length: selectLength)
        let mutableResult = NSMutableAttributedString(string: result)
        mutableResult.loadCheckboxes()

        #if os(OSX)
            textView.textStorage?.removeAttribute(.todo, range: pRange)
        #else
            textView.textStorage.removeAttribute(.todo, range: pRange)

            // Fixes font size issue #1271
            let parFont = NotesTextProcessor.font
            let parRange = NSRange(location: 0, length:   mutableResult.length)
            mutableResult.addAttribute(.font, value: parFont, range: parRange)
        #endif

        insertText(mutableResult, replacementRange: pRange, selectRange: selectRange)
    }
    
    public func header(_ string: String) {
        let fullSelection = selectedRange.length > 0
        guard let pRange = getParagraphRange() else { return }

#if os(iOS)
        var prefix = String()
        var paragraph = storage.mutableString.substring(with: pRange)

        if paragraph.starts(with: "######") {
            paragraph = paragraph
                .replacingOccurrences(of: "#", with: "")
                .trim()
        } else if paragraph.starts(with: "#") {
            prefix = string
        } else {
            prefix = string + " "
        }

        let diff = paragraph.contains("\n") ? 1 : 0
        let selectRange = NSRange(location: pRange.location + (prefix + paragraph).count - diff, length: 0)
        insertText(prefix + paragraph, replacementRange: pRange, selectRange: selectRange)
#else
        let prefix = string + " "
        var paragraph = storage.mutableString
            .substring(with: pRange)

        if paragraph.starts(with: prefix) {
            paragraph = paragraph.replacingOccurrences(of: prefix, with: "")
        } else {
            paragraph =
                prefix + paragraph.replacingOccurrences(of: "#", with: "").trim()
        }

        let diff = paragraph.contains("\n") ? 1 : 0

        var selectRange = NSRange(location: pRange.location + paragraph.count - diff, length: 0)

        if fullSelection {
            selectRange = NSRange(location: pRange.location, length: paragraph.count - diff)
        }

        insertText(paragraph, replacementRange: pRange, selectRange: selectRange)
#endif
    }
    
    public func link() {
        let text = "[" + attributedString.string + "]()"
        replaceWith(string: text, range: range)
        
        if (attributedString.length == 4) {
            setSelectedRange(NSMakeRange(range.location + 1, 0))
        } else {
            setSelectedRange(NSMakeRange(range.upperBound + 3, 0))
        }
    }

#if os(OSX)
    public func wikiLink() {
        let text = "[[" + attributedString.string + "]]"
        replaceWith(string: text, range: range)

        if (text.count == 4) {
            setSelectedRange(NSMakeRange(range.location + 2, 0))
            textView.complete(nil)
        } else {
            setSelectedRange(NSMakeRange(range.location + 2, text.count - 4))
        }
    }
#endif

    public func image() {
        let text = "![" + attributedString.string + "]()"
        replaceWith(string: text)
        
        if (attributedString.length == 5) {
            setSelectedRange(NSMakeRange(range.location + 2, 0))
        } else {
            setSelectedRange(NSMakeRange(range.upperBound + 4, 0))
        }
    }
    
    public func isListParagraph() -> Bool {
        guard let currentPR = getParagraphRange() else { return false }
        let paragraph = storage.attributedSubstring(from: currentPR).string
        
        if TextFormatter.getAutocompleteCharsMatch(string: paragraph) != nil {
            return true
        }

        if TextFormatter.getAutocompleteDigitsMatch(string: paragraph) != nil {
            return true
        }
        
        return false
    }

    public func tabKey() {
        guard let currentPR = getParagraphRange() else { return }
        let paragraph = storage.attributedSubstring(from: currentPR).string
        let sRange = self.textView.selectedRange
        
        // Middle
        if (sRange.location != 0 || sRange.location != storage.length)
            && paragraph.count == 1
            && self.note.isMarkdown()
        {
            self.insertText("\t", replacementRange: sRange)
            return
        }
        
        // First & Last
        if (sRange.location == 0 || sRange.location == self.storage.length) && paragraph.count == 0 && self.note.isMarkdown() {
        #if os(OSX)
            if textView.textStorage?.length == 0 {
                textView.textStorageProcessor?.shouldForceRescan = true
            }
        #else
            if textView.textStorage.length == 0 {
                textView.textStorageProcessor?.shouldForceRescan = true
            }
        #endif
            
            self.insertText("\t\n", replacementRange: sRange)
            self.setSelectedRange(NSRange(location: sRange.location + 1, length: 0))
            return
        }
        
        self.insertText("\t")
    }

    public static func getAutocompleteCharsMatch(string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern:
            "^(( |\t)*\\- \\[[x| ]*\\] )|^(( |\t)*[-|–|—|*|•|>|\\+]{1} )"), let result = regex.firstMatch(in: string, range: NSRange(0..<string.count)) else { return nil }

        return result
    }

    public static func getAutocompleteDigitsMatch(string: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: "^(( |\t)*[0-9]+\\. )"), let result = regex.firstMatch(in: string, range: NSRange(0..<string.count)) else { return nil }

        return result
    }

    private func matchChars(string: NSAttributedString, match: NSTextCheckingResult, prefix: String? = nil) {
        guard string.length >= match.range.upperBound else { return }

        let found = string.attributedSubstring(from: match.range).string
        var newLine = 1

        if textView.selectedRange.upperBound == storage.length {
            newLine = 0
        }

        if found.count + newLine == string.length {
            let range = storage.mutableString.paragraphRange(for: textView.selectedRange)
            let selectRange = NSRange(location: range.location, length: 0)
            insertText("\n", replacementRange: range, selectRange: selectRange)
        } else {
            insertText("\n" + found)
        }

        updateCurrentParagraph()
    }

    private func matchDigits(string: NSAttributedString, match: NSTextCheckingResult) {
        guard string.length >= match.range.upperBound else { return }

        let found = string.attributedSubstring(from: match.range).string
        var newLine = 1

        if textView.selectedRange.upperBound == storage.length {
            newLine = 0
        }

        if found.count + newLine == string.length {
            let range = storage.mutableString.paragraphRange(for: textView.selectedRange)
            let selectRange = NSRange(location: range.location, length: 0)
            insertText("\n", replacementRange: range, selectRange: selectRange)
        } else if let position = Int(found.replacingOccurrences(of:"[^0-9]", with: "", options: .regularExpression)) {
            let newDigit = found.replacingOccurrences(of: String(position), with: String(position + 1))
            insertText("\n" + newDigit)
        }

        updateCurrentParagraph()
    }

    private func updateCurrentParagraph() {
        let parRange = getParagraphRange(for: textView.selectedRange.location)

        #if os(iOS)
            textView.textStorage.updateParagraphStyle(range: parRange)
        #else
            textView.textStorage?.updateParagraphStyle(range: parRange)
        #endif
    }

    public func newLine() {
        guard let currentParagraphRange = self.getParagraphRange() else { return }

        let currentParagraph = storage.attributedSubstring(from: currentParagraphRange)
        let selectedRange = self.textView.selectedRange

        // Autocomplete todo lists

        if selectedRange.location != currentParagraphRange.location && currentParagraphRange.upperBound - 2 < selectedRange.location, currentParagraph.length >= 2 {

            if textView.selectedRange.upperBound > 2 {
                let char = storage.attributedSubstring(from: NSRange(location: textView.selectedRange.upperBound - 2, length: 1))

                if let _ = char.attribute(.todo, at: 0, effectiveRange: nil) {
                    let selectRange = NSRange(location: currentParagraphRange.location, length: 0)

                    insertText("", replacementRange: currentParagraphRange, selectRange: selectRange)

                    #if os(OSX)
                        textView.insertNewline(nil)
                        textView.setSelectedRange(selectRange)
                    #else
                        textView.insertText("\n")
                        textView.selectedRange = selectRange
                    #endif

                    return
                }
            }

            var todoLocation = -1
            currentParagraph.enumerateAttribute(.todo, in: NSRange(0..<currentParagraph.length), options: []) { (value, range, stop) -> Void in
                guard value != nil else { return }

                todoLocation = range.location
                stop.pointee = true
            }

            if todoLocation > -1 {
                let unchecked = AttributedBox.getUnChecked()?.attributedSubstring(from: NSRange(0..<2))
                var prefix = String()

                if todoLocation > 0 {
                    prefix = currentParagraph.attributedSubstring(from: NSRange(0..<todoLocation)).string
                }

            #if os(OSX)
                let string = NSMutableAttributedString(string: "\n" + prefix)
                string.append(unchecked!)
                self.insertText(string)
            #else
                let selectedRange = textView.selectedRange
                let selectedTextRange = textView.selectedTextRange!
                let checkbox = NSMutableAttributedString(string: "\n" + prefix)
                checkbox.append(unchecked!)

                textView.undoManager?.beginUndoGrouping()
                textView.replace(selectedTextRange, withText: checkbox.string)
                textView.textStorage.replaceCharacters(in: NSRange(location: selectedRange.location, length: checkbox.length), with: checkbox)
                textView.undoManager?.endUndoGrouping()
            #endif
                return
            }
        }

        // Autocomplete ordered and unordered lists

        if selectedRange.location != currentParagraphRange.location && currentParagraphRange.upperBound - 2 < selectedRange.location {
            if let charsMatch = TextFormatter.getAutocompleteCharsMatch(string: currentParagraph.string) {
                self.matchChars(string: currentParagraph, match: charsMatch)
                return
            }

            if let digitsMatch = TextFormatter.getAutocompleteDigitsMatch(string: currentParagraph.string) {
                self.matchDigits(string: currentParagraph, match: digitsMatch)
                return
            }
        }

        // New Line insertion

        var newLine = "\n"
        
        var prefix: String?
        
        if UserDefaultsManagement.indentUsing == 0x00  && currentParagraph.string.starts(with: "\t") {
            prefix = currentParagraph.string.getPrefixMatchSequentially(char: "\t")
        }

        if UserDefaultsManagement.indentUsing == 0x01  && currentParagraph.string.starts(with: "  ") {
            prefix = currentParagraph.string.getPrefixMatchSequentially(char: " ")
        }

        if UserDefaultsManagement.indentUsing == 0x02  && currentParagraph.string.starts(with: "    ") {
            prefix = currentParagraph.string.getPrefixMatchSequentially(char: " ")
        }

        if let x = prefix {
            if selectedRange.location != currentParagraphRange.location {
                newLine += x
            }

            let string = TextFormatter.getAttributedCode(string: newLine)
            self.insertText(string)
            return
        }

        #if os(iOS)
            self.textView.insertText("\n")
        #else
            self.textView.insertNewline(nil)
        #endif
    }

    public func todo() {
        guard let pRange = getParagraphRange() else { return }

        let attributedString = getAttributedString().attributedSubstring(from: pRange)
        let mutable = NSMutableAttributedString(attributedString: attributedString).unLoadCheckboxes()

        if !attributedString.hasTodoAttribute() && selectedRange.length == 0 {
            var offset = 0
            let symbols = ["\t", " "]
            for char in mutable.string {
                if symbols.contains(String(char)) {
                    offset += 1
                } else {
                    break
                }
            }

            let insertRange = NSRange(location: pRange.location + offset, length: 0)
            let selectRange = NSRange(location: range.location + 2, length: range.length)
            insertText(AttributedBox.getUnChecked()!, replacementRange: insertRange, selectRange: selectRange)
            storage.updateParagraphStyle(range: getParagraphRange())
            return
        }

        var lines = [String]()
        var addPrefixes = false
        var addCompleted = false
        let string = mutable.string

        string.enumerateLines { (line, _) in
            let result = self.parseTodo(line: line)
            addPrefixes = !result.0
            addCompleted = result.1
            lines.append(result.2)
        }

        var result = String()
        for line in lines {

            // Removes extra chars identified as list items start
            var line = line

            let digitRegex = try! NSRegularExpression(pattern: "^([0-9]+\\. )")
            let digitRegexResult = digitRegex.firstMatch(in: line, range: NSRange(0..<line.count))

            let charRegex = try! NSRegularExpression(pattern: "^([-*–+]+ )")
            let charRegexResult = charRegex.firstMatch(in: line, range: NSRange(0..<line.count))

            if let result = digitRegexResult {
                let qty = result.range.length
                line = String(line.dropFirst(qty))
            } else if let result = charRegexResult, !line.contains("- [") {
                let qty = result.range.length
                line = String(line.dropFirst(qty))
            }

            if addPrefixes {
                let task = addCompleted ? "- [x] " : "- [ ] "
                var empty = String()
                var scanFinished = false

                if line.count > 0 {
                    var j = 0
                    for char in line {
                        j += 1

                        if (char.isWhitespace || char == "\t")
                            && !scanFinished {
                            if j == line.count {
                                empty.append("\(char)" + task)
                            } else {
                                empty.append(char)
                            }
                        } else {
                            if !scanFinished {
                                empty.append(task + "\(char)")
                                scanFinished = true
                            } else {
                                empty.append(char)
                            }
                        }
                    }

                    result += empty + "\n"
                } else {
                    result += task + "\n"
                }
            } else {
                result += line + "\n"
            }
        }

        let mutableResult = NSMutableAttributedString(string: result)
        
        #if os(iOS)
            let textColor: UIColor = UIColor.blackWhite
        #else
            let textColor: NSColor = NotesTextProcessor.fontColor
        #endif
        
        mutableResult.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: mutableResult.length))
        mutableResult.addAttribute(.font, value: NotesTextProcessor.font, range: NSRange(location: 0, length: mutableResult.length))
        mutableResult.loadCheckboxes()

        let diff = mutableResult.length - attributedString.length
        let selectRange = selectedRange.length == 0 || lines.count == 1
            ? NSRange(location: pRange.location + pRange.length + diff - 1, length: 0)
            : NSRange(location: pRange.location, length: mutableResult.length)
        
        // Fixes clicked area
        storage.removeAttribute(.todo, range: pRange)

        insertText(mutableResult, replacementRange: pRange, selectRange: selectRange)
        storage.updateParagraphStyle(range: getParagraphRange())
    }

    public func toggleTodo(_ location: Int? = nil) {
        if let location = location, let todoAttr = storage.attribute(.todo, at: location, effectiveRange: nil) as? Int {
            let attributedText = (todoAttr == 0) ? AttributedBox.getChecked() : AttributedBox.getUnChecked()

            self.textView.undoManager?.beginUndoGrouping()
            self.storage.replaceCharacters(in: NSRange(location: location, length: 1), with: (attributedText?.attributedSubstring(from: NSRange(0..<1)))!)

            self.textView.undoManager?.endUndoGrouping()

            guard let paragraph = getParagraphRange(for: location) else { return }
            
            if todoAttr == 0 {
                self.storage.addAttribute(.strikethroughStyle, value: 1, range: paragraph)
            } else {
                self.storage.removeAttribute(.strikethroughStyle, range: paragraph)
            }
            
            if paragraph.contains(location) {
                textView.typingAttributes[.strikethroughStyle] = (todoAttr == 0) ? 1 : 0
            }

            storage.updateParagraphStyle(range: paragraph)
            
            return
        }

        guard var paragraphRange = getParagraphRange() else { return }

        if let location = location {
            let string = self.storage.string as NSString
            paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
        } else {
            guard let attributedText = AttributedBox.getUnChecked() else { return }

            // Toggle render if exist in current paragraph
            var rangeFound = false
            let attributedParagraph = self.storage.attributedSubstring(from: paragraphRange)
            attributedParagraph.enumerateAttribute(.todo, in: NSRange(0..<attributedParagraph.length), options: []) { value, range, stop in

                if let value = value as? Int {
                    let attributedText = (value == 0) ? AttributedBox.getCleanChecked() : AttributedBox.getCleanUnchecked()
                    let existsRange = NSRange(location: paragraphRange.lowerBound + range.location, length: 1)

                    self.textView.undoManager?.beginUndoGrouping()
                    self.storage.replaceCharacters(in: existsRange, with: attributedText)
                    self.textView.undoManager?.endUndoGrouping()

                    stop.pointee = true
                    rangeFound = true
                }
            }

            guard !rangeFound else { return }

#if os(iOS)
            if let selTextRange = self.textView.selectedTextRange {
                let newRange = NSRange(location: self.textView.selectedRange.location, length: attributedText.length)
                self.textView.undoManager?.beginUndoGrouping()
                self.textView.replace(selTextRange, withText: attributedText.string)
                self.storage.replaceCharacters(in: newRange, with: attributedText)
                self.textView.undoManager?.endUndoGrouping()
            }
#else
            self.insertText(attributedText)
#endif
            return
        }
        
        let paragraph = self.storage.attributedSubstring(from: paragraphRange)
        
        if let index = paragraph.string.range(of: "- [ ]") {
            let local = paragraph.string.nsRange(from: index).location
            let range = NSMakeRange(paragraphRange.location + local, 5)
            if let attributedText = AttributedBox.getChecked() {
                self.insertText(attributedText, replacementRange: range)
            }
            
            return

        } else if let index = paragraph.string.range(of: "- [x]") {
            let local = paragraph.string.nsRange(from: index).location
            let range = NSMakeRange(paragraphRange.location + local, 5)
            if let attributedText = AttributedBox.getUnChecked() {
                self.insertText(attributedText, replacementRange: range)
            }
            
            return
        }
    }

    public func backTick() {
        let selectedRange = textView.selectedRange

        if selectedRange.length > 0 {
            let text = storage.attributedSubstring(from: selectedRange).string
            let string = "`\(text)`"
            let codeFont = UserDefaultsManagement.codeFont

            let mutableString = NSMutableAttributedString(string: string)
            mutableString.addAttribute(.font, value: codeFont, range: NSRange(0..<string.count))

            textView.textStorageProcessor?.shouldForceRescan = true
            insertText(mutableString, replacementRange: selectedRange)
            return
        }

        insertText("``")
        setSelectedRange(NSRange(location: selectedRange.location, length: selectedRange.length + 1))
    }

    public func codeBlock() {
        textView.textStorageProcessor?.shouldForceRescan = true

        let currentRange = textView.selectedRange
        if currentRange.length > 0 {
            let substring = storage.attributedSubstring(from: currentRange)
            let mutable = NSMutableAttributedString(string: "```\n")
            mutable.append(substring)

            if substring.string.last != "\n" {
                mutable.append(NSAttributedString(string: "\n"))
            }
            
            mutable.append(NSAttributedString(string: "```\n"))

            insertText(mutable.string, replacementRange: currentRange)
            setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
            return
        }

        insertText("```\n\n```\n")
        setSelectedRange(NSRange(location: currentRange.location + 4, length: 0))
    }

    public func quote() {
        textView.textStorageProcessor?.shouldForceRescan = true

        guard let pRange = getParagraphRange() else { return }
        let paragraph = storage.mutableString.substring(with: pRange)

        guard paragraph.isContainsLetters else {
            insertText("> ")
            return
        }

        var hasPrefix = false
        var lines = [String]()

        paragraph.enumerateLines { (line, _) in
            hasPrefix = line.starts(with: "> ")

            var skipNext = false
            var scanFinished = false
            var cleanLine = String()

            for char in line {
                if skipNext {
                    skipNext = false
                    continue
                }

                if char == ">" && !scanFinished {
                    skipNext = true
                    scanFinished = true
                } else {
                    cleanLine.append(char)
                }
            }

            lines.append(cleanLine)
        }

        var result = String()
        for line in lines {
            if hasPrefix {
                result += line + "\n"
            } else {
                result += "> " + line + "\n"
            }
        }

        let selectRange = selectedRange.length == 0 || lines.count == 1
            ? NSRange(location: pRange.location + result.count - 1, length: 0)
            : NSRange(location: pRange.location, length: result.count)

        insertText(result, replacementRange: pRange, selectRange: selectRange)
    }
    
    private func getAttributedTodoString(_ string: String) -> NSAttributedString {
        let string = NSMutableAttributedString(string: string)
        string.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: NSRange(0..<1))

        var color = Color.black
        #if os(OSX)
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            color = NSColor(named: "mainText")!
        }
        #endif

        string.addAttribute(.foregroundColor, value: color, range: NSRange(1..<string.length))
        return string
    }
    
    private func replaceWith(string: String, range: NSRange? = nil) {
        #if os(iOS)
            var selectedRange: UITextRange
        
            if let range = range,
                let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                let end = textView.position(from: start, offset: range.length),
                let sRange = textView.textRange(from: start, to: end) {
                selectedRange = sRange
            } else {
                selectedRange = textView.selectedTextRange!
            }
        
            textView.undoManager?.beginUndoGrouping()
            textView.replace(selectedRange, withText: string)
            textView.undoManager?.endUndoGrouping()
        #else
            var r = textView.selectedRange
            if let range = range {
                r = range
            }
        
            textView.insertText(string, replacementRange: r)
        #endif
    }
    
    deinit {
        #if os(OSX)
            textView.isAutomaticQuoteSubstitutionEnabled = self.isAutomaticQuoteSubstitutionEnabled
            textView.isAutomaticDashSubstitutionEnabled = self.isAutomaticDashSubstitutionEnabled
        #endif
        
        if note.isMarkdown() {
            setTypingAttributes(font: UserDefaultsManagement.noteFont)
        }

        if note.isMarkdown() || note.type == .RichText {
            var text: NSAttributedString?
            
            #if os(OSX)
                text = textView.attributedString()
            #else
                text = textView.attributedText
            #endif
            
            if let attributed = text {
                note.save(attributed: attributed)
            }
        }
        
        #if os(iOS)
            textView.initUndoRedoButons()
        #endif
    }
    
    func getParagraphRange() -> NSRange? {
        if range.upperBound <= storage.length {
            let paragraph = storage.mutableString.paragraphRange(for: range)
            return paragraph
        }
        
        return nil
    }
    
    private func getParagraphRange(for location: Int) -> NSRange? {
        guard location <= storage.length else { return nil}

        let range = NSRange(location: location, length: 0)
        let paragraphRange = storage.mutableString.paragraphRange(for: range)
        
        return paragraphRange
    }
    
    func toggleBoldFont(font: Font) -> Font {
        if (font.isBold) {
            return font.unBold()
        } else {
            return font.bold()
        }
    }
    
    func toggleItalicFont(font: Font) -> Font {
        if (font.isItalic) {
            return font.unItalic()
        } else {
            return font.italic()
        }
    }
    
    func getTypingAttributes() -> Font {
        #if os(OSX)
            return textView.typingAttributes[.font] as! Font
        #else
            if let typingFont = textView.typingFont {
                textView.typingFont = nil
                return typingFont
            }

            guard textView.textStorage.length > 0, textView.selectedRange.location > 0 else { return UserDefaultsManagement.noteFont }

            let i = textView.selectedRange.location - 1
            let upper = textView.selectedRange.upperBound
            let substring = textView.attributedText.attributedSubstring(from: NSRange(i..<upper))

            if let prevFont = substring.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                return prevFont
            }

            return UserDefaultsManagement.noteFont
        #endif
    }

    #if os(OSX)
    private func getDefaultColor() -> NSColor {
        var color = Color.black
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            color = NSColor(named: "mainText")!
        }
        return color
    }
    #endif
    
    func setTypingAttributes(font: Font) {
        #if os(OSX)
            textView.typingAttributes[.font] = font
        #else
            textView.typingFont = font
            textView.typingAttributes[.font] = font
        #endif
    }
        
    public func setSelectedRange(_ range: NSRange) {
        #if os(OSX)
            if range.upperBound <= storage.length {
                textView.setSelectedRange(range)
            }
        #else
            textView.selectedRange = range
        #endif
    }
    
    func getAttributedString() -> NSAttributedString {
        #if os(OSX)
            return textView.attributedString()
        #else
            return textView.attributedText
        #endif
    }
    
    private func insertText(_ string: Any, replacementRange: NSRange? = nil, selectRange: NSRange? = nil) {
        let range = replacementRange ?? self.textView.selectedRange
        
    #if os(iOS)
        guard
            let start = textView.position(from: self.textView.beginningOfDocument, offset: range.location),
            let end = textView.position(from: start, offset: range.length),
            let selectedRange = textView.textRange(from: start, to: end)
        else { return }
    
        var replaceString = String()
        if let attributedString = string as? NSAttributedString {
            replaceString = attributedString.string
        }

        if let plainString = string as? String {
            replaceString = plainString
        }

        self.textView.undoManager?.beginUndoGrouping()
        self.textView.replace(selectedRange, withText: replaceString)

        if let string = string as? NSAttributedString {
            let editedRange = NSRange(location: range.location, length: replaceString.count)
            storage.replaceCharacters(in: editedRange, with: string)

            #if os(OSX)
                storage.textStorage(storage, didProcessEditing: .editedCharacters, range: editedRange, changeInLength: 1)
            #else
                storage.delegate?.textStorage!(storage, didProcessEditing: NSTextStorage.EditActions.editedCharacters, range: editedRange, changeInLength: 1)
            #endif
        }

        let parRange = NSRange(location: range.location, length: replaceString.count)
        let parStyle = NSMutableParagraphStyle()
        parStyle.alignment = .left
        parStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        self.textView.textStorage.addAttribute(.paragraphStyle, value: parStyle, range: parRange)

        self.textView.undoManager?.endUndoGrouping()
    #else
        textView.insertText(string, replacementRange: range)
    #endif
        
        if let select = selectRange {
            setSelectedRange(select)
        }
    }

    public static func getAttributedCode(string: String) -> NSMutableAttributedString {
        let attributedString = NSMutableAttributedString(string: string)
        let range = NSRange(0..<attributedString.length)

        attributedString.addAttribute(.font, value: NotesTextProcessor.codeFont as Any, range: range)
        return attributedString
    }

    public func list() {
        guard let pRange = getParagraphRange() else { return }

        let attributedString = getAttributedString().attributedSubstring(from: pRange)
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let string = mutable.unLoadCheckboxes().string

        guard string.isContainsLetters else {
            insertText("- ")
            return
        }

        var lines = [String]()
        var addPrefixes = false

        string.enumerateLines { (line, _) in
            addPrefixes = !self.hasPrefix(line: line, numbers: false)
            let cleanLine = self.cleanListItem(line: line)
            lines.append(cleanLine)
        }

        var result = String()
        for line in lines {
            if addPrefixes {
                var empty = String()
                var scanFinished = false

                for char in line {
                    if char.isWhitespace && !scanFinished {
                        empty.append(char)
                    } else {
                        if !scanFinished {
                            empty.append("- \(char)")
                            scanFinished = true
                        } else {
                            empty.append(char)
                        }
                    }
                }

                result += empty + "\n"
            } else {
                result += line + "\n"
            }
        }

        let selectRange = selectedRange.length == 0 || lines.count == 1
            ? NSRange(location: pRange.location + result.count - 1, length: 0)
            : NSRange(location: pRange.location, length: result.count)
        
        reset(pRange: pRange)
        insertText(result, replacementRange: pRange, selectRange: selectRange)
        
        // Fixes small font bug
        storage.addAttribute(.font, value: NotesTextProcessor.font, range: NSRange(location: pRange.location, length: result.count))
    }

    public func orderedList() {
        guard let pRange = getParagraphRange() else { return }

        let attributedString = getAttributedString().attributedSubstring(from: pRange)
        let mutable = NSMutableAttributedString(attributedString: attributedString)
        let string = mutable.unLoadCheckboxes().string

        guard string.isContainsLetters else {
            insertText("1. ")
            return
        }

        var lines = [String]()
        var addPrefixes = false

        string.enumerateLines { (line, _) in
            addPrefixes = !self.hasPrefix(line: line, numbers: true)
            let cleanLine = self.cleanListItem(line: line)
            lines.append(cleanLine)
        }

        var result = String()
        var i = 1
        var deep = 0

        for line in lines {
            if addPrefixes {
                var empty = String()
                var scanFinished = false
                var lineDeep = 0

                for char in line {
                    if char.isWhitespace && !scanFinished {
                        empty.append(char)
                        lineDeep += 1
                    } else {
                        if !scanFinished {

                            // Resets numeration on deeper lvl
                            if lineDeep != deep {
                                i = 1
                                deep = lineDeep
                            }

                            empty.append("\(i). \(char)")
                            scanFinished = true
                        } else {
                            empty.append(char)
                        }
                    }
                }


                result += empty + "\n"
                i += 1
            } else {
                result += line + "\n"
            }
        }

        let selectRange = selectedRange.length == 0 || lines.count == 1
            ? NSRange(location: pRange.location + result.count - 1, length: 0)
            : NSRange(location: pRange.location, length: result.count)

        reset(pRange: pRange)
        insertText(result, replacementRange: pRange, selectRange: selectRange)
        
        // Fixes small font bug
        storage.addAttribute(.font, value: NotesTextProcessor.font, range: NSRange(location: pRange.location, length: result.count))
    }
    
    private func reset(pRange: NSRange) {
        storage.removeAttribute(.strikethroughStyle, range: pRange)
        storage.removeAttribute(.todo, range: pRange)
    }

    private func cleanListItem(line: String) -> String {
        var line = line

        let digitRegex = try! NSRegularExpression(pattern: "^([0-9]+\\. )")
        let digitRegexResult = digitRegex.firstMatch(in: line, range: NSRange(0..<line.count))

        let charRegex = try! NSRegularExpression(pattern: "^([-*–+]+ )")
        let charRegexResult = charRegex.firstMatch(in: line, range: NSRange(0..<line.count))

        if line.starts(with: "- [ ] ") || line.starts(with: "- [x] ") {
            line = String(line.dropFirst(6))
        } else if let result = digitRegexResult {
            let qty = result.range.length
            line = String(line.dropFirst(qty))
        } else if let result = charRegexResult, !line.contains("- [") {
            let qty = result.range.length
            line = String(line.dropFirst(qty))
        }

        return line
    }

    private func parseTodo(line: String) -> (Bool, Bool, String) {
        var count = 0
        var hasTodoPrefix = false
        var hasIncompletedTask = false
        var charFound = false
        var whitespacePrefix = String()
        var letterPrefix = String()

        for char in line {
            if char.isWhitespace && !charFound {
                count += 1
                whitespacePrefix.append(char)
                continue
            } else {
                charFound = true
                letterPrefix.append(char)
            }
        }

        if letterPrefix.starts(with: "- [ ] ") {
            hasTodoPrefix = false
            hasIncompletedTask = true
        }

        if letterPrefix.starts(with: "- [x] ") {
            hasTodoPrefix = true
        }

        letterPrefix =
            letterPrefix
                .replacingOccurrences(of: "- [ ] ", with: "")
                .replacingOccurrences(of: "- [x] ", with: "")

        return (hasTodoPrefix, hasIncompletedTask, whitespacePrefix + letterPrefix)
    }

    private func hasPrefix(line: String, numbers: Bool) -> Bool {
        if line.starts(with: "- [ ] ") || line.starts(with: "- [x] ") {
            return false
        }

        var checkNumberDot = false

        for char in line {
            if checkNumberDot {
                if char == "." {
                    return numbers
                }
            }

            if char.isWhitespace {
                continue
            } else {
                if char.isNumber {
                    checkNumberDot = true
                    continue
                } else if char == "-" {
                    return !numbers
                } else {
                    return false
                }
            }
        }

        return false
    }
}
