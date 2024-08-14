//
//  NSMutableAttributedString+Attachments.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 10/3/19.
//  Copyright © 2019 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

extension NSMutableAttributedString {
    func loadImages(editor: EditTextView, note: Note) {
        let paragraphRange = NSRange(0..<length)
        var offset = 0

        FSParser.imageInlineRegex.matches(string, range: paragraphRange) { (result) -> Void in
            guard var range = result?.range else { return }

            range = NSRange(location: range.location - offset, length: range.length)
            let mdLink = self.attributedSubstring(from: range).string

            var path = String()
            var title = String()

            if let titleRange = result?.range(at: 2) {
                title = self.mutableString.substring(with: NSRange(location: titleRange.location - offset, length: titleRange.length))
            }

            if let linkRange = result?.range(at: 3) {
                path = self.mutableString.substring(with: NSRange(location: linkRange.location - offset, length: linkRange.length))
            }

            guard let cleanPath = path.removingPercentEncoding,
                  let imageURL = note.getImageUrl(imageName: cleanPath)
            else { return }

            let imageAttachment = NoteAttachment(editor: editor, title: title, path: cleanPath, url: imageURL, note: note)

            if let attributedStringWithImage = imageAttachment.getAttributedString() {
                offset += mdLink.count - 1
                self.replaceCharacters(in: range, with: attributedStringWithImage)
            }
        }
    }
}
