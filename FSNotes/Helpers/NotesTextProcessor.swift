//
//  NotesTextStorage.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 12/26/17.
//  Copyright © 2017 Oleksandr Glushchenko. All rights reserved.
//

import Highlightr

#if os(OSX)
    import Cocoa
    import MASShortcut
#else
    import UIKit
#endif

public class NotesTextProcessor {
#if os(OSX)
    typealias Color = NSColor
    typealias Image = NSImage
    typealias Font = NSFont

    public static var fontColor: NSColor {
        get {
            if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
                return NSColor(named: "mainText")!
            } else {
                return UserDefaultsManagement.fontColor
            }
        }
    }
#else
    typealias Color = UIColor
    typealias Image = UIImage
    typealias Font = UIFont

    public static var fontColor: UIColor {
        get {
            return UIColor { (traits) -> UIColor in
                return traits.userInterfaceStyle == .dark ?
                    UIColor.white :
                    UIColor.black
            }
        }
    }
#endif
    // MARK: Syntax highlight customisation
    
    /**
     Color used to highlight markdown syntax. Default value is light grey.
     */
    public static var syntaxColor = Color.lightGray
    
    public static var yamlOpenerColor = Color.systemRed
    
#if os(OSX)
    public static var font: NSFont {
        get {
            return UserDefaultsManagement.noteFont
        }
    }

    public static var codeBackground: NSColor {
        get {
            if let theme = HighlighterTheme(rawValue: UserDefaultsManagement.codeTheme) {
                return NSColor(hex: theme.backgroundHex)
            }

            return NSColor(named: "code") ?? NSColor(red:0.97, green:0.97, blue:0.97, alpha:1.0)
        }
    }

    public static var codeSpanBackground: NSColor {
        get {
            return NSColor(named: "code") ?? NSColor(red:0.97, green:0.97, blue:0.97, alpha:1.0)
        }
    }

    open var highlightColor: NSColor {
        get {
            if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
                return NSColor(named: "highlight")!
            } else {
                return NSColor(red:1.00, green:0.90, blue:0.70, alpha:1.0)
            }
        }
    }

    public static var quoteColor: NSColor {
        get {
            if UserDefaultsManagement.appearanceType != AppearanceType.Custom, #available(OSX 10.13, *) {
                return NSColor(named: "quoteColor")!
            } else {
                return NSColor.darkGray
            }
        }
    }
#else
    public static var font: UIFont {
        get {
            return UserDefaultsManagement.noteFont
        }
    }

    public static var codeBackground: UIColor {
        get {
            return UIColor.codeBackground
        }
    }

    public static var codeSpanBackground: UIColor {
        get {
            return UIColor.codeBackground
        }
    }
    
    open var highlightColor: UIColor {
        get {
            return UIColor.highlightColor
        }
    }

    public static var quoteColor: UIColor {
        get {
            return UIColor.darkGray
        }
    }
#endif
    
    /**
     Quote indentation in points. Default 20.
     */
    open var quoteIndendation : CGFloat = 20
    
    static var codeFont = UserDefaultsManagement.codeFont
    
    /**
     If the markdown syntax should be hidden or visible
     */
    public static var hideSyntax = false
    
    private var note: Note?
    private var storage: NSTextStorage?
    private var range: NSRange?
    private var width: CGFloat?
    
    init(note: Note? = nil, storage: NSTextStorage? = nil, range: NSRange? = nil) {
        self.note = note
        self.storage = storage
        self.range = range
    }

    public static func resetCaches() {
        NotesTextProcessor.hl = nil
        NotesTextProcessor.codeFont = UserDefaultsManagement.codeFont
    }

    public static func getFencedCodeBlockRange(paragraphRange: NSRange, string: NSMutableAttributedString) -> NSRange? {
        guard UserDefaultsManagement.codeBlockHighlight else { return nil }

        let regex = try! NSRegularExpression(pattern: NotesTextProcessor._codeQuoteBlockPattern, options: [
            NSRegularExpression.Options.allowCommentsAndWhitespace,
            NSRegularExpression.Options.anchorsMatchLines
            ])

        var foundRange: NSRange? = nil
        regex.enumerateMatches(
            in: string.string,
            options: NSRegularExpression.MatchingOptions(),
            range: NSRange(0..<string.length),
            using: { (result, matchingFlags, stop) -> Void in
                guard let r = result else {
                    return
                }
                
                if r.range.intersection(paragraphRange) != nil {
                    if r.range.upperBound < string.length {
                        foundRange = NSRange(location: r.range.location, length: r.range.length)
                    } else {
                        foundRange = r.range
                    }
                    
                    stop.pointee = true
                }
            }
        )
        
        return foundRange
    }

    public static func getSpanCodeBlockRange(content: NSMutableAttributedString, range: NSRange) -> NSRange? {
        var codeSpan: NSRange?
        let paragraphRange = content.mutableString.paragraphRange(for: range)
        let paragraph = content.attributedSubstring(from: paragraphRange).string

        if paragraph.contains("`") {
            NotesTextProcessor.codeSpanRegex.matches(content.string, range: paragraphRange) { (result) -> Void in
                if let spanRange = result?.range, spanRange.intersection(range) != nil {
                    codeSpan = spanRange
                }
            }
        }
        
        return codeSpan
    }

    public static var hl: Highlightr? = nil
    public static var backgroundHl: Highlightr? = nil
    
    public static func getHighlighter(backgroundThread: Bool = false) -> Highlightr? {
        if backgroundThread, let instance = self.backgroundHl {
            return instance
        } else if let instance = self.hl, !backgroundThread {
            return instance
        }

        guard let highlightr = Highlightr() else {
            return nil
        }

        highlightr.setTheme(to: UserDefaultsManagement.codeTheme)
        highlightr.theme.codeFont = UserDefaultsManagement.codeFont

        if backgroundThread {
            self.backgroundHl = highlightr
        } else {
            self.hl = highlightr
        }
        
        return highlightr
    }

    public static func highlightCode(attributedString: NSMutableAttributedString, range: NSRange, language: String? = nil, backgroundThread: Bool = false) {
        guard let highlighter = NotesTextProcessor.getHighlighter(backgroundThread: backgroundThread) else { return }

        let codeString = attributedString.mutableString.substring(with: range)
        let preDefinedLanguage = language ?? getLanguage(codeString)

        attributedString.mutableString.enumerateSubstrings(in: range, options: .byParagraphs) { string, range, _, _ in
            let rangeNewline = range.upperBound == attributedString.length ? range : NSRange(range.location..<range.upperBound + 1)
            attributedString.addAttribute(.backgroundColor, value: NotesTextProcessor.codeBackground, range: rangeNewline)
        }

        guard UserDefaultsManagement.codeBlocksWithSyntaxHighlighting, let code = highlighter.highlight(codeString, as: preDefinedLanguage) else { return }

        if (range.location + range.length) > attributedString.length { return }
        if attributedString.length >= range.upperBound && (code.string != attributedString.mutableString.substring(with: range)) { return }

        let codeFont = UserDefaultsManagement.codeFont
        let codeFontBold = codeFont.codeBold()

        code.enumerateAttributes(
            in: NSMakeRange(0, code.length),
            options: [],
            using: { (attrs, locRange, stop) in
                var fixedRange = NSMakeRange(range.location+locRange.location, locRange.length)
                fixedRange.length = (fixedRange.location + fixedRange.length < attributedString.length) ? fixedRange.length : attributedString.length-fixedRange.location
                fixedRange.length = (fixedRange.length >= 0) ? fixedRange.length : 0

                for (key, value) in attrs {
                    if key == NSAttributedString.Key.font, let font = value as? Font {
                        if font.isBold {
                            attributedString.addAttribute(key, value: codeFontBold, range: fixedRange)
                        } else {
                            attributedString.addAttribute(key, value: codeFont, range: fixedRange)
                        }

                        attributedString.fixAttributes(in: fixedRange)
                    } else {
                        attributedString.addAttribute(key, value: value, range: fixedRange)
                    }
                }
            }
        )
    }

    fileprivate static var quoteIndendationStyle : NSParagraphStyle {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)
        return paragraphStyle
    }
    
    public static var languages: [String]? = nil
    
    public static func getLanguage(_ code: String) -> String? {
        if code.starts(with: "```") {
            let start = code.index(code.startIndex, offsetBy: 0)
            let end = code.index(code.startIndex, offsetBy: 3)
            let range = start..<end

            let paragraphRange = code.paragraphRange(for: range)
            let detectedLang =
                code[paragraphRange]
                    .replacingOccurrences(of: "```", with: "")
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

            self.languages = self.getHighlighter()?.supportedLanguages()

            if let lang = self.languages, lang.contains(detectedLang) {
                return detectedLang
            }
        }
        
        return nil
    }
    
    
    /**
     Coverts App links:`[[Link Title]]` to Markdown: `[Link](fsnotes://find/link%20title)`
     
     - parameter content:      A string containing CommonMark Markdown
     
     - returns: Content string with converted links
     */

    public static func convertAppLinks(in content: NSMutableAttributedString) -> NSMutableAttributedString {
        let attributedString = content.mutableCopy() as! NSMutableAttributedString
        let range = NSRange(0..<content.string.utf16.count)
        let tagQuery = "fsnotes://find?id="

        NotesTextProcessor.appUrlRegex.matches(content.string, range: range, completion: { (result) -> (Void) in
            guard let innerRange = result?.range else { return }

            var substring = attributedString.mutableString.substring(with: innerRange)
            substring = substring
                .replacingOccurrences(of: "[[", with: "")
                .replacingOccurrences(of: "]]", with: "")
                .trim()

            guard let tag = substring.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return }

            attributedString.addAttribute(.link, value: "\(tagQuery)\(tag)", range: innerRange)
        })

        attributedString.enumerateAttribute(.link, in: range) { (value, range, _) in
            if let value = value as? String, value.starts(with: tagQuery) {
                if let tag = value
                    .replacingOccurrences(of: tagQuery, with: "")
                    .removingPercentEncoding
                {

                    if NotesTextProcessor.getSpanCodeBlockRange(content: attributedString, range: range) != nil {
                        return
                    }

                    if NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: range, string: attributedString) != nil {
                        return
                    }

                    let link = "[\(tag)](\(value))"
                    attributedString.replaceCharacters(in: range, with: link)
                }
            }
        }
        
        return attributedString
    }

    public static func convertAppTags(in content: NSMutableAttributedString) -> NSMutableAttributedString {
        let attributedString = content.mutableCopy() as! NSMutableAttributedString
        guard UserDefaultsManagement.inlineTags else { return attributedString}

        let range = NSRange(0..<content.string.utf16.count)
        let tagQuery = "fsnotes://open/?tag="

        FSParser.tagsInlineRegex.matches(content.string, range: range) { (result) -> Void in
            guard var range = result?.range(at: 1) else { return }

            var substring = attributedString.mutableString.substring(with: range)
            guard !substring.isNumber else { return }

            range = NSRange(location: range.location - 1, length: range.length + 1)
            substring = attributedString.mutableString.substring(with: range)
                .replacingOccurrences(of: "#", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .trim()

            guard let tag = substring.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

            attributedString.addAttribute(.link, value: "\(tagQuery)\(tag)", range: range)
        }

        attributedString.enumerateAttribute(.link, in: range) { (value, range, _) in
            if let value = value as? String, value.starts(with: tagQuery) {
                if let tag = value
                    .replacingOccurrences(of: tagQuery, with: "")
                    .removingPercentEncoding
                {

                    if NotesTextProcessor.getSpanCodeBlockRange(content: attributedString, range: range) != nil {
                        return
                    }

                    if NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: range, string: attributedString) != nil {
                        return
                    }

                    let link = "[#\(tag)](\(value))"
                    attributedString.replaceCharacters(in: range, with: link)
                }
            }
        }

        return attributedString
    }

    public static func highlight(note: Note) {
        highlightMarkdown(attributedString: note.content, note: note)
        highlightFencedAndIndentCodeBlocks(attributedString: note.content)
    }

    public static func highlightFencedAndIndentCodeBlocks(attributedString: NSMutableAttributedString, backgroundThread: Bool = false) {
        let range = NSRange(0..<attributedString.length)

        if UserDefaultsManagement.codeBlockHighlight {
            var fencedRanges = [NSRange]()

            // Fenced code block
            let regexFencedCodeBlock = try! NSRegularExpression(pattern: self._codeQuoteBlockPattern, options: [
                .allowCommentsAndWhitespace,
                .anchorsMatchLines
            ])

            regexFencedCodeBlock.enumerateMatches(
                in: attributedString.string,
                options: NSRegularExpression.MatchingOptions(),
                range: range,
                using: { (result, matchingFlags, stop) -> Void in
                    guard let r = result else { return }
                    fencedRanges.append(r.range(at: 2))

                    let fullCode = attributedString.mutableString.substring(with: r.range)
                    let preDefinedLanguage = getLanguage(fullCode)

                    // If no code highlight empty line
                    if r.range(at: 2).length == 0 {
                        attributedString.addAttribute(.backgroundColor, value: NotesTextProcessor.codeBackground, range: r.range)
                    }

                    NotesTextProcessor.highlightCode(attributedString: attributedString, range: r.range(at: 2), language: preDefinedLanguage, backgroundThread: backgroundThread)
                    NotesTextProcessor.highlightFencedBackTick(range: r.range, attributedString: attributedString)
            })

            // Indent code blocks
            if UserDefaultsManagement.indentedCodeBlockHighlighting {
                let codeTextProcessor = CodeTextProcessor(textStorage: attributedString)
                if let codeBlockRanges = codeTextProcessor.getCodeBlockRanges() {
                    for range in codeBlockRanges {

                        if isIntersect(fencedRanges: fencedRanges, indentRange: range) {
                            continue
                        }

                        NotesTextProcessor.highlightCode(attributedString: attributedString, range: range)
                    }
                }
            }
        }
    }

    public static func highlightFencedBackTick(range: NSRange, attributedString: NSMutableAttributedString, language: String? = nil) {

        let code = attributedString.mutableString.substring(with: range)
        let langLength = (code.components(separatedBy: "\n").first?.count ?? 3) - 3
        let length = langLength + 3

        // Open range background
        let openRangeBackground = NSRange(location: range.location, length: length + 1)
        attributedString.addAttribute(.backgroundColor, value: NotesTextProcessor.codeBackground, range: openRangeBackground)

        // Open range font and foreground
        let openRange = NSRange(location: range.location, length: length + 1)
        attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: openRange)
        attributedString.addAttribute(.font, value: NotesTextProcessor.codeFont, range: openRange)

        // Close range foreground
        let closeRange = NSRange(location: range.upperBound - 4, length: 4)
        attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: closeRange)

        // Colorize last new line
        let lastParRange = attributedString.mutableString.paragraphRange(for: NSRange(location: range.location + range.length - 1, length: 0))
        attributedString.addAttribute(.backgroundColor, value: NotesTextProcessor.codeBackground, range: lastParRange)
        attributedString.addAttribute(.font, value: NotesTextProcessor.codeFont, range: lastParRange)

        // Colorize center
        let centerRange = NSRange(openRangeBackground.location..<lastParRange.upperBound)
        attributedString.addAttribute(.backgroundColor, value: NotesTextProcessor.codeBackground, range: centerRange)

        // Colorize language name
        if let langLength = NotesTextProcessor.getLanguage(code)?.count {
            let  color = Color.init(red: 0.18, green: 0.61, blue: 0.25, alpha: 1.00)
            let range = NSRange(location: range.location + 3, length: langLength)
            attributedString.addAttribute(.foregroundColor, value: color, range: range)
        }
    }

    public static func isIntersect(fencedRanges: [NSRange], indentRange: NSRange) -> Bool {
        for fencedRange in fencedRanges {
            if fencedRange.intersection(indentRange) != nil {
                return true
            }
        }

        return false
    }

    public static func minimalHighlight(attributedString: NSMutableAttributedString, paragraphRange: NSRange? = nil, note: Note) {
         let paragraphRange = paragraphRange ?? NSRange(0..<attributedString.length)

        attributedString.addAttribute(.font, value: font, range: paragraphRange)
        attributedString.fixAttributes(in: paragraphRange)

        #if os(iOS)
        attributedString.addAttribute(.foregroundColor, value: UIColor.blackWhite, range: paragraphRange)
        #else
            attributedString.addAttribute(.foregroundColor, value: fontColor, range: paragraphRange)
            attributedString.enumerateAttribute(.foregroundColor, in: paragraphRange,  options: []) { (value, range, stop) -> Void in

                if (value as? NSColor) != nil {
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range)
                }
            }
        #endif
    }

    public static func highlightMarkdown(attributedString: NSMutableAttributedString, paragraphRange: NSRange? = nil, note: Note) {
        let paragraphRange = paragraphRange ?? NSRange(0..<attributedString.length)
        let isFullScan = attributedString.length == paragraphRange.upperBound && paragraphRange.lowerBound == 0
        let string = attributedString.string
        
        let codeFont = UserDefaultsManagement.noteFont
        let quoteFont = UserDefaultsManagement.noteFont
        
    #if os(OSX)
        let boldFont = NSFont.boldFont()
        let italicFont = NSFont.italicFont()
        let hiddenFont = NSFont.systemFont(ofSize: 0.1)
    #else
        var boldFont: UIFont {
            get {
                return UserDefaultsManagement.noteFont.bold()
            }
        }
        
        var italicFont: UIFont {
            get {
                return UserDefaultsManagement.noteFont.italic()
            }
        }
        
        let hiddenFont = UIFont.systemFont(ofSize: 0.1)
    #endif

        let hiddenColor = Color.clear
        let hiddenAttributes: [NSAttributedString.Key : Any] = [
            .font : hiddenFont,
            .foregroundColor : hiddenColor
        ]
        
        func hideSyntaxIfNecessary(range: @autoclosure () -> NSRange) {
            guard NotesTextProcessor.hideSyntax else { return }
            
            attributedString.addAttributes(hiddenAttributes, range: range())
        }

        attributedString.enumerateAttribute(.link, in: paragraphRange,  options: []) { (value, range, stop) -> Void in
            if value != nil && attributedString.attribute(.attachment, at: range.location, effectiveRange: nil) == nil {
                attributedString.removeAttribute(.link, range: range)
            }
        }

        attributedString.enumerateAttribute(.strikethroughStyle, in: paragraphRange,  options: []) { (value, range, stop) -> Void in
            if value != nil {
                attributedString.removeAttribute(.strikethroughStyle, range: range)
            }
        }

        attributedString.enumerateAttribute(.tag, in: paragraphRange,  options: []) { (value, range, stop) -> Void in
            if value != nil {
                attributedString.removeAttribute(.tag, range: range)
            }
        }

        attributedString.addAttribute(.font, value: font, range: paragraphRange)
        attributedString.fixAttributes(in: paragraphRange)

        #if os(iOS)
            attributedString.addAttribute(.foregroundColor, value: UIColor.blackWhite, range: paragraphRange)
        #else
            attributedString.addAttribute(.foregroundColor, value: fontColor, range: paragraphRange)
            attributedString.enumerateAttribute(.foregroundColor, in: paragraphRange,  options: []) { (value, range, stop) -> Void in

                if (value as? NSColor) != nil {
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range)
                }
            }
        #endif

        // We detect and process inline links not formatted
        
        if  UserDefaultsManagement.clickableLinks {
            NotesTextProcessor.autolinkRegex.matches(string, range: paragraphRange) { (result) -> Void in
                guard var range = result?.range else { return }
                var substring = attributedString.mutableString.substring(with: range)
                
                guard substring.lengthOfBytes(using: .utf8) > 0 else { return }
                
                if ["!", "?", ";", ":", ".", ",", "_"].contains(substring.last) {
                    range = NSRange(location: range.location, length: range.length - 1)
                    substring = String(substring.dropLast())
                }
                
                if substring.first == "(" {
                    range = NSRange(location: range.location + 1, length: range.length - 1)
                }
                
                if substring.last == ")" {
                    range = NSRange(location: range.location, length: range.length - 1)
                }
                
                if let url = URL(string: substring) {
                    attributedString.addAttribute(.link, value: url, range: range)
                } else if let substring = String(substring).addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) {
                    attributedString.addAttribute(.link, value: substring, range: range)
                }
                
                if NotesTextProcessor.hideSyntax {
                    NotesTextProcessor.autolinkPrefixRegex.matches(string, range: range) { (innerResult) -> Void in
                        guard let innerRange = innerResult?.range else { return }
                        attributedString.addAttribute(.font, value: hiddenFont, range: innerRange)
                        attributedString.fixAttributes(in: innerRange)
                        attributedString.addAttribute(.foregroundColor, value: hiddenColor, range: innerRange)
                    }
                }
            }
        }
        
        FSParser.yamlBlockRegex.matches(string, range: NSRange(location: 0, length: attributedString.length)) { (result) -> Void in
            guard let range = result?.range(at: 1) else { return }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.fontColor, range: range)

            if range.location == 0 {
                let listOpeningRegex = MarklightRegex(pattern: "([a-zA-Z_]+):", options: [.allowCommentsAndWhitespace])
                listOpeningRegex.matches(string, range: range) { (result) -> Void in
                    guard let range = result?.range(at: 0) else { return }
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.yamlOpenerColor, range: range)
                }
                
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.yamlOpenerColor, range: NSRange(location: 0, length: 3))
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.yamlOpenerColor, range: NSRange(location: range.length - 3, length: 3))
                
                attributedString.addAttribute(NSAttributedString.Key.yamlBlock, value: range, range: range)
            }
        }
        
        // We detect and process underlined headers
        NotesTextProcessor.headersSetextRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: boldFont, range: range)
            attributedString.fixAttributes(in: range)

            NotesTextProcessor.headersSetextUnderlineRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: NSMakeRange(innerRange.location, innerRange.length))
            }
        }
        
        // We detect and process dashed headers
        NotesTextProcessor.headersAtxRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: boldFont, range: range)
            attributedString.fixAttributes(in: range)

            NotesTextProcessor.headersAtxOpeningRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                let syntaxRange = NSMakeRange(innerRange.location, innerRange.length + 1)
                hideSyntaxIfNecessary(range: syntaxRange)
            }

            NotesTextProcessor.headersAtxClosingRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }
        
        // We detect and process reference links
        NotesTextProcessor.referenceLinkRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: range)
        }
        
        // We detect and process lists
        NotesTextProcessor.listRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            NotesTextProcessor.listOpeningRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }

        // We detect and process anchors (links)
        NotesTextProcessor.anchorRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: codeFont, range: range)
            attributedString.fixAttributes(in: range)
            NotesTextProcessor.openingSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.closingSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.parenRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                let initialSyntaxRange = NSMakeRange(innerRange.location, 1)
                let finalSyntaxRange = NSMakeRange(innerRange.location + innerRange.length - 1, 1)
                hideSyntaxIfNecessary(range: initialSyntaxRange)
                hideSyntaxIfNecessary(range: finalSyntaxRange)
            }
        }

        #if IOS_APP || os(OSX)
        // We detect and process inline anchors (links)
        NotesTextProcessor.anchorInlineRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: codeFont, range: range)
            attributedString.fixAttributes(in: range)
            
            var destinationLink : String?
            
            NotesTextProcessor.coupleRoundRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                
                guard let linkRange = result?.range(at: 3), linkRange.length > 0 else { return }

                var substring = attributedString.mutableString.substring(with: linkRange)

                guard substring.count > 0 else { return }

                if substring.starts(with: "/i/")
                    || substring.starts(with: "i/")
                    || substring.starts(with: "/files/")
                    || substring.starts(with: "files/"),
                    let path = note.project.url.appendingPathComponent(substring).path.removingPercentEncoding
                {
                    substring = "file://" + path
                } else if note.isTextBundle() && substring.starts(with: "assets/"), let path = note.getURL().appendingPathComponent(substring).path.removingPercentEncoding {
                    substring = "file://" + path
                }
                
                destinationLink = substring
                attributedString.addAttribute(.link, value: substring, range: linkRange)

                hideSyntaxIfNecessary(range: innerRange)
            }
            
            NotesTextProcessor.openingSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
            
            NotesTextProcessor.closingSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
            
            guard let destinationLinkString = destinationLink else { return }
            
            NotesTextProcessor.coupleSquareRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                var _range = innerRange
                _range.location = _range.location + 1
                _range.length = _range.length - 2
                
                let substring = attributedString.mutableString.substring(with: _range)
                guard substring.lengthOfBytes(using: .utf8) > 0 else { return }
                
                attributedString.addAttribute(.link, value: destinationLinkString, range: _range)
            }
        }
        #endif

        NotesTextProcessor.imageRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: codeFont, range: range)
            attributedString.fixAttributes(in: range)

            // TODO: add image attachment
            if NotesTextProcessor.hideSyntax {
                attributedString.addAttribute(.font, value: hiddenFont, range: range)
            }
            NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: paragraphRange) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.imageClosingSquareRegex.matches(string, range: paragraphRange) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }

        // We detect and process app urls [[link]]
        NotesTextProcessor.appUrlRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let innerRange = result?.range else { return }
            var _range = innerRange
            _range.location = _range.location + 2
            _range.length = _range.length - 4
            
            let appLink = attributedString.mutableString.substring(with: _range)
            guard !appLink.startsWith(string: "`") else { return }

            if let link = appLink.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {

            #if os(iOS)
                attributedString.addAttribute(.foregroundColor, value: UIColor.wikiColor, range: innerRange)
            #endif

                attributedString.addAttribute(.link, value: "fsnotes://find?id=" + link, range: _range)

                if let range = result?.range(at: 0) {
                    attributedString.addAttribute(.foregroundColor, value: Color.gray, range: range)
                }

                if let range = result?.range(at: 2) {
                    attributedString.addAttribute(.foregroundColor, value: Color.gray, range: range)
                }
            }
        }
        
        // We detect and process quotes
        NotesTextProcessor.blockQuoteRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            attributedString.addAttribute(.font, value: quoteFont, range: range)
            attributedString.fixAttributes(in: range)
            attributedString.addAttribute(.foregroundColor, value: quoteColor, range: range)
            NotesTextProcessor.blockQuoteOpeningRegex.matches(string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                hideSyntaxIfNecessary(range: innerRange)
            }
        }
                
        // We detect and process italics
        NotesTextProcessor.strictItalicRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range(at: 3) else { return }

            if NotesTextProcessor.isLink(attributedString: attributedString, range: range) {
                return
            }

            attributedString.addAttribute(.font, value: italicFont, range: range)

            NotesTextProcessor.strictBoldRegex.matches(string, range: range) { (result) -> Void in
                guard let range = result?.range else { return }
                let boldItalic = Font.addBold(font: italicFont)
                attributedString.addAttribute(.font, value: boldItalic, range: range)
            }

            attributedString.fixAttributes(in: range)
            
            let preRange = NSMakeRange(range.location - 1, 1)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: preRange)
            hideSyntaxIfNecessary(range: preRange)
            
            let postRange = NSMakeRange(range.location + range.length, 1)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: postRange)
            hideSyntaxIfNecessary(range: postRange)
        }
        
        // We detect and process bolds
        NotesTextProcessor.strictBoldRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range(at: 3) else { return }

            let boldString = attributedString.attributedSubstring(from: range)
            if boldString.string.contains("__") || boldString.string == "_" {
                return
            }

            if NotesTextProcessor.isLink(attributedString: attributedString, range: range) {
                return
            }

            if let font = boldString.attribute(.font, at: 0, effectiveRange: nil) as? Font, font.isItalic {
            } else {
                attributedString.addAttribute(.font, value: boldFont, range: range)

                NotesTextProcessor.italicRegex.matches(string, range: range) { (result) -> Void in
                    guard let range = result?.range else { return }
                    let boldItalic = Font.addItalic(font: boldFont)
                    attributedString.addAttribute(.font, value: boldItalic, range: range)
                }
            }

            attributedString.fixAttributes(in: range)

            let preRange = NSMakeRange(range.location - 2, 2)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: preRange)
            hideSyntaxIfNecessary(range: preRange)
            
            let postRange = NSMakeRange(range.location + range.length, 2)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: postRange)
            hideSyntaxIfNecessary(range: postRange)
        }

        // We detect and process bolds
        NotesTextProcessor.strikeRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }

            attributedString.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: range.location + 2, length: range.length - 4))

            attributedString.fixAttributes(in: range)

            let preRange = NSMakeRange(range.location, 2)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: preRange)
            hideSyntaxIfNecessary(range: preRange)

            let postRange = NSMakeRange(range.location + range.length - 2, 2)
            attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: postRange)
            hideSyntaxIfNecessary(range: postRange)
        }
        
        // We detect and process inline mailto links not formatted
        
        if UserDefaultsManagement.clickableLinks {
            NotesTextProcessor.autolinkEmailRegex.matches(string, range: paragraphRange) { (result) -> Void in
                guard let range = result?.range else { return }
                let substring = attributedString.mutableString.substring(with: range)
                guard substring.lengthOfBytes(using: .utf8) > 0, URL(string: substring) != nil else { return }
                
                if substring.isValidEmail() {
                    attributedString.addAttribute(.link, value: "mailto:\(substring)", range: range)
                } else {
                    attributedString.addAttribute(.link, value: substring, range: range)
                }
                
                if NotesTextProcessor.hideSyntax {
                    NotesTextProcessor.mailtoRegex.matches(string, range: range) { (innerResult) -> Void in
                        guard let innerRange = innerResult?.range else { return }
                        attributedString.addAttribute(.font, value: hiddenFont, range: innerRange)
                        attributedString.addAttribute(.foregroundColor, value: hiddenColor, range: innerRange)
                    }
                }
            }
        }

        // Todo
        NotesTextProcessor.todoInlineRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard let range = result?.range else { return }
            let substring = attributedString.mutableString.substring(with: range)

            if substring.contains("- [x]") {
                let strikeRange = attributedString.mutableString.paragraphRange(for: range)
                attributedString.addAttribute(.strikethroughStyle, value: 1, range: strikeRange)
            }
        }

        // Inline tags
        if UserDefaultsManagement.inlineTags {
            FSParser.tagsInlineRegex.matches(string, range: paragraphRange) { (result) -> Void in
                guard var range = result?.range(at: 1) else { return }

                // Skip if indented code block
                let parRange = attributedString.mutableString.paragraphRange(for: range)
                let parString = attributedString.mutableString.substring(with: parRange)
                if parString.starts(with: "    ") || parString.starts(with: "\t") {
                    return
                }

                if NotesTextProcessor.getSpanCodeBlockRange(content: attributedString, range: range) != nil {
                    return
                }

                if NotesTextProcessor.getFencedCodeBlockRange(paragraphRange: range, string: attributedString) != nil {
                    return
                }

                var substring = attributedString.mutableString.substring(with: range)
                guard !substring.isNumber && !substring.isHexColor() else { return }

                range = NSRange(location: range.location - 1, length: range.length + 1)
                substring = attributedString.mutableString.substring(with: range)
                    .replacingOccurrences(of: "#", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .trim()

                guard let tag = substring.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return }

                attributedString.addAttribute(.link, value: "fsnotes://open/?tag=\(tag)", range: range)
                attributedString.addAttribute(.tag, value: "\(tag)", range: range)
            }
        }

        if !UserDefaultsManagement.liveImagesPreview {
            
            // We detect and process inline images
            FSParser.imageInlineRegex.matches(string, range: paragraphRange) { (result) -> Void in
                guard let range = result?.range else { return }

                if let linkRange = result?.range(at: 3) {
                    let link = attributedString.mutableString.substring(with: linkRange).removingPercentEncoding

                    if let link = link, let url = note.getImageUrl(imageName: link) {
                        attributedString.addAttribute(.link, value: url, range: linkRange)
                    }
                }

                attributedString.addAttribute(.font, value: codeFont, range: range)
                NotesTextProcessor.imageOpeningSquareRegex.matches(string, range: paragraphRange) { (innerResult) -> Void in
                    guard let innerRange = innerResult?.range else { return }
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                }
                NotesTextProcessor.imageClosingSquareRegex.matches(string, range: paragraphRange) { (innerResult) -> Void in
                    guard let innerRange = innerResult?.range else { return }
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                }
                NotesTextProcessor.parenRegex.matches(string, range: range) { (innerResult) -> Void in
                    guard let innerRange = innerResult?.range else { return }
                    attributedString.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
                }
            }
        }

        attributedString.enumerateAttribute(.attachment, in: paragraphRange,  options: []) { (value, range, stop) -> Void in
            if value != nil, let todo = attributedString.attribute(.todo, at: range.location, effectiveRange: nil) {

                let strikeRange = attributedString.mutableString.paragraphRange(for: range)
                attributedString.addAttribute(.strikethroughStyle, value: todo, range: strikeRange)
            }
        }

        if isFullScan {
            checkBackTick(styleApplier: attributedString)
        }
    }

    public static func checkBackTick(styleApplier: NSMutableAttributedString, paragraphRange: NSRange? = nil) {
        guard UserDefaultsManagement.codeBlockHighlight else { return }

        var range = NSRange(0..<styleApplier.length)

        if let parRange = paragraphRange {
            range = parRange
        }

        styleApplier.enumerateAttribute(.backgroundColor, in: range) { (value, innerRange, _) in
            if value != nil {
                let font = UserDefaultsManagement.noteFont
                styleApplier.removeAttribute(.backgroundColor, range: innerRange)
                styleApplier.addAttribute(.font, value: font, range: innerRange)
                styleApplier.fixAttributes(in: innerRange)
            }
        }

        let codeFont = NotesTextProcessor.codeFont
        NotesTextProcessor.codeSpanRegex.matches(styleApplier.string, range: range) { (result) -> Void in
            guard let range = result?.range else { return }

            if styleApplier.mutableString.substring(with: range).startsWith(string: "```") {
                return
            }

            styleApplier.addAttribute(.font, value: codeFont, range: range)
            styleApplier.fixAttributes(in: range)

            styleApplier.addAttribute(.backgroundColor, value: NotesTextProcessor.codeSpanBackground, range: range)

            NotesTextProcessor.codeSpanOpeningRegex.matches(styleApplier.string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
            NotesTextProcessor.codeSpanClosingRegex.matches(styleApplier.string, range: range) { (innerResult) -> Void in
                guard let innerRange = innerResult?.range else { return }
                styleApplier.addAttribute(.foregroundColor, value: NotesTextProcessor.syntaxColor, range: innerRange)
            }
        }
    }

    public static func isLink(attributedString: NSAttributedString, range: NSRange) -> Bool {
        return attributedString.attributedSubstring(from: range).attribute(.link, at: 0, effectiveRange: nil) != nil
    }
    
    /// Tabs are automatically converted to spaces as part of the transform
    /// this constant determines how "wide" those tabs become in spaces
    public static let _tabWidth = 4
    
    // MARK: Headers
    
    /*
     Head
     ======
     
     Subhead
     -------
     */
    
    fileprivate static let headerSetextPattern = [
        "^(.+?)",
        "\\p{Z}*",
        "\\n",
        "(==+)",  // $1 = string of ='s or -'s
        "\\p{Z}*",
        "\\n|\\Z"
        ].joined(separator: "\n")
    
    public static let headersSetextRegex = MarklightRegex(pattern: headerSetextPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    fileprivate static let setextUnderlinePattern = [
        "(==+|--+)     # $1 = string of ='s or -'s",
        "\\p{Z}*$"
        ].joined(separator: "\n")
    
    public static let headersSetextUnderlineRegex = MarklightRegex(pattern: setextUnderlinePattern, options: [.allowCommentsAndWhitespace])
    
    /*
     # Head
     
     ## Subhead ##
     */
    
    fileprivate static let headerAtxPattern = [
        "^(\\#{1,6}\\  )  # $1 = string of #'s",
        "\\p{Z}*",
        "(.+?)        # $2 = Header text",
        "\\p{Z}*",
        "\\#*         # optional closing #'s (not counted)",
        "(?:\\n|\\Z)"
        ].joined(separator: "\n")
    
    public static let headersAtxRegex = MarklightRegex(pattern: headerAtxPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    fileprivate static let headersAtxOpeningPattern = [
        "^(\\#{1,6}\\ )"
        ].joined(separator: "\n")
    
    public static let headersAtxOpeningRegex = MarklightRegex(pattern: headersAtxOpeningPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    fileprivate static let headersAtxClosingPattern = [
        "\\#{1,6}\\ \\n+"
        ].joined(separator: "\n")
    
    public static let headersAtxClosingRegex = MarklightRegex(pattern: headersAtxClosingPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    // MARK: Reference links
    
    /*
     TODO: we don't know how reference links are formed
     */
    
    fileprivate static let referenceLinkPattern = [
        "^\\p{Z}{0,\(_tabWidth - 1)}\\[([^\\[\\]]+)\\]:  # id = $1",
        "  \\p{Z}*",
        "  \\n?                   # maybe *one* newline",
        "  \\p{Z}*",
        "<?(\\S+?)>?              # url = $2",
        "  \\p{Z}*",
        "  \\n?                   # maybe one newline",
        "  \\p{Z}*",
        "(?:",
        "    (?<=\\s)             # lookbehind for whitespace",
        "    [\"(]",
        "    (.+?)                # title = $3",
        "    [\")]",
        "    \\p{Z}*",
        ")?                       # title is optional",
        "(?:\\n|\\Z)"
        ].joined(separator: "")
    
    public static let referenceLinkRegex = MarklightRegex(pattern: referenceLinkPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    // MARK: Lists
    
    /*
     * First element
     * Second element
     */
    
    fileprivate static let _markerUL = "[*+-]"
    fileprivate static let _markerOL = "[0-9-]+[.]"

    fileprivate static let _listMarker = "(?:\\p{Z}|\\t)*(?:\(_markerUL)|\(_markerOL))"
    fileprivate static let _listSingleLinePattern = "^(?:\\p{Z}|\\t)*((?:[*+-]|\\d+[.]))\\p{Z}+"

    public static let listRegex = MarklightRegex(pattern: _listSingleLinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    public static let listOpeningRegex = MarklightRegex(pattern: _listMarker, options: [.allowCommentsAndWhitespace])

    // MARK: Anchors
    
    /*
     [Title](http://example.com)
     */
    
    fileprivate static let anchorPattern = [
        "(                                  # wrap whole match in $1",
        "    \\[",
        "        (\(NotesTextProcessor.getNestedBracketsPattern()))  # link text = $2",
        "    \\]",
        "",
        "    \\p{Z}?                        # one optional space",
        "    (?:\\n\\p{Z}*)?                # one optional newline followed by spaces",
        "",
        "    \\[",
        "        (.*?)                      # id = $3",
        "    \\]",
        ")"
        ].joined(separator: "\n")
    
    public static let anchorRegex = MarklightRegex(pattern: anchorPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let opneningSquarePattern = [
        "(\\[)"
        ].joined(separator: "\n")
    
    public static let openingSquareRegex = MarklightRegex(pattern: opneningSquarePattern, options: [.allowCommentsAndWhitespace])
    
    fileprivate static let closingSquarePattern = [
        "\\]"
        ].joined(separator: "\n")
    
    public static let closingSquareRegex = MarklightRegex(pattern: closingSquarePattern, options: [.allowCommentsAndWhitespace])
    
    fileprivate static let coupleSquarePattern = [
        "\\[(.*?)\\]"
        ].joined(separator: "\n")
    
    public static let coupleSquareRegex = MarklightRegex(pattern: coupleSquarePattern, options: [])
    
    fileprivate static let coupleRoundPattern = [
        ".*(?:\\])\\((.+)\\)"
        ].joined(separator: "\n")
    
    public static let coupleRoundRegex = MarklightRegex(pattern: coupleRoundPattern, options: [])
    
    fileprivate static let parenPattern = [
        "(",
        "\\(                 # literal paren",
        "      \\p{Z}*",
        "      (\(NotesTextProcessor.getNestedParensPattern()))    # href = $3",
        "      \\p{Z}*",
        "      (               # $4",
        "      (['\"])         # quote char = $5",
        "      (.*?)           # title = $6",
        "      \\5             # matching quote",
        "      \\p{Z}*",
        "      )?              # title is optional",
        "  \\)",
        ")"
        ].joined(separator: "\n")
    
    public static let parenRegex = MarklightRegex(pattern: parenPattern, options: [.allowCommentsAndWhitespace])
    
    fileprivate static let anchorInlinePattern = [
        "(                           # wrap whole match in $1",
        "    \\[",
        "        (\(NotesTextProcessor.getNestedBracketsPattern()))   # link text = $2",
        "    \\]",
        "    \\(                     # literal paren",
        "        \\p{Z}*",
        "        (\(NotesTextProcessor.getNestedParensPattern()))   # href = $3",
        "        \\p{Z}*",
        "        (                   # $4",
        "        (['\"])           # quote char = $5",
        "        (.*?)               # title = $6",
        "        \\5                 # matching quote",
        "        \\p{Z}*                # ignore any spaces between closing quote and )",
        "        )?                  # title is optional",
        "    \\)",
        ")"
        ].joined(separator: "\n")
    
    public static let anchorInlineRegex = MarklightRegex(pattern: anchorInlinePattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    // Mark: Images
    
    /*
     ![Title](http://example.com/image.png)
     */
    
    fileprivate static let imagePattern = [
        "(               # wrap whole match in $1",
        "!\\[",
        "    (.*?)       # alt text = $2",
        "\\]",
        "",
        "\\p{Z}?            # one optional space",
        "(?:\\n\\p{Z}*)?    # one optional newline followed by spaces",
        "",
        "\\[",
        "    (.*?)       # id = $3",
        "\\]",
        "",
        ")"
        ].joined(separator: "\n")
    
    public static let imageRegex = MarklightRegex(pattern: imagePattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let imageOpeningSquarePattern = [
        "(!\\[)"
        ].joined(separator: "\n")
    
    public static let imageOpeningSquareRegex = MarklightRegex(pattern: imageOpeningSquarePattern, options: [.allowCommentsAndWhitespace])
    
    fileprivate static let imageClosingSquarePattern = [
        "(\\])"
        ].joined(separator: "\n")
    
    public static let imageClosingSquareRegex = MarklightRegex(pattern: imageClosingSquarePattern, options: [.allowCommentsAndWhitespace])

    fileprivate static let todoInlinePattern = "(^(-\\ \\[(?:\\ |x)\\])\\ )"
    
    public static let todoInlineRegex = MarklightRegex(pattern: todoInlinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let allTodoInlinePattern = "((-\\ \\[(?:\\ |x)\\])\\ )"

    public static let allTodoInlineRegex = MarklightRegex(pattern: allTodoInlinePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    // MARK: Code
    
    /*
     ```
     Code
     ```
     
     Code
     */
    public static let _codeQuoteBlockPattern = [
        "(?<=\\n|\\A)",
        "(^```[\\S\\ \\(\\)]*\\n([\\s\\S]*?)\\n```(?:\\n|\\Z))"
        ].joined(separator: "\n")
            
    fileprivate static let codeSpanPattern = [
        "(?<![\\\\`])   # Character before opening ` can't be a backslash or backtick",
        "(`+)           # $1 = Opening run of `",
        "(?!`)          # and no more backticks -- match the full run",
        "(.+?)          # $2 = The code block",
        "(?<!`)",
        "\\1",
        "(?!`)"
        ].joined(separator: "\n")
    
    public static let codeSpanRegex = MarklightRegex(pattern: codeSpanPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let codeSpanOpeningPattern = [
        "(?<![\\\\`])   # Character before opening ` can't be a backslash or backtick",
        "(`+)           # $1 = Opening run of `"
        ].joined(separator: "\n")
    
    public static let codeSpanOpeningRegex = MarklightRegex(pattern: codeSpanOpeningPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let codeSpanClosingPattern = [
        "(?<![\\\\`])   # Character before opening ` can't be a backslash or backtick",
        "(`+)           # $1 = Opening run of `"
        ].joined(separator: "\n")
    
    public static let codeSpanClosingRegex = MarklightRegex(pattern: codeSpanClosingPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    // MARK: Block quotes
    
    /*
     > Quoted text
     */
    
    fileprivate static let blockQuotePattern = [
        "(                           # Wrap whole match in $1",
        "    (",
        "    ^\\p{Z}*>\\p{Z}?              # '>' at the start of a line",
        "        .+(?:\\n|\\Z)               # rest of the first line",
        "    (.+(?:\\n|\\Z))*                # subsequent consecutive lines",
        "    (?:\\n|\\Z)*                    # blanks",
        "    )+",
        ")"
        ].joined(separator: "\n")
    
    public static let blockQuoteRegex = MarklightRegex(pattern: blockQuotePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    fileprivate static let blockQuoteOpeningPattern = [
        "(^\\p{Z}*>\\p{Z})"
        ].joined(separator: "\n")
    
    public static let blockQuoteOpeningRegex = MarklightRegex(pattern: blockQuoteOpeningPattern, options: [.anchorsMatchLines])
    
    // MARK: App url
    
    fileprivate static let appUrlPattern = "(\\[\\[)(.+?[\\[\\]]*)(\\]\\])"

    public static let appUrlRegex = MarklightRegex(pattern: appUrlPattern, options: [.anchorsMatchLines])
    
    // MARK: Bold
    
    /*
     **Bold**
     __Bold__
     */
    
    fileprivate static let strictBoldPattern = "(^|[\\W_])(?:(?!\\1)|(?=^))(\\*|_)\\2(?=\\S)(.*?\\S)\\2\\2(?!\\2)(?=[\\W_]|$)"

    public static let strictBoldRegex = MarklightRegex(pattern: strictBoldPattern, options: [.anchorsMatchLines])

    fileprivate static let boldPattern = "(\\*\\*|__) (?=\\S) (.+?[*_]*) (?<=\\S) \\1"

    public static let boldRegex = MarklightRegex(pattern: boldPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let strikePattern = "(\\~\\~) (?=\\S) (.+?[~]*) (?<=\\S) \\1"

    public static let strikeRegex = MarklightRegex(pattern: strikePattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])
    
    // MARK: Italic
    
    /*
     *Italic*
     _Italic_
     */
    
    fileprivate static let strictItalicPattern = "(^|[\\W_])(?:(?!\\1)|(?=^))(\\*|_)(?=\\S)((?:(?!\\2).)*?\\S)\\2(?!\\2)(?=[\\W_]|$)"

    public static let strictItalicRegex = MarklightRegex(pattern: strictItalicPattern, options: [.anchorsMatchLines])
    
    fileprivate static let italicPattern = "(\\_){1} (?=\\S) (.+?) (?<=\\S) \\1"

    public static let italicRegex = MarklightRegex(pattern: italicPattern, options: [.allowCommentsAndWhitespace, .anchorsMatchLines])

    fileprivate static let autolinkPattern = "([\\(]*(https?|ftp):[^`\'\">\\s\\*]+)"
    
    public static let autolinkRegex = MarklightRegex(pattern: autolinkPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let autolinkPrefixPattern = "((https?|ftp)://)"
    
    public static let autolinkPrefixRegex = MarklightRegex(pattern: autolinkPrefixPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let autolinkEmailPattern = [
        "(?:mailto:)?",
        "(",
        "  [-.\\w]+",
        "  \\@",
        "  [-a-z0-9]+(\\.[-a-z0-9]+)*\\.[a-z]+",
        ")"
        ].joined(separator: "\n")
    
    public static let autolinkEmailRegex = MarklightRegex(pattern: autolinkEmailPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    fileprivate static let mailtoPattern = "mailto:"
    
    public static let mailtoRegex = MarklightRegex(pattern: mailtoPattern, options: [.allowCommentsAndWhitespace, .dotMatchesLineSeparators])
    
    /// maximum nested depth of [] and () supported by the transform;
    /// implementation detail
    fileprivate static let _nestDepth = 6
    
    fileprivate static var _nestedBracketsPattern = ""
    fileprivate static var _nestedParensPattern = ""
    
    /// Reusable pattern to match balanced [brackets]. See Friedl's
    /// "Mastering Regular Expressions", 2nd Ed., pp. 328-331.
    fileprivate static func getNestedBracketsPattern() -> String {
        // in other words [this] and [this[also]] and [this[also[too]]]
        // up to _nestDepth
        if (_nestedBracketsPattern.isEmpty) {
            _nestedBracketsPattern = repeatString([
                "(?>             # Atomic matching",
                "[^\\[\\]]+      # Anything other than brackets",
                "|",
                "\\["
                ].joined(separator: "\n"), _nestDepth) +
                repeatString(" \\])*", _nestDepth)
        }
        return _nestedBracketsPattern
    }
    
    /// Reusable pattern to match balanced (parens). See Friedl's
    /// "Mastering Regular Expressions", 2nd Ed., pp. 328-331.
    fileprivate static func getNestedParensPattern() -> String {
        // in other words (this) and (this(also)) and (this(also(too)))
        // up to _nestDepth
        if (_nestedParensPattern.isEmpty) {
            _nestedParensPattern = repeatString([
                "(?>            # Atomic matching",
                "[^()\\s]+      # Anything other than parens or whitespace",
                "|",
                "\\("
                ].joined(separator: "\n"), _nestDepth) +
                repeatString(" \\))*", _nestDepth)
        }
        return _nestedParensPattern
    }
    
    /// this is to emulate what's available in PHP
    fileprivate static func repeatString(_ text: String, _ count: Int) -> String {
        return Array(repeating: text, count: count).reduce("", +)
    }
        
    public func higlightLinks() {
        guard let storage = self.storage, let range = self.range else {
            return
        }
        
        storage.removeAttribute(.link, range: range)
        
        let pattern = "(https?:\\/\\/(?:www\\.|(?!www))[^\\s\\.]+\\.[^\\s]{2,}|www\\.[^\\s]+\\.[^\\s]{2,})"
        let regex = try! NSRegularExpression(pattern: pattern, options: [NSRegularExpression.Options.caseInsensitive])
        
        regex.enumerateMatches(
            in: (storage.string),
            options: NSRegularExpression.MatchingOptions(),
            range: range,
            using: { (result, matchingFlags, stop) -> Void in
                if let range = result?.range {
                    guard storage.length >= range.location + range.length else {
                        return
                    }
                    
                    var str = storage.mutableString.substring(with: range)
                    
                    if str.starts(with: "www.") {
                        str = "http://" + str
                    }
                    
                    guard let url = URL(string: str) else { return }
                    
                    storage.addAttribute(.link, value: url, range: range)
                }
            }
        )
        
        // We detect and process app urls [[link]]
        NotesTextProcessor.appUrlRegex.matches(storage.string, range: range) { (result) -> Void in
            guard let innerRange = result?.range else { return }
            let from = String.Index.init(utf16Offset: innerRange.lowerBound + 2, in: storage.string)
            let to = String.Index.init(utf16Offset: innerRange.upperBound - 2, in: storage.string)
            
            let appLink = storage.string[from..<to]
            if let link = appLink.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                storage.addAttribute(.link, value: "fsnotes://find?id=" + link, range: innerRange)
            }
        }
    }
    


    func highlightKeyword(search: String = "", remove: Bool = false) {
        guard let storage = self.storage, search.count > 0, UserDefaultsManagement.searchHighlight else { return }

        let searchTerm = NSRegularExpression.escapedPattern(for: search)
        let attributedString = NSMutableAttributedString(attributedString: storage)
        let pattern = "(\(searchTerm))"
        let range: NSRange = NSMakeRange(0, storage.length)
                
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [NSRegularExpression.Options.caseInsensitive])
            
            regex.enumerateMatches(
                in: storage.string,
                options: NSRegularExpression.MatchingOptions(),
                range: range,
                using: {
                    (textCheckingResult, matchingFlags, stop) -> Void in
                    guard let subRange = textCheckingResult?.range else {
                        return
                    }

                    if remove {
                        if attributedString.attributes(at: subRange.location, effectiveRange: nil).keys.contains(NoteAttribute.highlight) {
                            storage.removeAttribute(NoteAttribute.highlight, range: subRange)
                            storage.addAttribute(NSAttributedString.Key.backgroundColor, value: NotesTextProcessor.codeBackground, range: subRange)
                            return
                        } else {
                            storage.removeAttribute(NSAttributedString.Key.backgroundColor, range: subRange)
                        }
                    } else {
                        if attributedString.attributes(at: subRange.location, effectiveRange: nil).keys.contains(NSAttributedString.Key.backgroundColor) {
                            attributedString.addAttribute(NoteAttribute.highlight, value: true, range: subRange)
                        }

                        attributedString.addAttribute(NSAttributedString.Key.backgroundColor, value: highlightColor, range: subRange)
                    }
                }
            )

            if !remove {
                storage.setAttributedString(attributedString)
            }
        } catch {
            print(error)
        }
    }

}

public struct MarklightRegex {
    public let regularExpression: NSRegularExpression!
    
    public init(pattern: String, options: NSRegularExpression.Options = NSRegularExpression.Options(rawValue: 0)) {
        var error: NSError?
        let re: NSRegularExpression?
        do {
            re = try NSRegularExpression(pattern: pattern,
                                         options: options)
        } catch let error1 as NSError {
            error = error1
            re = nil
        }
        
        // If re is nil, it means NSRegularExpression didn't like
        // the pattern we gave it.  All regex patterns used by Markdown
        // should be valid, so this probably means that a pattern
        // valid for .NET Regex is not valid for NSRegularExpression.
        if re == nil {
            if let error = error {
                print("Regular expression error: \(error.userInfo)")
            }
            assert(re != nil)
        }
        
        self.regularExpression = re
    }
    
    public func matches(_ input: String, range: NSRange,
                        completion: @escaping (_ result: NSTextCheckingResult?) -> Void) {
        let s = input as NSString
        //NSRegularExpression.
        let options = NSRegularExpression.MatchingOptions(rawValue: 0)
        regularExpression.enumerateMatches(in: s as String,
                                           options: options,
                                           range: range,
                                           using: { (result, flags, stop) -> Void in

                                            completion(result)
        })
    }
}
