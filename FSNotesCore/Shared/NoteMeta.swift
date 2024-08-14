//
//  NoteMeta.swift
//  FSNotes
//
//  Created by Олександр Глущенко on 17.05.2020.
//  Copyright © 2020 Oleksandr Glushchenko. All rights reserved.
//

import Foundation

public struct NoteMeta: Codable {
    var url: URL
    var attachments: [URL]?
    var imageUrl: [URL]?
    var title: String
    var preview: String
    var modificationDate: Date
    var creationDate: Date
    var pinned: Bool
    var tags: [String]
    var selectedRange: NSRange?
}
