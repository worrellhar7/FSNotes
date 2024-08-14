//
//  AppDelegate+URLRoutes.swift
//  FSNotes
//
//  Created by Jeff Hanbury on 13/04/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import Foundation
import Cocoa


extension AppDelegate {
    
    enum HandledSchemes: String {
        case fsnotes = "fsnotes"
        case nv = "nv"
        case nvALT = "nvalt"
        case file = "file"
    }
    
    enum FSNotesRoutes: String {
        case find = "find"
        case new = "new"
    }
    
    enum NvALTRoutes: String {
        case find = "find"
        case blank = ""
        case make = "make"
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        guard var url = urls.first,
            let scheme = url.scheme
            else { return }

        if url.host == "open" {
            if let tag = url["tag"]?.removingPercentEncoding {
                ViewController.shared()?.sidebarOutlineView.select(tag: tag)
                return
            }
        }

        let path = url.absoluteString.escapePlus()
        if let escaped = URL(string: path) {
            url = escaped
        }

        switch scheme {
        case HandledSchemes.file.rawValue:
            if nil != ViewController.shared() {
                self.importNotes(urls: urls)
            } else {
                self.urls = urls
            }
        case HandledSchemes.fsnotes.rawValue:
            FSNotesRouter(url)
        case HandledSchemes.nv.rawValue,
             HandledSchemes.nvALT.rawValue:
            NvALTRouter(url)
        default:
            break
        }
    }

    func importNotes(urls: [URL]) {
        guard let vc = ViewController.shared() else { return }

        var importedNote: Note? = nil
        var sidebarIndex: Int? = nil

        for url in urls {
            if let items = vc.sidebarOutlineView.sidebarItems, let note = Storage.shared().getBy(url: url) {
                if let sidebarItem = items.first(where: { ($0 as? SidebarItem)?.project == note.project || $0 as? Project == note.project }) {
                    sidebarIndex = vc.sidebarOutlineView.row(forItem: sidebarItem)
                    importedNote = note
                }
            } else {
                let project = Storage.shared().getMainProject()
                let newUrl = vc.copy(project: project, url: url)

                UserDataService.instance.focusOnImport = newUrl
                UserDataService.instance.skipSidebarSelection = true
            }
        }

        if let note = importedNote, let si = sidebarIndex {
            vc.sidebarOutlineView.selectRowIndexes([si], byExtendingSelection: false)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: {
                vc.notesTableView.setSelected(note: note)
            })
        }
    }
    
    // MARK: - FSNotes routes
    
    func FSNotesRouter(_ url: URL) {
        guard let directive = url.host else { return }
        
        switch directive {
        case FSNotesRoutes.find.rawValue:
            RouteFSNotesFind(url)
        case FSNotesRoutes.new.rawValue:
            RouteFSNotesNew(url)
        default:
            break
        }
    }
    
    /// Handles URLs with the path /find/searchstring1%20searchstring2
    func RouteFSNotesFind(_ url: URL) {
        guard ViewController.shared() != nil else {
            self.url = url
            return
        }

        search(url: url)
    }

    public func search(url: URL) {
        guard let vc = ViewController.shared() else { return }

        var lastPath = url.lastPathComponent

        if let wikiURL = url["id"] {
            var note = Storage.shared().getBy(fileName: wikiURL)
            if note == nil {
                note = Storage.shared().getBy(title: wikiURL)
            }
            
            if let note = note {
                vc.cleanSearchAndEditArea(shouldBecomeFirstResponder: false, completion: { () -> Void in
                    vc.notesTableView.selectRowAndSidebarItem(note: note)
                    NSApp.mainWindow?.makeFirstResponder(vc.editor)
                    vc.notesTableView.saveNavigationHistory(note: note)
                })
                return
            } else {
                lastPath = wikiURL
                vc.search.window?.makeFirstResponder(vc.search)
            }
        }

        search(query: lastPath)
    }

    func search(query: String) {
        guard let controller = ViewController.shared() else { return }

        let searchQuery = SearchQuery()
        searchQuery.type = .All
        searchQuery.setFilter(query)

        controller.storage.setSearchQuery(value: searchQuery)
        controller.updateTable() {
            DispatchQueue.main.async {
                controller.search.stringValue = query

                if let note = controller.notesTableView.noteList.first {
                    if note.title.lowercased() == query.lowercased() {
                        controller.notesTableView.saveNavigationHistory(note: note)
                        controller.notesTableView.setSelected(note: note)
                        controller.view.window?.makeFirstResponder(controller.editor)
                    } else {
                        controller.search.suggestAutocomplete(note, filter: query)
                    }
                }
            }
        }
    }
    
    /// Handles URLs with the following paths:
    ///   - fsnotes://make/?title=URI-escaped-title&html=URI-escaped-HTML-data
    ///   - fsnotes://make/?title=URI-escaped-title&txt=URI-escaped-plain-text
    ///   - fsnotes://make/?txt=URI-escaped-plain-text
    ///
    /// The three possible parameters (title, txt, html) are all optional.
    ///
    func RouteFSNotesNew(_ url: URL) {
        var title = ""
        var body = ""
        
        if let titleParam = url["title"] {
            title = titleParam
        }
        
        if let txtParam = url["txt"] {
            body = txtParam
        }
        else if let htmlParam = url["html"] {
            body = htmlParam
        }
        
        guard nil != ViewController.shared() else {
            self.newName = title
            self.newContent = body
            return
        }

        create(name: title, content: body)
    }

    func create(name: String, content: String) {
        guard let controller = ViewController.shared() else { return }

        _ = controller.createNote(name: name, content: content)
    }
    
    
    // MARK: - nvALT routes, for compatibility
    
    func NvALTRouter(_ url: URL) {
        guard let directive = url.host else { return }
        
        switch directive {
        case NvALTRoutes.find.rawValue:
            RouteNvAltFind(url)
        case NvALTRoutes.make.rawValue:
            RouteNvAltMake(url)
        default:
            RouteNvAltBlank(url)
            break
        }
    }
    
    /// Handle URLs in the format nv://find/searchstring1%20searchstring2
    ///
    /// Note: this route is identical to the corresponding FSNotes route.
    ///
    func RouteNvAltFind(_ url: URL) {
        RouteFSNotesFind(url)
    }
    
    /// Handle URLs in the format nv://note%20title
    ///
    /// Note: this route is an alias to the /find route above.
    ///
    func RouteNvAltBlank(_ url: URL) {
        let pathWithFind = url.absoluteString.replacingOccurrences(of: "://", with: "://find/")
        guard let newURL = URL(string: pathWithFind) else { return }
        
        RouteFSNotesFind(newURL)
    }
    
    /// Handle URLs in the format:
    ///
    ///   - nv://make/?title=URI-escaped-title&html=URI-escaped-HTML-data&tags=URI-escaped-tag-string
    ///   - nv://make/?title=URI-escaped-title&txt=URI-escaped-plain-text
    ///   - nv://make/?txt=URI-escaped-plain-text
    ///
    /// The four possible parameters (title, txt, html and tags) are all optional.
    ///
    func RouteNvAltMake(_ url: URL) {
        var title = ""
        var body = ""
        
        if let titleParam = url["title"] {
            title = titleParam
        }
        
        if let txtParam = url["txt"] {
            body = txtParam
        }
        else if let htmlParam = url["html"] {
            body = htmlParam
        }
        
        if let tagsParam = url["tags"] {
            body = body.appending("\n\nnvALT tags: \(tagsParam)")
        }
        
        guard let controller = ViewController.shared() else { return }
        
        _ = controller.createNote(name: title, content: body)
    }
}
