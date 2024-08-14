//
//  EditTextView.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 8/11/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Cocoa
import Highlightr
import Carbon.HIToolbox
import FSNotesCore_macOS
import SwiftSoup

class EditTextView: NSTextView, NSTextFinderClient, NSSharingServicePickerDelegate {
    
    public var editorViewController: EditorViewController?
    public var textStorageProcessor: TextStorageProcessor?
    public var note: Note?
    public var viewDelegate: ViewController?
    
    var isHighlighted: Bool = false
    let storage = Storage.shared()
    let caretWidth: CGFloat = 2
    var downView: MPreviewView?
    
    public var timer: Timer?
    public var tagsTimer: Timer?
    public var markdownView: MPreviewView?
    public var isLastEdited: Bool = false
    
    @IBOutlet weak var previewMathJax: NSMenuItem!

    public var imagesLoaderQueue = OperationQueue.init()
    public var attributesCachingQueue = OperationQueue.init()
    
    private var preview = false
    
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        validateSubmenu(menu)
    }
    
    override func becomeFirstResponder() -> Bool {        
        if let note = self.note {
            if note.container == .encryptedTextPack {
                return false
            }

            removeHighlight()
        }
        
        return super.becomeFirstResponder()
    }

    //MARK: caret width

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard UserDefaultsManagement.inlineTags else { return }
        
        if #available(OSX 10.16, *) {
            let range = NSRange(location: 0, length: textStorage!.length)
            attributedString().enumerateAttributes(in: range, options: .reverse) {
                attributes, range, stop in

                let tag = attributedString().attributedSubstring(from: range).string
                guard attributes.index(forKey: .tag) != nil, let font = attributes[.font] as? NSFont else { return }
                let parStyle = attributes[.paragraphStyle] as? NSMutableParagraphStyle

                var lineSpacing = CGFloat(0)
                if let line = parStyle?.lineSpacing {
                    lineSpacing = line
                }

                let parRange = textStorage?.mutableString.paragraphRange(for: range)
                if textStorage?.length == parRange?.upperBound && textStorage?.string.last != "\n" {
                    lineSpacing = 0
                }

                guard let container = self.textContainer else { return }
                guard let activeRange = self.layoutManager?.glyphRange(forCharacterRange: range, actualCharacterRange: nil) else { return }

                guard var tagRect = self.layoutManager?.boundingRect(forGlyphRange: activeRange, in: container) else { return }

                tagRect.origin.x += self.textContainerOrigin.x;
                tagRect.origin.y += self.textContainerOrigin.y;
                tagRect = self.convertToLayer(tagRect)

                let tagAttributes = attributedString().attributes(at: range.location, effectiveRange: nil)
                let oneCharSize = ("A" as NSString).size(withAttributes: tagAttributes)

                let height = tagRect.size.height - lineSpacing
                let tagBorderRect = NSRect(origin: CGPoint(x: tagRect.origin.x, y: tagRect.origin.y), size: CGSize(width: tagRect.size.width + oneCharSize.width*0.25, height: height))

                NSGraphicsContext.saveGraphicsState()

                let path = NSBezierPath(roundedRect: tagBorderRect, xRadius: 3, yRadius: 3)

                let fillColor = NSColor.tagColor
                let textColor = NSColor.white

                path.addClip()
                fillColor.setFill()
                tagBorderRect.fill(using: .sourceIn)

//                let transform = NSAffineTransform()
//                transform.translateX(by: 0.5, yBy: 0.5)
//                path.transform(using: transform as AffineTransform)
//                path.stroke()
//                transform.translateX(by: -1.5, yBy: -1.5)
//                path.transform(using: transform as AffineTransform)
//                path.stroke()

                let dict = NSMutableDictionary(dictionary: tagAttributes)
                dict.addEntries(from: [
                    NSAttributedString.Key.font: font,
                    NSAttributedString.Key.foregroundColor: textColor,
                    NSAttributedString.Key.baselineOffset: -(font.pointSize - 1)
                ])

                dict.removeObject(forKey: NSAttributedString.Key.link)

                let newRect = tagBorderRect.offsetBy(dx: 1, dy: 0)
                (tag as NSString).draw(with: newRect, options: .init(), attributes: (dict as! [NSAttributedString.Key : Any]))

                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    
    public func initTextStorage() {
        let processor = TextStorageProcessor()
        processor.editor = self
        
        textStorageProcessor = processor
        textStorage?.delegate = processor
    }
    
    public func configure() {
        DispatchQueue.main.async {
            self.updateTextContainerInset()
        }
            
        attributesCachingQueue.qualityOfService = .background
        textContainerInset.height = 10
        isEditable = false

        layoutManager?.allowsNonContiguousLayout = UserDefaultsManagement.nonContiguousLayout

        if #available(OSX 10.13, *) {} else {
            backgroundColor = UserDefaultsManagement.bgColor
        }

        layoutManager?.defaultAttachmentScaling = .scaleProportionallyDown
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        defaultParagraphStyle = paragraphStyle
        typingAttributes[.paragraphStyle] = paragraphStyle
        
        font = UserDefaultsManagement.noteFont
    }

    public func invalidateLayout() {
        if let length = self.textStorage?.length {
            self.textStorage?.layoutManagers.first?.invalidateLayout(forCharacterRange: NSRange(location: 0, length: length), actualCharacterRange: nil)
        }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any], proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        return []
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var newRect = NSRect(origin: rect.origin, size: rect.size)
        newRect.size.width = self.caretWidth

        if let range = getParagraphRange(), range.upperBound != textStorage?.length || (
            range.upperBound == textStorage?.length
            && textStorage?.string.last == "\n"
            && selectedRange().location != textStorage?.length
        ) {
            newRect.size.height = newRect.size.height - CGFloat(UserDefaultsManagement.editorLineSpacing)
        }

        let clr = NSColor(red:0.47, green:0.53, blue:0.69, alpha:1.0)
        super.drawInsertionPoint(in: newRect, color: clr, turnedOn: flag)
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(true)
    }
    
    override func setNeedsDisplay(_ invalidRect: NSRect) {
        var newInvalidRect = NSRect(origin: invalidRect.origin, size: invalidRect.size)
        newInvalidRect.size.width += self.caretWidth - 1
        super.setNeedsDisplay(newInvalidRect)
    }

    // MARK: Menu
    
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let note = self.note else { return false }

        menuItem.isHidden = false

        if menuItem.menu?.identifier?.rawValue == "editMenu" {
            validateSubmenu(menuItem.menu!)
        }
        
        if menuItem.menu?.identifier?.rawValue == "formatMenu", !hasFocus() {
            return false
        }
        
        if note.isRTF() {
            let disableRTF = [
                "format.h1",
                "format.h2",
                "format.h3",
                "format.h4",
                "format.h5",
                "format.h6",
                "format.codeBlock",
                "format.codeSpan",
                "format.image",
                "format.todo",
                "format.link"
            ]

            if let ident = menuItem.identifier?.rawValue, disableRTF.contains(ident) {
                menuItem.isHidden = true
            }
            
            return !disableRTF.contains(menuItem.title)
        } else {
            let disable = [
                NSLocalizedString("Underline", comment: "")
            ]

            if disable.contains(menuItem.title) {
                menuItem.isHidden = true
            }

            return !disable.contains(menuItem.title)
        }
    }
    
    // MARK: Overrides
    
    override func toggleContinuousSpellChecking(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.continuousSpellChecking = (menu.state == .off)
        }
        super.toggleContinuousSpellChecking(sender)
    }
    
    override func toggleGrammarChecking(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.grammarChecking = (menu.state == .off)
        }
        super.toggleGrammarChecking(sender)
    }
    
    override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.automaticSpellingCorrection = (menu.state == .off)
        }
        super.toggleAutomaticSpellingCorrection(sender)
    }
    
    override func toggleSmartInsertDelete(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.smartInsertDelete = (menu.state == .off)
        }
        super.toggleSmartInsertDelete(sender)
    }
    
    override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.automaticQuoteSubstitution = (menu.state == .off)
        }
        super.toggleAutomaticQuoteSubstitution(sender)
    }
    
    override func toggleAutomaticDataDetection(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.automaticDataDetection = (menu.state == .off)
        }
        super.toggleAutomaticDataDetection(sender)
    }
    
    override func toggleAutomaticLinkDetection(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.automaticLinkDetection = (menu.state == .off)
        }
        super.toggleAutomaticLinkDetection(sender)
    }
    
    override func toggleAutomaticTextReplacement(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.automaticTextReplacement = (menu.state == .off)
        }
        super.toggleAutomaticTextReplacement(sender)
    }
    
    override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        if let menu = sender as? NSMenuItem {
            UserDefaultsManagement.automaticDashSubstitution = (menu.state == .off)
        }
        super.toggleAutomaticDashSubstitution(sender)
    }

    override func mouseDown(with event: NSEvent) {
        
        guard let note = self.note, note.type == .Markdown else { return super.mouseDown(with: event) }
        guard note.container != .encryptedTextPack else {
            editorViewController?.unLock(notes: [note])
            editorViewController?.vcNonSelectedLabel?.isHidden = false
            return
        }
        
        guard let container = self.textContainer, let manager = self.layoutManager else { return super.mouseDown(with: event) }

        let point = self.convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)

        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)

        let glyphRect = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)

        if glyphRect.contains(properPoint), isTodo(index) {
            guard let f = self.getTextFormatter() else { return super.mouseDown(with: event) }
            f.toggleTodo(index)

            NSApp.mainWindow?.makeFirstResponder(nil)

            DispatchQueue.main.async {
                NSCursor.pointingHand.set()
            }
            
            return
        }
        
        super.mouseDown(with: event)
        saveSelectedRange()
        
        if editorViewController?.vcEditor?.isPreviewEnabled() == false {
            self.isEditable = true
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        if let isHidden = editorViewController?.vcNonSelectedLabel?.isHidden as? Bool, !isHidden {
            NSCursor.arrow.set()
            return
        }

        let point = self.convert(event.locationInWindow, from: nil)
        let properPoint = NSPoint(x: point.x - textContainerInset.width, y: point.y)

        guard let container = self.textContainer, let manager = self.layoutManager else { return }

        let index = manager.characterIndex(for: properPoint, in: container, fractionOfDistanceBetweenInsertionPoints: nil)

        let glyphRect = manager.boundingRect(forGlyphRange: NSRange(location: index, length: 1), in: container)
        
        if glyphRect.contains(properPoint), self.isTodo(index) {
            NSCursor.pointingHand.set()
            return
        }

        if glyphRect.contains(properPoint), ((textStorage?.attribute(.link, at: index, effectiveRange: nil)) != nil) {
            NSCursor.pointingHand.set()
            return
        }
        
        if editorViewController?.vcEditor?.isPreviewEnabled() == true {
            return
        }
        
        super.mouseMoved(with: event)
    }
    
    public func isTodo(_ location: Int) -> Bool {
        guard let storage = self.textStorage else { return false }
        
        let range = (storage.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
        let string = storage.attributedSubstring(from: range).string as NSString

        if storage.attribute(.todo, at: location, effectiveRange: nil) != nil {
            return true
        }

        var length = string.range(of: "- [ ]").length
        if length == 0 {
            length = string.range(of: "- [x]").length
        }
        
        if length > 0 {
            let upper = range.location + length
            if location >= range.location && location <= upper {
                return true
            }
        }

        return false
    }

    private func isBetweenBraces(location: Int) -> (String, NSRange)? {
        guard let storage = textStorage else { return nil }

        let string = Array(storage.string)
        let length = string.count

        guard location < length else { return nil }

        var firstLeftFound = false
        var firstRigthFound = false

        var rigthFound = false
        var leftFound = false

        var i = location - 1
        var j = location

        while i >= 0 {
            let char = string[i]
            if firstLeftFound {
                leftFound = char == "["
                break
            }

            if char.isNewline {
                break
            }

            if char == "[" {
                firstLeftFound = true
            }

            i -= 1
        }

        while length > j {
            let char = string[j]
            if firstRigthFound {
                rigthFound = char == "]"
                break
            }

            if char.isNewline {
                break
            }

            if char == "]" {
                firstRigthFound = true
            }

            j += 1
        }

        var result = String()
        if leftFound && rigthFound {
            result =
                String(string[i...j])

            result = result
                .replacingOccurrences(of: "[[", with: "")
                .replacingOccurrences(of: "]]", with: "")

            return (result, NSRange(i...j))
        }

        return nil
    }

    private var completeRange = NSRange()

    override var rangeForUserCompletion: NSRange {
        guard let storageString = textStorage?.string else { return super.rangeForUserCompletion }

        let to = storageString.utf16.index(storageString.utf16.startIndex, offsetBy: selectedRange.location)
        let distance = string.distance(from: storageString.startIndex, to: to)

        if let result = isBetweenBraces(location: distance) {
            let range = result.1

            // decode multibyte offset for Emoji like "🇺🇦"
            let startIndex = string.index(string.startIndex, offsetBy: range.lowerBound + 2)
            let startRange = NSRange(startIndex...startIndex, in: string)
            let replacementRange = NSRange(location: startRange.lowerBound, length: result.0.count)

            return replacementRange
        }

        if UserDefaultsManagement.inlineTags {
            var location = distance
            var length = 0

            while true {
                if location - 1 < 0 {
                    break
                }

                let scanRange = NSRange(location: location - 1, length: 1)
                let char = textStorage?.attributedSubstring(from: scanRange).string

                if char?.isWhitespace != nil {
                    break
                }

                if char == "#" {
                    return NSRange(location: location, length: length)
                }

                length += 1
                location = location - 1
            }
        }

        return super.rangeForUserCompletion
    }

    override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {

        guard let storageString = textStorage?.string else { return nil }

        let to = storageString.utf16.index(storageString.utf16.startIndex, offsetBy: selectedRange.location)
        let distance = string.distance(from: storageString.startIndex, to: to)

        if let result = isBetweenBraces(location: distance) {
            if let notes = storage.getBy(contains: result.0) {
                let titles = notes.map{ String($0.title) }.filter({ $0.count > 0 }).filter({ $0 != result.0

                }).sorted()

                return titles
            }

            return nil
        }

        let mainWord = (string as NSString).substring(with: charRange)

        if UserDefaultsManagement.inlineTags {
            if (string as NSString).substring(with: charRange) == "#" {
                if let tags = viewDelegate?.sidebarOutlineView.getAllTags() {
                    let list = tags.compactMap({ "#\($0)"}).sorted { $0.count > $1.count }

                    return unfoldTags(list: list).sorted { $0.count < $1.count }
                }

                return nil
            } else if charRange.location > 0,
                let parRange = textStorage?.mutableString.paragraphRange(for: NSRange(location: charRange.location, length: 0)),
                let paragraph = textStorage?.mutableString.substring(with: parRange)
            {
                let words = paragraph.components(separatedBy: " ")

                var i = parRange.location
                for word in words {
                    let range = NSRange(location: i + 1, length: word.count)
                    i += word.count + 1

                    if word == "" || charRange.location > range.upperBound || charRange.location < range.lowerBound || range.location <= 0 {
                        continue
                    }

                    if let tags = viewDelegate?.sidebarOutlineView.getAllTags(),
                        let partialWord = textStorage?.mutableString.substring(with: NSRange(range.location..<charRange.upperBound)) {

                        var parts = partialWord.components(separatedBy: "/")
                        _ = parts.popLast()

                        if !partialWord.contains("/") {
                            let list = tags.filter({ $0.starts(with: partialWord )})

                            return unfoldTags(list: list, isFirstLevel: true, word: mainWord).sorted { $0.count < $1.count }
                        }

                        let excludePart = parts.joined(separator: "/")
                        let offset = excludePart.count + 1

                        if partialWord.last != "/" {
                            let list = tags.filter({ $0.starts(with: partialWord )})
                                .filter({ $0 != partialWord })
                                .compactMap({ String($0[offset...]) })

                            return unfoldTags(list: list, word: mainWord).sorted { $0.count < $1.count }
                        }

                        if let lastPart = parts.popLast() {
                            let list = tags.filter({ $0.starts(with: partialWord )})
                                .filter({ $0 != partialWord })
                                .compactMap({ String(lastPart + "/" + $0[offset...]) })

                            return unfoldTags(list: list, word: mainWord).sorted { $0.count < $1.count }
                        }

                        return nil
                    }
                }
            }
        }

        return nil
    }

    private func unfoldTags(list: [String], isFirstLevel: Bool = false, word: String = "") -> [String] {

        let check = word + "/"
        if list.filter({ $0.starts(with: check)}).count > 0 {
            return []
        }

        var list: Set<String> = Set(list)

        for listItem in list {
            if listItem.contains("/") {
                let items = listItem.components(separatedBy: "/")

                var start = items.first!
                var first = true

                for item in items {
                    if first {
                        first = false
                        if isFirstLevel, !list.contains(start) {
                            list.insert(start)
                        }
                        continue
                    }

                    start += ("/" + item)

                    if !list.contains(start) {
                        list.insert(start)
                    }
                }
            }
        }

        return Array(list).sorted()
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        get {
            if let note = self.note, note.type == .RichText {
                return super.writablePasteboardTypes
            }
            
            return
                [NSPasteboard.PasteboardType.rtfd, NSPasteboard.PasteboardType.string, NSPasteboard.attributedTextType]
        }
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        get {
            if let note = self.note, note.type == .RichText {
                return super.readablePasteboardTypes
            }
            
            return super.readablePasteboardTypes + [NSPasteboard.attributedTextType]
        }
    }

    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let note = self.note, var data = pboard.data(forType: type) {
            if type == .tiff || type == .png {
                let image = NSImage(data: data)
                
                if let imageData = image?.jpgData {
                    data = imageData
                    
                    textStorageProcessor?.shouldForceRescan = true
                    saveClipboard(data: data, note: note, ext: "jpg")
                    saveTextStorageContent(to: note)
                    note.save()
                    
                    if let container = textContainer {
                        textStorage?.sizeAttachmentImages(container: container)
                    }
                    
                    return true
                }
                
                return false
            }
            
            if data.isPDF {
                textStorageProcessor?.shouldForceRescan = true
                saveClipboard(data: data, note: note, ext: "pdf")
                saveTextStorageContent(to: note)
                note.save()
                
                if let container = textContainer {
                    textStorage?.sizeAttachmentImages(container: container)
                }
                
                return true
            }
        }

        return super.readSelection(from: pboard, type: type)
    }

    override func writeSelection(to pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        
        if let note = self.note, note.type == .RichText {
            return super.writeSelection(to: pboard, type: type)
        }

        guard let storage = textStorage else { return false }

        let range = selectedRange()
        let attributedString = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))

        if type == .string {
            let plainText = attributedString.unLoadImages().unLoadCheckboxes().string

            pboard.setString(plainText, forType: .string)
            return true
        }

        if type == NSPasteboard.attributedTextType {
            let richString = attributedString.unLoadCheckboxes()

            let imageKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.url")
            let pathKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.path")

            richString.enumerateAttribute(.attachment, in: NSMakeRange(0,(richString.length)), options: .reverse, using:  {(_ value: Any?, _ range: NSRange, _ stop: UnsafeMutablePointer<ObjCBool>) -> Void in

                guard let textAttachment = value as? NSTextAttachment,
                      let url = richString.attribute(imageKey, at: range.location, effectiveRange: nil) as? URL,
                      let image = try? Data(contentsOf: url) else { return }

                richString.removeAttribute(pathKey, range: range)
                richString.removeAttribute(imageKey, range: range)

                let imageWrapper = FileWrapper(regularFileWithContents: image)
                let fileExtension = ImageFormat.get(from: image).rawValue

                imageWrapper.preferredFilename = "\(UUID()).\(fileExtension)"
                textAttachment.fileWrapper = imageWrapper
            })

            if let rtfd = try? richString.data(from: NSMakeRange(0, richString.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd]) {
                pboard.setData(rtfd, forType: NSPasteboard.attributedTextType)

                return super.writeSelection(to: pboard, type: type)
            }
        }

        if type == .rtfd {
            let richString = attributedString.unLoadCheckboxes()
            if let rtfd = try? richString.data(from: NSMakeRange(0, richString.length), documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtfd]) {
                pboard.setData(rtfd, forType: NSPasteboard.PasteboardType.rtfd)
                return true
            }
        }

        if type.rawValue == "NSStringPboardType" {
            textStorageProcessor?.shouldForceRescan = true
            return super.writeSelection(to: pboard, type: type)
        }

        return false
    }

    // Copy empty string
    override func copy(_ sender: Any?) {
        if selectedRanges.count > 1, let note = self.note {
            var combined = String()
            for range in selectedRanges {
                if let range = range as? NSRange, let sub = attributedSubstring(forProposedRange: range, actualRange: nil) as? NSMutableAttributedString {
                    if note.isMarkdown() {
                        combined.append(sub.unLoadCheckboxes().unLoadImages().string + "\n")
                    } else {
                        combined.append(sub.string + "\n")
                    }
                }
            }

            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(combined.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return
        }

        if self.selectedRange.length == 0, let paragraphRange = self.getParagraphRange(), let paragraph = attributedSubstring(forProposedRange: paragraphRange, actualRange: nil) {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(paragraph.string.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)
            return
        }

        super.copy(sender)
    }

    override func paste(_ sender: Any?) {
        guard let note = self.note else { return }

        guard note.isMarkdown() else {
            super.paste(sender)

            fillPlainAndRTFStyle(note: note, saveTyping: false)
            return
        }

        if let rtfd = NSPasteboard.general.data(forType: NSPasteboard.attributedTextType) {
            let options = [
                NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtfd
            ] as [NSAttributedString.DocumentReadingOptionKey : Any]

            let attributedString = try? NSMutableAttributedString(data: rtfd, options: options, documentAttributes: nil)

            attributedString?.loadCheckboxes()

            if let attributedString = attributedString {
                let currentRange = selectedRange()

                insertText(attributedString, replacementRange: currentRange)
                breakUndoCoalescing()

                guard let container = textContainer else { return }
                textStorage?.sizeAttachmentImages(container: container)

                saveImages()
                saveTextStorageContent(to: note)

                return
            }
        }

        if let clipboard = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string), NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.fileURL) == nil {
            let attributed = NSMutableAttributedString(string: clipboard)
            attributed.loadCheckboxes()

            textStorageProcessor?.shouldForceRescan = true

            let currentRange = selectedRange()

            self.breakUndoCoalescing()
            self.insertText(attributed, replacementRange: currentRange)
            self.breakUndoCoalescing()

            saveTextStorageContent(to: note)
            return
        }

        if pasteImageFromClipboard(in: note) {
            return
        }

        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard let note = self.note else { return }

        guard note.isMarkdown() else {
            super.pasteAsPlainText(sender)
            return
        }

        let currentRange = selectedRange()
        var plainText: String?

        if let rtfd = NSPasteboard.general.data(forType: NSPasteboard.attributedTextType) {
            let options = [
                NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtfd
            ] as [NSAttributedString.DocumentReadingOptionKey : Any]

            let attributedString = try? NSMutableAttributedString(data: rtfd, options: options, documentAttributes: nil)
            attributedString?.loadCheckboxes()

            if let attributedString = attributedString {
                plainText = attributedString.unLoad().string
            }
        } else if let clipboard = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.string), NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.fileURL) == nil {
            plainText = clipboard
        } else if let url = NSPasteboard.general.string(forType: NSPasteboard.PasteboardType.fileURL) {
            plainText = url
        }

        if let plainText = plainText {
            textStorageProcessor?.shouldForceRescan = true

            self.breakUndoCoalescing()
            self.insertText(plainText, replacementRange: currentRange)
            self.breakUndoCoalescing()

            saveTextStorageContent(to: note)
            return
        }

        return paste(sender)
    }

    override func cut(_ sender: Any?) {
        guard nil != self.note else {
            super.cut(sender)
            return
        }

        if self.selectedRange.length == 0, let paragraphRange = self.getParagraphRange(), let paragraph = attributedSubstring(forProposedRange: paragraphRange, actualRange: nil) {
            let pasteboard = NSPasteboard.general
            pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: nil)
            pasteboard.setString(paragraph.string.trim().removeLastNewLine(), forType: NSPasteboard.PasteboardType.string)

            insertText(String(), replacementRange: paragraphRange)
            return
        }

        super.cut(sender)
    }

    public func saveImages() {
        guard let storage = textStorage else { return }

        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { (value, range, _) in

            guard let textAttachment = value as? NSTextAttachment,
                storage.attribute(.todo, at: range.location, effectiveRange: nil) == nil else {
                return
            }

            let filePathKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.path")

            if (storage.attribute(filePathKey, at: range.location, effectiveRange: nil) as? String) != nil {
                return
            }

            if let note = self.note,
                let imageData = textAttachment.fileWrapper?.regularFileContents,
                let path = ImagesProcessor.writeFile(data: imageData, note: note) {

                storage.addAttribute(filePathKey, value: path, range: range)
            }
        }
    }

    func getSelectedNote() -> Note? {
        return ViewController.shared()?.notesTableView?.getSelectedNote()
    }
    
    public func isEditable(note: Note) -> Bool {
        if note.container == .encryptedTextPack {
            return false
        }
        
        if editorViewController?.vcEditor?.isPreviewEnabled() == true && !note.isRTF() {
            return false
        }
        
        return true
    }

    public func getVC() -> EditorViewController {
        return self.window?.contentViewController as! EditorViewController
    }
    
    public func getEVC() -> EditorViewController? {
        return self.window?.contentViewController as? EditorViewController
    }
    
    func fill(note: Note, highlight: Bool = false, saveTyping: Bool = false, force: Bool = false) {
        if !note.isLoaded {
            note.load()
        }
        
        textStorage?.setAttributedString(NSAttributedString(string: ""))
        
        // Hack for invalidate prev layout data (order is important, only before fill)
        if let length = textStorage?.length {
            textStorage?.layoutManagers.first?.invalidateDisplay(forGlyphRange: NSRange(location: 0, length: length))

            invalidateLayout()
        }

        undoManager?.removeAllActions(withTarget: self)
        registerHandoff(note: note)

        // resets timer if editor refilled 
        viewDelegate?.breakUndoTimer.invalidate()

        unregisterDraggedTypes()
        registerForDraggedTypes([
            NSPasteboard.PasteboardType(kUTTypeFileURL as String),
            NSPasteboard.noteType,
            .URL
        ])

        if let label = editorViewController?.vcNonSelectedLabel {
            label.isHidden = true

            if note.container == .encryptedTextPack {
                label.stringValue = NSLocalizedString("Locked", comment: "")
                label.isHidden = false
            } else {
                label.stringValue = NSLocalizedString("None Selected", comment: "")
                label.isHidden = true
            }
        }
    
        self.note = note
        UserDefaultsManagement.lastSelectedURL = note.url

        editorViewController?.updateTitle(note: note)

        isEditable = isEditable(note: note)
        
        editorViewController?.editorUndoManager = note.undoManager

        if !saveTyping {
            typingAttributes.removeAll()
            typingAttributes[.font] = UserDefaultsManagement.noteFont
        }

        if isPreviewEnabled() && !note.isRTF() {
            loadMarkdownWebView(note: note, force: force)
            return
        }

        markdownView?.removeFromSuperview()
        markdownView = nil

        guard let storage = textStorage else { return }

        if note.isMarkdown(), let content = note.content.mutableCopy() as? NSMutableAttributedString {
            if UserDefaultsManagement.liveImagesPreview {
                content.loadImages(editor: self, note: note)
            }

            content.replaceCheckboxes()

            textStorageProcessor?.shouldForceRescan = true
            storage.setAttributedString(content)
        } else {
            storage.setAttributedString(note.content)
        }

        if !note.isMarkdown()  {
            fillPlainAndRTFStyle(note: note, saveTyping: saveTyping)
        }
        
        if highlight {
            let search = getSearchText()
            let processor = NotesTextProcessor(storage: storage)
            processor.highlightKeyword(search: search)
            isHighlighted = true
        }

        loadSelectedRange()

        if UserDefaultsManagement.appearanceType == AppearanceType.Custom {
            backgroundColor = UserDefaultsManagement.bgColor
        }
    }

    private func loadMarkdownWebView(note: Note, force: Bool) {
        self.note = nil
        textStorage?.setAttributedString(NSAttributedString())
        self.note = note

        guard let scrollView = editorViewController?.vcEditorScrollView else { return }
        
        if markdownView == nil {
            let frame = scrollView.bounds
            markdownView = MPreviewView(frame: frame, note: note, closure: {})
            markdownView?.setEditorVC(evc: editorViewController)
            if let view = self.markdownView, self.note == note {
                scrollView.addSubview(view)
            }
        } else {
            /// Resize markdownView
            let frame = scrollView.bounds
            markdownView?.frame = frame

            /// Load note if needed
            markdownView?.load(note: note, force: force)
        }
    }

    private func fillPlainAndRTFStyle(note: Note, saveTyping: Bool) {
        guard let storage = textStorage else { return }

        if note.type == .RichText && !saveTyping {
            storage.updateFont()
            storage.loadUnderlines()
        }

        setTextColor()

        let range = NSRange(0..<storage.length)
        let processor = NotesTextProcessor(storage: storage, range: range)
        processor.higlightLinks()
    }

    private func setTextColor() {
        if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
            textColor = NSColor.init(named: "mainText")
        } else {
            textColor = UserDefaultsManagement.fontColor
        }
    }

    func removeHighlight() {
        guard isHighlighted else {
            return
        }
        
        isHighlighted = false
        
        // save cursor position
        let cursorLocation = selectedRanges[0].rangeValue.location

        if let search = viewDelegate?.search.lastSearchQuery, search.count > 0  {
            let processor = NotesTextProcessor(storage: textStorage)
            processor.highlightKeyword(search: search, remove: true)
        }
        
        // restore cursor
        setSelectedRange(NSRange.init(location: cursorLocation, length: 0))
    }
    
    public func lockEncryptedView() {
        textStorage?.setAttributedString(NSAttributedString())
        markdownView?.removeFromSuperview()
        markdownView = nil

        isEditable = false
        
        if let label = editorViewController?.vcNonSelectedLabel {
            label.stringValue = NSLocalizedString("Locked", comment: "")
            label.isHidden = false
        }
    }
    
    public func clear() {
        textStorage?.setAttributedString(NSAttributedString())
        markdownView?.removeFromSuperview()
        markdownView = nil

        isEditable = false
        
        window?.title = AppDelegate.appTitle
        
        if let label = editorViewController?.vcNonSelectedLabel {
            label.stringValue = NSLocalizedString("None Selected", comment: "")
            label.isHidden = false
            editorViewController?.dropTitle()
        }
        
        self.note = nil
    }

    @IBAction func boldMenu(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.bold()
    }

    @IBAction func italicMenu(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.italic()
    }

    @IBAction func linkMenu(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.link()
    }

    @IBAction func underlineMenu(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.underline()
    }

    @IBAction func strikeMenu(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.strike()
    }

    @IBAction func headerMenu(_ sender: NSMenuItem) {
        guard let note = self.note, isEditable else { return }

        guard let id = sender.identifier?.rawValue else { return }

        let code =
            Int(id.replacingOccurrences(of: "format.h", with: ""))

        var string = String()
        for index in [1, 2, 3, 4, 5, 6] {
            string = string + "#"
            if code == index {
                break
            }
        }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.header(string)
    }

    func getParagraphRange() -> NSRange? {
        guard let storage = textStorage else { return nil }
        
        let range = selectedRange()
        return storage.mutableString.paragraphRange(for: range)
    }
    
    func toggleBoldFont(font: NSFont) -> NSFont {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }
        
        var mask = 0
        if (font.isBold) {
            if (font.isItalic) {
                mask = NSFontItalicTrait
            }
        } else {
            if (font.isItalic) {
                mask = NSFontBoldTrait|NSFontItalicTrait
            } else {
                mask = NSFontBoldTrait
            }
        }
        
        return NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: CGFloat(UserDefaultsManagement.fontSize))!
    }
    
    func toggleItalicFont(font: NSFont) -> NSFont? {
        guard let family = UserDefaultsManagement.noteFont.familyName else {
            return UserDefaultsManagement.noteFont
        }
        
        var mask = 0
        if (font.isItalic) {
            if (font.isBold) {
                mask = NSFontBoldTrait
            }
        } else {
            if (font.isBold) {
                mask = NSFontBoldTrait|NSFontItalicTrait
            } else {
                mask = NSFontItalicTrait
            }
        }
        
        let size = CGFloat(UserDefaultsManagement.fontSize)
        guard let newFont = NSFontManager().font(withFamily: family, traits: NSFontTraitMask(rawValue: NSFontTraitMask.RawValue(mask)), weight: 5, size: size) else {
            return nil
        }
        
        return newFont
    }

    override func keyDown(with event: NSEvent) {
        defer {
            saveSelectedRange()
        }

        guard !(
            event.modifierFlags.contains(.shift) &&
            [
                kVK_UpArrow,
                kVK_DownArrow,
                kVK_LeftArrow,
                kVK_RightArrow
            ].contains(Int(event.keyCode))
        ) else {
            super.keyDown(with: event)
            return
        }
        
        guard let note = self.note else { return }
        
        let brackets = [
            "(" : ")",
            "[" : "]",
            "{" : "}",
            "\"" : "\"",
        ]
        
        if UserDefaultsManagement.autocloseBrackets,
            let openingBracket = event.characters,
            let closingBracket = brackets[openingBracket] {
            if selectedRange().length > 0 {
                let before = NSMakeRange(selectedRange().lowerBound, 0)
                self.insertText(openingBracket, replacementRange: before)
                let after = NSMakeRange(selectedRange().upperBound, 0)
                self.insertText(closingBracket, replacementRange: after)
            } else {
                super.keyDown(with: event)
                self.insertText(closingBracket, replacementRange: selectedRange())
                self.moveBackward(self)
            }
            return
        }

        // hasMarkedText added for Japanese hack https://yllan.org/blog/archives/231
        if event.keyCode == kVK_Tab && !hasMarkedText(){
            breakUndoCoalescing()
            
            let formatter = TextFormatter(textView: self, note: note)
            if formatter.isListParagraph() {
                textStorageProcessor?.shouldForceRescan = true
                
                if NSEvent.modifierFlags.contains(.shift) {
                    formatter.unTab()
                } else {
                    formatter.tab()
                }
                
                breakUndoCoalescing()
                return
            }
            
            if UserDefaultsManagement.indentUsing == 0x01 {
                let tab = TextFormatter.getAttributedCode(string: "  ")
                insertText(tab, replacementRange: selectedRange())
                breakUndoCoalescing()
                return
            }
            
            if UserDefaultsManagement.indentUsing == 0x02 {
                let tab = TextFormatter.getAttributedCode(string: "    ")
                insertText(tab, replacementRange: selectedRange())
                breakUndoCoalescing()
                return
            }

            super.keyDown(with: event)
            return
        }

        if event.keyCode == kVK_Return && !hasMarkedText() && isEditable {
            breakUndoCoalescing()
            let formatter = TextFormatter(textView: self, note: note)
            formatter.newLine()
            breakUndoCoalescing()
            return
        }

        if event.keyCode == kVK_Delete && event.modifierFlags.contains(.option) {
            deleteWordBackward(nil)
            return
        }

        if event.characters?.unicodeScalars.first == "o" && event.modifierFlags.contains(.command) {
            guard let storage = textStorage else { return }

            var location = selectedRange().location
            if location == storage.length && location > 0 {
                location = location - 1
            }

            if storage.length > location, let link = textStorage?.attribute(.link, at: location, effectiveRange: nil) as? String {

                if link.isValidEmail(), let mail = URL(string: "mailto:\(link)") {
                    NSWorkspace.shared.open(mail)
                } else if let url = URL(string: link) {
                    _ = try? NSWorkspace.shared.open(url, options: .default, configuration: [:])
                }
            }

            return
        }

        if note.type == .RichText {
            super.keyDown(with: event)

            let range = getParagraphRange()
            let processor = NotesTextProcessor(storage: textStorage, range: range)
            processor.higlightLinks()

            return
        }
        
        super.keyDown(with: event)
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let note = self.note else {
            return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        }
        
        note.resetAttributesCache()
        
        if let par = getParagraphRange(),
            let text = textStorage?.mutableString.substring(with: par), text.contains("[["), text.contains("]]") {

            guard let storageString = textStorage?.string else { return false }
            let to = storageString.utf16.index(storageString.utf16.startIndex, offsetBy: affectedCharRange.location)
            let distance = string.distance(from: storageString.startIndex, to: to)

            if isBetweenBraces(location: distance) != nil {
                if !hasMarkedText() {
                    DispatchQueue.main.async {
                        self.complete(nil)
                    }
                }

                return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
            }
        }

        if UserDefaultsManagement.inlineTags {
            if let repl = replacementString, repl.count == 1, !["", " ", "\t", "\n"].contains(repl), let parRange = textStorage?.mutableString.paragraphRange(for: NSRange(location: affectedCharRange.location, length: 0)) {

                var nextChar = " "
                let nextCharLocation = affectedCharRange.location + 1
                if selectedRange().length == 0, let textStorage = textStorage, nextCharLocation <= textStorage.length {
                    let nextCharRange = NSRange(location: affectedCharRange.location, length: 1)
                    nextChar = textStorage.mutableString.substring(with: nextCharRange)
                }

                if let paragraph = textStorage?.mutableString.substring(with: parRange) {
                    let words = paragraph.components(separatedBy: " ")
                    var i = parRange.location
                    for word in words {
                        let range = NSRange(location: i + 1, length: word.count)

                        i += word.count + 1

                        if word == ""
                            || affectedCharRange.location >= range.upperBound
                            || affectedCharRange.location < range.lowerBound
                            || range.location <= 0 {
                            continue
                        }


                        let hashRange = NSRange(location: range.location - 1, length: 1)
                        if (self.string as NSString).substring(with: hashRange) == "#", nextChar.isWhitespace {
                            if !hasMarkedText() {
                                DispatchQueue.main.async {
                                    self.complete(nil)
                                }
                                
                                return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
                            }
                        }
                    }
                }
            }
        }
        
        if let vc = ViewController.shared(),
           !vc.tagsScannerQueue.contains(note) {
            vc.tagsScannerQueue.append(note)
        }

        tagsTimer?.invalidate()
        tagsTimer = Timer.scheduledTimer(timeInterval: 2.5, target: self, selector: #selector(scanTagsAndAutoRename), userInfo: nil, repeats: false)

        if replacementString == "", let storage = textStorage {
            let lastChar = storage.attributedSubstring(from: affectedCharRange).string
            if lastChar.count == 1 {
                textStorageProcessor?.lastRemoved = lastChar
            }
        }

        if note.isMarkdown() {
            deleteUnusedImages(checkRange: affectedCharRange)

            typingAttributes.removeValue(forKey: .todo)
            typingAttributes.removeValue(forKey: .tag)

            if let paragraphStyle = typingAttributes[.paragraphStyle] as? NSMutableParagraphStyle {
                paragraphStyle.alignment = .left
            }

            if textStorage?.length == 0 {
                typingAttributes[.foregroundColor] = UserDataService.instance.isDark ? NSColor.white : NSColor.black
            }
        }

        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func insertCompletion(_ word: String, forPartialWordRange charRange: NSRange, movement: Int, isFinal flag: Bool) {
        guard let storageString = textStorage?.string else { return }

        let to = storageString.utf16.index(storageString.utf16.startIndex, offsetBy: selectedRange.location)
        let distance = string.distance(from: storageString.startIndex, to: to)

        if nil != isBetweenBraces(location: distance) {
            if movement == NSReturnTextMovement {
                super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: true)
            }
            return
        }

        var final = flag

        if let event = self.window?.currentEvent, event.type == .keyDown, ["_", "/"].contains(event.characters) {
            final = false
        }

        super.insertCompletion(word, forPartialWordRange: charRange, movement: movement, isFinal: final)
    }

    @objc public func scanTagsAndAutoRename() {
        guard let vc = ViewController.shared() else { return }
        let notes = vc.tagsScannerQueue

        attributesCachingQueue.addOperation {
            for note in notes {
                note.cache()
            }
        }
        
        for note in notes {
            let result = note.scanContentTags()
            guard let outline = ViewController.shared()?.sidebarOutlineView else { return }

            let added = result.0
            let removed = result.1

            if removed.count > 0 {
                outline.removeTags(removed)
            }

            if added.count > 0 {
                outline.addTags(added)
            }

            if let title = note.getAutoRenameTitle() {
                note.rename(to: title)

                if let editorViewController = getEVC() {
                    editorViewController.vcTitleLabel?.updateNotesTableView()
                    editorViewController.updateTitle(note: note)
                }
            }

            ViewController.shared()?.tagsScannerQueue.removeAll(where: { $0 === note })
        }
    }

    func saveSelectedRange() {
        guard let note = self.note, let range = selectedRanges[0] as? NSRange else {
            return
        }

        note.setSelectedRange(range: range) 
    }
    
    func loadSelectedRange() {
        guard let storage = textStorage else { return }

        if let range = self.note?.getSelectedRange(), range.upperBound <= storage.length {
            setSelectedRange(range)
            scrollToCursor()
        }
    }
    
    func saveTextStorageContent(to note: Note) {
        guard note.container != .encryptedTextPack, let storage = self.textStorage else { return }

        let string = storage.attributedSubstring(from: NSRange(0..<storage.length))

        note.modifiedLocalAt = Date()
        note.content =
            NSMutableAttributedString(attributedString: string)
                .unLoadImages()
                .unLoadCheckboxes()
    }
    
    func setEditorTextColor(_ color: NSColor) {
        if let note = self.note, !note.isMarkdown() {
            textColor = color
        }
    }
    
    func getPreviewStyle() -> String {
        var codeStyle = ""
        if let hgPath = Bundle(for: Highlightr.self).path(forResource: UserDefaultsManagement.codeTheme + ".min", ofType: "css") {
            codeStyle = try! String.init(contentsOfFile: hgPath)
        }
        
        guard let familyName = UserDefaultsManagement.noteFont.familyName else {
            return codeStyle
        }
        
        return "body {font: \(UserDefaultsManagement.fontSize)px \(familyName); } code, pre {font: \(UserDefaultsManagement.codeFontSize)px \(UserDefaultsManagement.codeFontName);} \(codeStyle)"
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        imagesLoaderQueue.maxConcurrentOperationCount = 3
        imagesLoaderQueue.qualityOfService = .userInteractive
    }

    override var textContainerOrigin: NSPoint {
        let origin = super.textContainerOrigin
        return NSPoint(x: origin.x, y: origin.y - 7)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let board = sender.draggingPasteboard
        let range = selectedRange
        let dropPoint = convert(sender.draggingLocation, from: nil)
        let caretLocation = characterIndexForInsertion(at: dropPoint)
        var replacementRange = NSRange(location: caretLocation, length: 0)

        guard let note = self.note, let storage = textStorage else { return false }

        if let data = board.data(forType: .rtfd),
            let text = NSAttributedString(rtfd: data, documentAttributes: nil),
            text.length > 0,
            range.length > 0
        {
            insertText("", replacementRange: range)

            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)

            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.loadCheckboxes()

            insertText(mutable, replacementRange: NSRange(location: caretLocation, length: 0))

            guard let container = textContainer else { return false }
            storage.sizeAttachmentImages(container: container)

            DispatchQueue.main.async {
                self.setSelectedRange(NSRange(location: caretLocation, length: mutable.length))
            }
            
            return true
        }

        if let data = board.data(forType: NSPasteboard.PasteboardType.init(rawValue: "attributedText")), 
            let attributedText = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSMutableAttributedString.self, from: data) {

            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)
            
            let filePathKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.path")
            let titleKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.title")
            let positionKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.position")
            
            guard
                let path = attributedText.attribute(filePathKey, at: 0, effectiveRange: nil) as? String,
                let title = attributedText.attribute(titleKey, at: 0, effectiveRange: nil) as? String,
                let position = attributedText.attribute(positionKey, at: 0, effectiveRange: nil) as? Int else { return false }
            
            guard let imageUrl = note.getImageUrl(imageName: path) else { return false }

            let locationDiff = position > caretLocation ? caretLocation : caretLocation - 1
            let attachment = NoteAttachment(editor: self, title: title, path: path, url: imageUrl)

            guard let attachmentText = attachment.getAttributedString() else { return false }
            guard locationDiff < storage.length else { return false }
            
            textStorage?.deleteCharacters(in: NSRange(location: position, length: 1))
            textStorage?.replaceCharacters(in: NSRange(location: locationDiff, length: 0), with: attachmentText)

            safeSave(note: note)
            setSelectedRange(NSRange(location: caretLocation, length: 0))

            return true
        }

        if let archivedData = board.data(forType: NSPasteboard.noteType),
           let urls = try? NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSArray.self, NSURL.self], from: archivedData) as? [URL],
           let url = urls.first,
           let draggableNote = Storage.shared().getBy(url: url) {

            let title = "[[" + draggableNote.title + "]]"
            NSApp.mainWindow?.makeFirstResponder(self)

            DispatchQueue.main.async {
                self.insertText(title, replacementRange: replacementRange)
                self.setSelectedRange(NSRange(location: caretLocation + title.count, length: 0))

                self.safeSave(note: note)
            }

            return true
        }
        
        if let urls = board.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
            urls.count > 0 {

            safeSave(note: note)

            for (index, url) in urls.enumerated() {
                fetchDataFromURL(url: url) { (data, error) in
                    if let error = error {
                        print("Error fetching data: \(error.localizedDescription)")
                        return
                    }

                    guard let data = data else { return }

                    DispatchQueue.main.async {
                        if url.absoluteString.startsWith(string: "https://") || url.absoluteString.startsWith(string: "http://") {
                            let title = self.getHTMLTitle(from: data) ?? ""
                            self.insertText("[\(title)](\(url.absoluteString))", replacementRange: replacementRange)
                            return
                        }

                        guard let filePath = ImagesProcessor.writeFile(data: data, url: url, note: note) else { return }

                        if UserDefaultsManagement.liveImagesPreview {
                            let cleanPath = filePath.removingPercentEncoding ?? filePath
                            guard let url = note.getImageUrl(imageName: cleanPath) else { return }
                            let attachment = NoteAttachment(editor: self, title: "", path: cleanPath, url: url, note: note)

                            let newLine = urls.count > 0 && index != urls.count - 1
                            if let string = attachment.getAttributedString(newLine: newLine) {
                                self.textStorageProcessor?.shouldForceRescan = true

                                self.insertText(string, replacementRange: replacementRange)
                                replacementRange = NSRange(location: replacementRange.location + string.length, length: 0)
                                self.setSelectedRange(replacementRange)
                            }
                        } else {
                            let string = "![](\(filePath))\n"
                            self.insertText(string, replacementRange: replacementRange)
                            replacementRange = NSRange(location: replacementRange.location + string.count, length: 0)
                            self.setSelectedRange(replacementRange)
                        }

                        if let storage = self.textStorage {
                            NotesTextProcessor.highlightMarkdown(attributedString: storage, note: note)
                            self.saveTextStorageContent(to: note)
                            note.save()
                        }

                        self.viewDelegate?.notesTableView.reloadRow(note: note)
                    }
                }
            }

            return true
        }

        return false
    }

    func fetchDataFromURL(url: URL, completion: @escaping (Data?, Error?) -> Void) {
        let session = URLSession.shared

        let task = session.dataTask(with: url) { (data, response, error) in
            if let error = error {
                completion(nil, error)
                return
            }

            completion(data, nil)
        }

        task.resume()
    }

    func getHTMLTitle(from data: Data) -> String? {
        do {
            let htmlString = String(data: data, encoding: .utf8)
            let doc = try SwiftSoup.parse(htmlString!)
            let titleElement = try doc.select("title").first()
            let title = try titleElement?.text()

            return title
        } catch {
            print("Error parsing HTML: \(error.localizedDescription)")
            return nil
        }
    }

    public func safeSave(note: Note) {
        guard note.container != .encryptedTextPack else { return }
        
        note.save(attributed: attributedString())
    }
    
    func getSearchText() -> String {
        guard let search = ViewController.shared()?.search else { return String() }

        if let editor = search.currentEditor(), editor.selectedRange.length > 0 {
            return (search.stringValue as NSString).substring(with: NSRange(0..<editor.selectedRange.location))
        }
        
        return search.stringValue
    }

    public func scrollToCursor() {
        let cursorRange = NSMakeRange(self.selectedRange().location, 0)

        // DispatchQueue fixes rare bug when textStorage invalidation not working (blank page instead text)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.scrollRangeToVisible(cursorRange)
        }
    }
    
    public func hasFocus() -> Bool {
        if let fr = self.window?.firstResponder, fr.isKind(of: EditTextView.self) {
            return true
        }
        
        return false
    }

    @IBAction func shiftLeft(_ sender: Any) {
        guard let note = self.note, isEditable else { return }
        let f = TextFormatter(textView: self, note: note)

        textStorageProcessor?.shouldForceRescan = true
        f.unTab()
    }
    
    @IBAction func shiftRight(_ sender: Any) {
        guard let note = self.note, isEditable else { return }
        let f = TextFormatter(textView: self, note: note)

        textStorageProcessor?.shouldForceRescan = true
        f.tab()
    }

    @IBAction func todo(_ sender: Any) {
        guard let f = self.getTextFormatter(), isEditable else { return }
        
        f.todo()
    }

    @IBAction func wikiLinks(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.wikiLink()
    }

    @IBAction func pressBold(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.bold()
    }

    @IBAction func pressItalic(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.italic()
    }
    
    @IBAction func insertFileOrImage(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.canCreateDirectories = true
        panel.begin { (result) -> Void in
            if result == NSApplication.ModalResponse.OK {
                let urls = panel.urls

                for url in urls {
                    if self.saveFile(url: url, in: note) {
                        if urls.count > 1 {
                            self.insertNewline(nil)
                        }
                    }
                }

                if let vc = ViewController.shared() {
                    vc.notesTableView.reloadRow(note: note)
                }
            }
        }
    }

    @IBAction func insertCodeBlock(_ sender: NSButton) {
        guard isEditable else { return }

        let currentRange = selectedRange()

        if currentRange.length > 0 {
            let mutable = NSMutableAttributedString(string: "```\n")
            if let substring = attributedSubstring(forProposedRange: currentRange, actualRange: nil) {
                mutable.append(substring)

                if substring.string.last != "\n" {
                    mutable.append(NSAttributedString(string: "\n"))
                }
            }

            mutable.append(NSAttributedString(string: "```\n"))

            textStorageProcessor?.shouldForceRescan = true
            insertText(mutable, replacementRange: currentRange)
            setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
            
            return
        }

        if textStorage?.length == 0 {
            textStorageProcessor?.shouldForceRescan = true
        }
        
        insertText("```\n\n```\n", replacementRange: currentRange)
        setSelectedRange(NSRange(location: currentRange.location + 3, length: 0))
    }

    @IBAction func insertCodeSpan(_ sender: NSMenuItem) {
        guard isEditable else { return }

        let currentRange = selectedRange()

        if currentRange.length > 0 {
            let mutable = NSMutableAttributedString(string: "`")
            if let substring = attributedSubstring(forProposedRange: currentRange, actualRange: nil) {
                mutable.append(substring)
            }

            mutable.append(NSAttributedString(string: "`"))

            textStorageProcessor?.shouldForceRescan = true
            insertText(mutable, replacementRange: currentRange)
            return
        }

        insertText("``", replacementRange: currentRange)
        setSelectedRange(NSRange(location: currentRange.location + 1, length: 0))
    }

    @IBAction func insertList(_ sender: NSMenuItem) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.list()
    }

    @IBAction func insertOrderedList(_ sender: NSMenuItem) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.orderedList()
    }

    @IBAction func insertQuote(_ sender: NSMenuItem) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.quote()
    }

    @IBAction func insertLink(_ sender: Any) {
        guard let note = self.note, isEditable else { return }

        let formatter = TextFormatter(textView: self, note: note)
        formatter.link()
    }
    
    private func getTextFormatter() -> TextFormatter? {
        guard let note = self.note, isEditable else { return nil }
        
        return TextFormatter(textView: self, note: note)
    }
    
    private func validateSubmenu(_ menu: NSMenu) {
        let sg = menu.item(withTitle: NSLocalizedString("Spelling and Grammar", comment: ""))?.submenu
        let s = menu.item(withTitle: NSLocalizedString("Substitutions", comment: ""))?.submenu
        
        sg?.item(withTitle: NSLocalizedString("Check Spelling While Typing", comment: ""))?.state = self.isContinuousSpellCheckingEnabled ? .on : .off
        sg?.item(withTitle: NSLocalizedString("Check Grammar With Spelling", comment: ""))?.state = self.isGrammarCheckingEnabled ? .on : .off
        sg?.item(withTitle: NSLocalizedString("Correct Spelling Automatically", comment: ""))?.state = self.isAutomaticSpellingCorrectionEnabled ? .on : .off
        
        s?.item(withTitle: NSLocalizedString("Smart Copy/Paste", comment: ""))?.state = self.smartInsertDeleteEnabled ? .on : .off
        s?.item(withTitle: NSLocalizedString("Smart Quotes", comment: ""))?.state = self.isAutomaticQuoteSubstitutionEnabled ? .on : .off
        
        s?.item(withTitle: NSLocalizedString("Smart Dashes", comment: ""))?.state = self.isAutomaticDashSubstitutionEnabled ? .on : .off
        s?.item(withTitle: NSLocalizedString("Smart Links", comment: ""))?.state = self.isAutomaticLinkDetectionEnabled  ? .on : .off
        s?.item(withTitle: NSLocalizedString("Text Replacement", comment: ""))?.state = self.isAutomaticTextReplacementEnabled   ? .on : .off
        s?.item(withTitle: NSLocalizedString("Data Detectors", comment: ""))?.state = self.isAutomaticDataDetectionEnabled ? .on : .off
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return true
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.data(forType: NSPasteboard.noteType) != nil {
            let dropPoint = convert(sender.draggingLocation, from: nil)
            let caretLocation = characterIndexForInsertion(at: dropPoint)
            setSelectedRange(NSRange(location: caretLocation, length: 0))
            return .copy
        }

        return super.draggingUpdated(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.data(forType: NSPasteboard.noteType) != nil {
            NSApp.mainWindow?.makeFirstResponder(self)
            return .copy
        }

        guard let selected = attributedSubstring(forProposedRange: selectedRange(), actualRange: nil) else { return .generic }
        
        let attributedString = NSMutableAttributedString(attributedString: selected)
        let positionKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.position")
        attributedString.addAttribute(positionKey, value: selectedRange().location, range: NSRange(0..<1))
        
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: attributedString, requiringSecureCoding: true)
            let type = NSPasteboard.PasteboardType.init(rawValue: "attributedText")
            let board = sender.draggingPasteboard
            board.setData(data, forType: type)
        } catch {
            print("Failed to archive attributed string: \(error)")
        }

        return .copy
    }

    override func clicked(onLink link: Any, at charIndex: Int) {
        if let link = link as? String, link.isValidEmail(), let mail = URL(string: "mailto:\(link)") {
            NSWorkspace.shared.open(mail)
            return
        }

        // Scroll to [TestJump](#TestJump) link
        if let link = link as? String, link.startsWith(string: "#") {
            let title = String(link.dropFirst()).replacingOccurrences(of: "-", with: " ")

            if let index = textStorage?.string.range(of: "# " + title) {
                if let range = textStorage?.string.nsRange(from: index) {
                    setSelectedRange(range)
                    scrollRangeToVisible(range)
                    return
                }
            }
        }

        let range = NSRange(location: charIndex, length: 1)
        
        let char = attributedSubstring(forProposedRange: range, actualRange: nil)
        if char?.attribute(.attachment, at: 0, effectiveRange: nil) == nil {

            if NSEvent.modifierFlags.contains(.command), let link = link as? String, let url = URL(string: link) {
                _ = try? NSWorkspace.shared.open(url, options: .withoutActivation, configuration: [:])
                return
            }
            
            if NSEvent.modifierFlags.contains(.shift), let link = link as? String, URL(string: link) != nil {
                setSelectedRange(NSRange(location: charIndex, length: 0))
                return
            }

            super.clicked(onLink: link, at: charIndex)
            return
        }
        
        if !UserDefaultsManagement.liveImagesPreview {
            let url = URL(fileURLWithPath: link as! String)
            NSWorkspace.shared.open(url)
            return
        }
        
        let titleKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.title")
        let pathKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.path")

        if let event = NSApp.currentEvent,
            !event.modifierFlags.contains(.command),
            let note = self.note,
            let path = (char?.attribute(pathKey, at: 0, effectiveRange: nil) as? String)?.removingPercentEncoding,
            let url = note.getImageUrl(imageName: path) {

            if !url.isImage {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return
            }

            let isOpened = NSWorkspace.shared.openFile(url.path, withApplication: "Preview", andDeactivate: true)

            if isOpened { return }

            let url = URL(fileURLWithPath: url.path)
            NSWorkspace.shared.open(url)
            return
        }

        guard let vc = editorViewController, let window = vc.view.window else { return }

        vc.alert = NSAlert()
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 290, height: 20))
        field.placeholderString = "All Hail the Crimson King"
        
        if let title = char?.attribute(titleKey, at: 0, effectiveRange: nil) as? String {
            field.stringValue = title
        }
        
        vc.alert?.messageText = NSLocalizedString("Please enter image title:", comment: "Edit area")
        vc.alert?.accessoryView = field
        vc.alert?.alertStyle = .informational
        vc.alert?.addButton(withTitle: "OK")
        vc.alert?.beginSheetModal(for: window) { (returnCode: NSApplication.ModalResponse) -> Void in
            if returnCode == NSApplication.ModalResponse.alertFirstButtonReturn {
                self.textStorage?.addAttribute(titleKey, value: field.stringValue, range: range)
                
                if let note = self.note, note.container != .encryptedTextPack {
                    note.save(attributed: self.attributedString())
                }
            }
            
            
            vc.alert = nil
        }
        
        field.becomeFirstResponder()
    }

    override func viewDidChangeEffectiveAppearance() {
        UserDataService.instance.isDark = effectiveAppearance.isDark
        storage.resetCacheAttributes()

        // clear preview cache
        MPreviewView.template = nil
        let webkitPreview = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wkPreview")
        try? FileManager.default.removeItem(at: webkitPreview)

        NotesTextProcessor.hl = nil

        guard let note = self.note else { return }
        NotesTextProcessor.highlight(note: note)

        let funcName = effectiveAppearance.isDark ? "switchToDarkMode" : "switchToLightMode"
        let switchScript = "if (typeof(\(funcName)) == 'function') { \(funcName)(); }"

        downView?.evaluateJavaScript(switchScript)

        // TODO: implement code block live theme changer
        viewDelegate?.refillEditArea(force: true)
    }

    private func pasteImageFromClipboard(in note: Note) -> Bool {
        if let url = NSURL(from: NSPasteboard.general) {
            if !url.isFileURL {
                return false
            }

            return saveFile(url: url as URL, in: note)
        }

        if NSPasteboard.general.data(forType: .png) != nil ||
            NSPasteboard.general.data(forType: .tiff) != nil {

            textStorageProcessor?.shouldForceRescan = true

            var ext = "png"
            var data = NSPasteboard.general.data(forType: .png)

            if data == nil {
                data = NSPasteboard.general.data(forType: .tiff)
                ext = "jpg"
            }

            if let data = data {
                saveClipboard(data: data, note: note, ext: ext)
            }

            saveTextStorageContent(to: note)
            note.save()

            if let container = textContainer {
                textStorage?.sizeAttachmentImages(container: container)
            }

            return true
        }

        return false
    }

    private func saveFile(url: URL, in note: Note) -> Bool {
        if let data = try? Data(contentsOf: url) {
            var ext: String?

            if let _ = NSImage(data: data) {
                ext = "jpg"
                if let source = CGImageSourceCreateWithData(data as CFData, nil) {
                    let uti = CGImageSourceGetType(source)

                    if let fileExtension = (uti as String?)?.utiFileExtension {
                        ext = fileExtension
                    }
                }
            }

            textStorageProcessor?.shouldForceRescan = true

            saveClipboard(data: data, note: note, ext: ext, url: url)
            saveTextStorageContent(to: note)
            note.save()

            if let container = textContainer {
                textStorage?.sizeAttachmentImages(container: container)
            }

            return true
        }

        return false
    }

    private func saveClipboard(data: Data, note: Note, ext: String? = nil, url: URL? = nil) {
        if let path = ImagesProcessor.writeFile(data: data, url: url, note: note, ext: ext) {

            guard UserDefaultsManagement.liveImagesPreview else {
                let newLineImage = NSAttributedString(string: "![](\(path))")
                self.breakUndoCoalescing()
                self.insertText(newLineImage, replacementRange: selectedRange())
                self.breakUndoCoalescing()
                return
            }

            guard let path = path.removingPercentEncoding else { return }
            
            if let imageUrl = note.getImageUrl(imageName: path) {
                let attachment = NoteAttachment(editor: self, title: "", path: path, url: imageUrl, note: note)

                if let attributedString = attachment.getAttributedString() {
                    let newLineImage = NSMutableAttributedString(attributedString: attributedString)

                    self.breakUndoCoalescing()
                    self.insertText(newLineImage, replacementRange: selectedRange())
                    self.breakUndoCoalescing()
                    return
                }
            }
        }
    }

    public func updateTextContainerInset() {
        textContainerInset.width = getWidth()
    }

    public func getWidth() -> CGFloat {
        let lineWidth = UserDefaultsManagement.lineWidth
        let margin = UserDefaultsManagement.marginSize
        let width = frame.width

        if lineWidth == 1000 {
            return CGFloat(margin)
        }

        guard Float(width) - margin * 2 > lineWidth else {
            return CGFloat(margin)
        }

        return CGFloat((Float(width) - lineWidth) / 2)
    }

    private func deleteUnusedImages(checkRange: NSRange) {
        guard let storage = textStorage else { return }
        guard let note = self.note else { return }

        var removedImages = [URL: URL]()

        storage.enumerateAttribute(.attachment, in: checkRange) { (value, range, _) in
            if let _ = value as? NSTextAttachment, storage.attribute(.todo, at: range.location, effectiveRange: nil) == nil {

                let filePathKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.path")

                if let filePath = storage.attribute(filePathKey, at: range.location, effectiveRange: nil) as? String {

                    if let note = self.note {
                        guard let imageURL = note.getImageUrl(imageName: filePath) else { return }

                        do {
                            guard let resultingItemUrl = Storage.shared().trashItem(url: imageURL) else { return }

                            try FileManager.default.moveItem(at: imageURL, to: resultingItemUrl)

                            removedImages[resultingItemUrl] = imageURL
                        } catch {
                            print(error)
                        }
                    }
                }
            }
        }

        if removedImages.count > 0 {
            note.undoManager.registerUndo(withTarget: self, selector: #selector(unDeleteImages), object: removedImages)
        }
    }

    @objc public func unDeleteImages(_ urls: [URL: URL]) {
        for (src, dst) in urls {
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                print(error)
            }
        }
    }

    @available(OSX 10.12.2, *)
    override func makeTouchBar() -> NSTouchBar? {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            NSTouchBarItem.Identifier("Todo"),
            NSTouchBarItem.Identifier("Bold"),
            NSTouchBarItem.Identifier("Italic"),
            .fixedSpaceSmall,
            NSTouchBarItem.Identifier("Link"),
            NSTouchBarItem.Identifier("Image or file"),
            NSTouchBarItem.Identifier("CodeBlock"),
            .fixedSpaceSmall,
            NSTouchBarItem.Identifier("Indent"),
            NSTouchBarItem.Identifier("UnIndent")
        ]
        return touchBar
    }

    @available(OSX 10.12.2, *)
    override func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case NSTouchBarItem.Identifier("Todo"):
            if let im = NSImage(named: "todo"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(todo(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }
        case NSTouchBarItem.Identifier("Bold"):
            if let im = NSImage(named: "bold"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(pressBold(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }
        case NSTouchBarItem.Identifier("Italic"):
            if let im = NSImage(named: "italic"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(pressItalic(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }
        case NSTouchBarItem.Identifier("Image or file"):
            if let im = NSImage(named: "image"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(insertFileOrImage(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }

        case NSTouchBarItem.Identifier("Indent"):
            if let im = NSImage(named: "indent"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(shiftRight(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }

        case NSTouchBarItem.Identifier("UnIndent"):
            if let im = NSImage(named: "unindent"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(shiftLeft(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }
        case NSTouchBarItem.Identifier("CodeBlock"):
            if let im = NSImage(named: "codeblock"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(insertCodeBlock(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }
        case NSTouchBarItem.Identifier("Link"):
            if let im = NSImage(named: "tb_link"), im.isValid, im.size.height > 0 {
                let image = im.tint(color: NSColor.white)
                image.size = NSSize(width: 20, height: 20)
                let button = NSButton(image: image, target: self, action: #selector(insertLink(_:)))
                button.bezelColor = NSColor(red:0.21, green:0.21, blue:0.21, alpha:1.0)

                let customViewItem = NSCustomTouchBarItem(identifier: identifier)
                customViewItem.view = button
                return customViewItem
            }
        default: break
        }

        return super.touchBar(touchBar, makeItemForIdentifier: identifier)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)

        let editTitle = NSLocalizedString("Edit Link…", comment: "")
        if let editLink = menu?.item(withTitle: editTitle) {
            menu?.removeItem(editLink)
        }

        let removeTitle = NSLocalizedString("Remove Link", comment: "")
        if let removeLink = menu?.item(withTitle: removeTitle) {
            menu?.removeItem(removeLink)
        }

        return menu
    }

    /**
     Handoff methods
     */
    override func updateUserActivityState(_ userActivity: NSUserActivity) {
        guard let note = self.note else { return }

        let position =
            window?.firstResponder == self ? selectedRange().location : -1
        let state = editorViewController?.vcEditor?.preview == true ? "preview" : "editor"
        let data =
            [
                "note-file-name": note.name,
                "position": String(position),
                "state": state
            ]

        userActivity.addUserInfoEntries(from: data)
    }

    override func resignFirstResponder() -> Bool {
        userActivity?.needsSave = true

        return super.resignFirstResponder()
    }

    public func registerHandoff(note: Note) {
        self.userActivity?.invalidate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let updateDict:  [String: String] = ["note-file-name": note.name]
            let activity = NSUserActivity(activityType: "es.fsnot.handoff-open-note")
            activity.isEligibleForHandoff = true
            activity.userInfo = updateDict
            activity.title = NSLocalizedString("Open note", comment: "Document opened")
            self.userActivity = activity
            self.userActivity?.becomeCurrent()
        }
    }
    
    public func changePreviewState(_ state: Bool) {
        preview = state
    }
    
    public func togglePreviewState() {
        self.preview = !self.preview
        
        note?.previewState = self.preview
    }
    
    public func isPreviewEnabled() -> Bool {
        return preview
    }
    
    public func disablePreviewEditorAndNote() {
        preview = false
        
        note?.previewState = false
    }
}
