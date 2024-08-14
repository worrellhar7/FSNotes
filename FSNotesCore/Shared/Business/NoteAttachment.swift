//
//  ImageAttachment.swift
//  FSNotes
//
//  Created by Oleksandr Glushchenko on 7/15/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation
import AVKit

#if os(OSX)
    import Cocoa
#else
    import UIKit
#endif

class NoteAttachment {
    public var title: String

    private var path: String
    public var url: URL

    public var note: Note?
    public var imageCache: URL?

    public var editor: EditTextView?

    init(editor: EditTextView, title: String, path: String, url: URL, note: Note? = nil) {
        self.editor = editor
        self.title = title
        self.url = url
        self.path = path
        self.note = note
    }

    weak var weakTimer: Timer?

    public func getAttributedString(newLine: Bool = false) -> NSMutableAttributedString? {
        let imageKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.url")
        let pathKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.path")
        let titleKey = NSAttributedString.Key(rawValue: "co.fluder.fsnotes.image.title")

        guard FileManager.default.fileExists(atPath: self.url.path) else { return nil }
        guard let attachment = load() else { return nil }

        let attributedString = NSAttributedString(attachment: attachment)
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)

        #if os(OSX)
            let attributes = [
                titleKey: self.title,
                pathKey: self.path,
                imageKey: self.url,
                .link: self.url,
                .attachment: attachment
            ] as [NSAttributedString.Key: Any]
        #else
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = url.isImage ? .center : .left
            paragraphStyle.lineSpacing = CGFloat(UserDefaultsManagement.editorLineSpacing)

            let attributes = [
                titleKey: self.title,
                pathKey: self.path,
                imageKey: self.url,
                .link: self.url,
                .attachment: attachment,
                .paragraphStyle: paragraphStyle
            ] as [NSAttributedString.Key: Any]
        #endif

        mutableAttributedString.addAttributes(attributes, range: NSRange(0..<1))

        if newLine {
            mutableAttributedString.append(NSAttributedString(string: "\n"))
        }

        return mutableAttributedString
    }

    public func getSize(url: URL) -> CGSize {
        var width = 0
        var height = 0
        var orientation = 0

        if url.isVideo {
            guard let track = AVURLAsset(url: url).tracks(withMediaType: AVMediaType.video).first else {
                return CGSize(width: width, height: height)
            }

            let size = track.naturalSize.applying(track.preferredTransform)
            return CGSize(width: abs(size.width), height: abs(size.height))
        }

        let url = NSURL(fileURLWithPath: url.path)
        if let imageSource = CGImageSourceCreateWithURL(url, nil) {
            let imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as Dictionary?
            width = imageProperties?[kCGImagePropertyPixelWidth] as? Int ?? 0
            height = imageProperties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            orientation = imageProperties?[kCGImagePropertyOrientation] as? Int ?? 0

            if case 5...8 = orientation {
                height = imageProperties?[kCGImagePropertyPixelWidth] as? Int ?? 0
                width = imageProperties?[kCGImagePropertyPixelHeight] as? Int ?? 0
            }
        }

        return CGSize(width: width, height: height)
    }

    public static func getCacheUrl(from url: URL, prefix: String = "Preview") -> URL? {
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent(prefix)

        return temporary.appendingPathComponent(url.absoluteString.md5 + "." + url.pathExtension)
    }

    public static func savePreviewImage(url: URL, image: Image, prefix: String = "Preview") {
        var temporary = URL(fileURLWithPath: NSTemporaryDirectory())
        temporary.appendPathComponent(prefix)

        if !FileManager.default.fileExists(atPath: temporary.path) {
            try? FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true, attributes: nil)
        }

        if let url = self.getCacheUrl(from: url, prefix: prefix) {
            if let data = image.jpgData {
                try? data.write(to: url)
            }
        }
    }

    public func getImageText() -> String {
        let fileSize = self.url.fileSize
        var sizeTitle = String()

        if fileSize > 10000 {
            sizeTitle = String(format: "%.2f", Double(fileSize) / 1000000) + " MB"
        } else {
            sizeTitle = String(fileSize) + " bytes"
        }

        let text = " \(self.url.lastPathComponent) – \(sizeTitle) 📎 "
        return text
    }

    public func getImageWidth(text: String) -> Double {
        let font = getAttachmentFont()
        let labelWidth = (text as NSString).size(withAttributes: [.font: font]).width

        return labelWidth
    }
}
