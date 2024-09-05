//
//  Cursor.swift
//  PlayCover
//  
//  Created by vkmilkyw on 2024/9/5.
//

import Foundation

struct Cursor {
    static var shared = Cursor()
    static var cursorsPath: URL {
        let cursorsDir = PlayTools.playCoverContainer.appendingPathComponent("Cursors")

        if !FileManager.default.fileExists(atPath: cursorsDir.path) {
            do {
                try FileManager.default.createDirectory(at: cursorsDir, withIntermediateDirectories: true)
            } catch {
                Log.shared.error(error)
            }
        }

        return cursorsDir
    }

    private func getCursorImagePath(_ bundleIdentifier: String) -> URL {
        return Cursor.cursorsPath
            .appendingPathComponent(bundleIdentifier)
            .appendingPathExtension("png")
    }

    func loadCursorImage(_ bundleIdentifier: String) -> NSImage? {
        let url = self.getCursorImagePath(bundleIdentifier)
        return NSImage(contentsOfFile: url.path)
    }

    func saveCursorImage(_ src: URL, for bundleIdentifier: String) {
        do {
            let dst = self.getCursorImagePath(bundleIdentifier)
            try FileManager.default.copyItem(at: src, to: dst)
        } catch {
            Log.shared.error(error)
        }
    }

    func clearCursorImage(_ bundleIdentifier: String) {
        let url = self.getCursorImagePath(bundleIdentifier)
        FileManager.default.delete(at: url)
    }
}
