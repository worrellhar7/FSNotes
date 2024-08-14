//
//  CodeTextProcessor.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 9/2/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

class CodeTextProcessor {
    private var textStorage: NSMutableAttributedString

    init(textStorage: NSMutableAttributedString) {
        self.textStorage = textStorage
    }

    public func getCodeBlockRanges(parRange: NSRange) -> [NSRange]? {
        guard UserDefaultsManagement.codeBlockHighlight else { return nil }

        let min = scanCodeBlockUp(location: parRange.location - 1)
        let max = scanCodeBlockDown(location: parRange.upperBound)

        let attributedParagraph = textStorage.attributedSubstring(from: parRange)
        let paragraph = attributedParagraph.string
        let isCodeParagraph = isCodeBlock(attributedParagraph)

        if let min = min, let max = max {
            if isCodeParagraph || paragraph.trim() == "\n" {
                return [NSRange(min.location..<max.upperBound)]
            } else {
                return [min, max]
            }
        } else if let min = min {
            if isCodeParagraph {
                return [NSRange(min.location..<parRange.upperBound - 1)]
            } else {
                return [min]
            }
        } else if let max = max {
            if isCodeParagraph {
                return [NSRange(parRange.location..<max.upperBound)]
            } else {
                return [max]
            }
        } else if isCodeParagraph {
            return [parRange]
        }

        return nil
    }

    private func scanCodeBlockUp(location: Int, min: Int? = nil, firstFound: Int? = nil) -> NSRange? {
        var firstFound = firstFound

        if location < 0 {
            if let min = min, let firstFound = firstFound {
                return NSRange(min..<firstFound)
            }
            return nil
        }

        let prevRange = textStorage.mutableString.paragraphRange(for: NSRange(location: location, length: 0))
        let prevAttributed = textStorage.attributedSubstring(from: prevRange)
        let prev = prevAttributed.string

        if isCodeBlock(prevAttributed) {
            if firstFound == nil {
                firstFound = prevRange.upperBound - 1
            }

            return scanCodeBlockUp(location: prevRange.location - 1, min: prevRange.location, firstFound: firstFound)
        } else if prev.trim() == "\n" {
            return scanCodeBlockUp(location: prevRange.location - 1, min: min, firstFound: firstFound)
        } else {
            if let firstFound = firstFound, let min = min {
                return NSRange(min..<firstFound)
            }

            return nil
        }
    }

    private func scanCodeBlockDown(location: Int, max: Int? = nil, firstFound: Int? = nil) -> NSRange? {
        var firstFound = firstFound

        if location > textStorage.length {
            if let max = max, let firstFound = firstFound {
                return NSRange(firstFound..<max)
            }
            return nil
        }

        let nextRange = textStorage.mutableString.paragraphRange(for: NSRange(location: location, length: 0))
        let nextAttributed = textStorage.attributedSubstring(from: nextRange)
        let next = nextAttributed.string

        if isCodeBlock(nextAttributed) {
            if textStorage.length == nextRange.upperBound {
                if let firstFound = firstFound {
                    return NSRange(firstFound..<nextRange.upperBound)
                }
            }

            if firstFound == nil {
                firstFound = nextRange.location
            }

            return scanCodeBlockDown(location: nextRange.upperBound, max: nextRange.upperBound - 1, firstFound: firstFound)
        } else if next.trim() == "\n" {
            if textStorage.length == nextRange.upperBound {
                if let max = max, let firstFound = firstFound {
                    return NSRange(firstFound..<max)
                }
            }

            return scanCodeBlockDown(location: nextRange.upperBound, max: max, firstFound: firstFound)
        } else {
            if let max = max, let firstFound = firstFound {
                return NSRange(firstFound..<max)
            }
            return nil
        }
    }

    private func isCodeBlock(_ attributedString: NSAttributedString) -> Bool {
        if attributedString.string.starts(with: "\t") || attributedString.string.starts(with: "    ") {
            return true
        }

        return false
    }

    public func getCodeBlockRanges() -> [NSRange]? {
        guard UserDefaultsManagement.codeBlockHighlight else { return nil }

        var paragraphRanges = [NSRange]()
        var paragraphList = [String]()

        let string = textStorage.string as NSString
        string.enumerateSubstrings(in: NSRange(0..<string.length), options: .byParagraphs) {value, range, _, _ in
            if let value = value, (value.starts(with: "    ") || value.starts(with: "\t")), self.textStorage.attributedSubstring(from: range).hasTodoAttribute() {
                return
            }

            paragraphRanges.append(range)
            paragraphList.append(value!)
        }

        return getBlockRanges(ranges: paragraphRanges, pars: paragraphList)
    }

    public func getBlockRanges(ranges: [NSRange], pars: [String]) -> [NSRange]? {
        let digitSet = CharacterSet.decimalDigits
        var codeBlocks = [NSRange]()
        var index = 0
        var start: Int?
        var finish: Int?
        var prevParagraph = ""
        var skipFlag = false

        for paragraph in pars {
            if isCodeBlockParagraph(paragraph) {
                if skipFlag {
                    index += 1
                    continue
                }

                if let char = prevParagraph.unicodeScalars.first,
                    (digitSet.contains(char) && prevParagraph.starts(with: "\(char). "))
                    || (prevParagraph.contains("- ") && !prevParagraph.contains("    ") && !prevParagraph.contains("\t"))
                    || (prevParagraph.contains(" - ") && !prevParagraph.contains("    ") && !prevParagraph.contains("\t"))
                    || (prevParagraph.contains("*") && !prevParagraph.contains("    ") && !prevParagraph.contains("\t")) {

                    skipFlag = true
                    index += 1
                    continue
                }

                if start != nil {
                    finish = ranges[index].upperBound
                } else {
                    start = ranges[index].location
                    finish = ranges[index].upperBound
                }

                index += 1
                prevParagraph = paragraph

                continue
            } else if paragraph.trim() == "" {
                index += 1
                continue
            } else if let startPos = start, let finishPos = finish {
                codeBlocks.append(NSRange(startPos..<finishPos))
                start = nil
                finish = nil
            }

            skipFlag = false
            index += 1
            prevParagraph = paragraph
        }

        if let startPos = start, let finishPos = finish {
            codeBlocks.append(NSRange(startPos..<finishPos))
            start = nil
            finish = nil
        }

        return codeBlocks
    }

    public func isCodeBlockParagraph(_ paragraph: String) -> Bool {
        if paragraph.starts(with: "\t") || paragraph.starts(with: "    ") {
            return true
        }

        return false
    }

    public func getIntersectedRange(range: NSRange, ranges: [NSRange]) -> NSRange? {
        for rangeItem in ranges {
            if range.intersection(rangeItem) != nil {
                return rangeItem
            }
        }

        return nil
    }
}
