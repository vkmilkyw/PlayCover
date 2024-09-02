//
//  PlayTools.swift
//  PlayCover
//

import Foundation
import injection

class PlayTools {
    private static let frameworksURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("Frameworks")
    private static let playToolsFramework = frameworksURL
        .appendingPathComponent("PlayTools")
        .appendingPathExtension("framework")
    private static let playToolsPath = playToolsFramework
        .appendingPathComponent("PlayTools")
    private static let akInterfacePath = playToolsFramework
        .appendingPathComponent("PlugIns")
        .appendingPathComponent("AKInterface")
        .appendingPathExtension("bundle")
    private static let bundledPlayToolsFramework = Bundle.main.bundleURL
        .appendingPathComponent("Contents")
        .appendingPathComponent("Frameworks")
        .appendingPathComponent("PlayTools")
        .appendingPathExtension("framework")

    public static var playCoverContainer: URL {
        let playCoverPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent("io.playcover.PlayCover")
        if !FileManager.default.fileExists(atPath: playCoverPath.path) {
            do {
                try FileManager.default.createDirectory(at: playCoverPath,
                                                        withIntermediateDirectories: true,
                                                        attributes: [:])
            } catch {
                Log.shared.error(error)
            }
        }

        return playCoverPath
    }
    
    private static var appPlayToolsPath: URL {
        let playToolsDir = PlayTools.playCoverContainer.appendingPathComponent("App PlayTools")

        if !FileManager.default.fileExists(atPath: playToolsDir.path) {
            do {
                try FileManager.default.createDirectory(at: playToolsDir, withIntermediateDirectories: true)
            } catch {
                Log.shared.error(error)
            }
        }

        return playToolsDir
    }

    static func installOnSystem() {
        Task(priority: .background) {
            do {
                Log.shared.log("Installing PlayTools")

                // Check if Frameworks folder exists, if not, create it
                if !FileManager.default.fileExists(atPath: frameworksURL.path) {
                    try FileManager.default.createDirectory(
                        atPath: frameworksURL.path,
                        withIntermediateDirectories: true,
                        attributes: [:])
                }

                // Check if a version of PlayTools is already installed, if so remove it
                FileManager.default.delete(at: URL(fileURLWithPath: playToolsFramework.path))

                // Install version of PlayTools bundled with PlayCover
                Log.shared.log("Copying PlayTools to Frameworks")
                if FileManager.default.fileExists(atPath: playToolsFramework.path) {
                    try FileManager.default.removeItem(at: playToolsFramework)
                }
                try FileManager.default.copyItem(at: bundledPlayToolsFramework, to: playToolsFramework)
            } catch {
                Log.shared.error(error)
            }
        }
    }

    static func installInIPA(_ exec: URL) async throws {
        var binary = try Data(contentsOf: exec)
        try Macho.stripBinary(&binary)

        Inject.injectMachO(machoPath: exec.path,
                           cmdType: .loadDylib,
                           backup: false,
                           injectPath: playToolsPath.path,
                           finishHandle: { result in
            if result {
                do {
                    try installPluginInIPA(exec.deletingLastPathComponent())
                    try Shell.signApp(exec)
                } catch {
                    Log.shared.error(error)
                }
            }
        })
    }

    static func installPluginInIPA(_ payload: URL) throws {
        let allFiles = try FileManager.default.contentsOfDirectory(
            at: bundledPlayToolsFramework, includingPropertiesForKeys: [])
        for localizationDirectory in allFiles where localizationDirectory.pathExtension == "lproj" {
            _ = try copyAsset(target: payload,
                              directoryName: localizationDirectory.lastPathComponent,
                              component: "Playtools", pathExtension: "strings")
        }

        let bundleTarget = try copyAsset(target: payload, directoryName: "PlugIns",
                                         component: "AKInterface", pathExtension: "bundle")
        try bundleTarget.fixExecutable()
        try Shell.signMacho(bundleTarget)
    }

    static func copyAsset(target: URL, directoryName: String,
                          component: String, pathExtension: String) throws -> URL {
        let directory = target.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let target = directory
                    .appendingPathComponent(component)
                    .appendingPathExtension(pathExtension)

        let source = bundledPlayToolsFramework
                    .appendingPathComponent(directoryName)
                    .appendingPathComponent(component)
                    .appendingPathExtension(pathExtension)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            try FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        }
        return target
    }

    static func injectInIPA(_ exec: URL, payload: URL) throws {
        var binary = try Data(contentsOf: exec)
        try Macho.stripBinary(&binary)

        Inject.injectMachO(machoPath: exec.path,
                           cmdType: .loadDylib,
                           backup: false,
                           injectPath: "@executable_path/Frameworks/PlayTools.dylib",
                           finishHandle: { result in
            if result {
                Task(priority: .background) {
                    do {
                        if !FileManager.default.fileExists(atPath: payload.appendingPathComponent("Frameworks").path) {
                            try FileManager.default.createDirectory(
                                at: payload.appendingPathComponent("Frameworks"),
                                withIntermediateDirectories: true)
                        }

                        let libraryTarget = payload.appendingPathComponent("Frameworks")
                            .appendingPathComponent("PlayTools")
                            .appendingPathExtension("dylib")

                        let tools = bundledPlayToolsFramework
                            .appendingPathComponent("PlayTools")

                        if FileManager.default.fileExists(atPath: libraryTarget.path) {
                            try FileManager.default.removeItem(at: libraryTarget)
                        }
                        try FileManager.default.copyItem(at: tools, to: libraryTarget)

                        try libraryTarget.fixExecutable()
                        try installPluginInIPA(payload)
                    } catch {
                        Log.shared.error(error)
                    }
                }
            }
        })
    }

    static func removeFromApp(_ exec: URL) async {
        Inject.removeMachO(machoPath: exec.path,
                           cmdType: .loadDylib,
                           backup: false,
                           injectPath: playToolsPath.path,
                           finishHandle: { result in
            if result {
                do {
                    let pluginUrl = exec.deletingLastPathComponent()
                        .appendingPathComponent("PlugIns")
                        .appendingPathComponent("AKInterface")
                        .appendingPathExtension("bundle")

                    if FileManager.default.fileExists(atPath: pluginUrl.path) {
                        try FileManager.default.removeItem(at: pluginUrl)
                    }
                    try Shell.signApp(exec)
                } catch {
                    Log.shared.error(error)
                }
            }
        })
    }

    static func installedInExec(atURL url: URL) throws -> Bool {
        var binary = try Data(contentsOf: url)
        try Macho.stripBinary(&binary)
        var result = false
        try _ = Macho.iterateLoadCommands(binary: binary) { offset, shouldSwap in
            let loadCommand = binary.extract(load_command.self, offset: offset,
                                             swap: shouldSwap ? swap_load_command:nil)
            if loadCommand.cmd == UInt32(LC_LOAD_DYLIB) {
                let dylibCommand = binary.extract(dylib_command.self, offset: offset,
                                                  swap: shouldSwap ? swap_dylib_command:nil)

                let dylibName = String(data: binary,
                                       offset: offset,
                                       commandSize: Int(dylibCommand.cmdsize),
                                       loadCommandString: dylibCommand.dylib.name)
                if dylibName == playToolsPath.esc {
                    result = true
                    return true
                }
            }
            return false
        }
        return result
    }

    static func isInstalled() throws -> Bool {
        try FileManager.default.fileExists(atPath: playToolsPath.path)
            && FileManager.default.fileExists(atPath: akInterfacePath.path)
            && Macho.isMachoValidArch(playToolsPath)
    }

	static func fetchEntitlements(_ exec: URL) throws -> String {
        do {
            return try Shell.run("/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", exec.path)
        } catch {
            if error.localizedDescription.contains("Document is empty") {
                // Empty entitlements
                return ""
            } else {
                throw error
            }
        }
	}

    static func configurePlayTools(_ zipUrl: URL, forApp bundleId: String) {
        do {
            Log.shared.log("Configuring PlayTools for \(bundleId)")

            let appSpecificPlayToolsPath = appPlayToolsPath.appendingPathComponent(bundleId)

            // Delete and recreate directory
            FileManager.default.delete(at: URL(fileURLWithPath: appSpecificPlayToolsPath.path))
            try FileManager.default.createDirectory(at: appSpecificPlayToolsPath, withIntermediateDirectories: true)

            // Extract from zip
            try Shell.run("/usr/bin/unzip", "-oq", zipUrl.path, "-d", appSpecificPlayToolsPath.path)

        } catch {
            Log.shared.error(error)
        }
    }

    static func copyPlayToolsForApp(_ bundleId: String) {
        do {
            let appSpecificPlayToolsPath = appPlayToolsPath.appendingPathComponent(bundleId)
                .appendingPathComponent("PlayTools")
                .appendingPathExtension("framework")
            let bundleIdHintFilePath = playToolsFramework.appendingPathComponent("BUNDLEID")

            if FileManager.default.fileExists(atPath: appSpecificPlayToolsPath.path) {
                Log.shared.log("Copying PlayTools for \(bundleId)")
                // Delete existing PlayTools
                FileManager.default.delete(at: URL(fileURLWithPath: playToolsFramework.path))
                // Copy the app-specific version of PlayTools
                try FileManager.default.copyItem(at: appSpecificPlayToolsPath, to: playToolsFramework)
                // Output bundle id to a file
                try bundleId.write(toFile: bundleIdHintFilePath.path, atomically: true, encoding: .utf8)
            } else {
                // If PlayTools is not found or is an app-specific version, reinstall it
                if FileManager.default.fileExists(atPath: bundleIdHintFilePath.path) {
                    Log.shared.log("Copying default PlayTools")
                    FileManager.default.delete(at: URL(fileURLWithPath: playToolsFramework.path))
                    try FileManager.default.copyItem(at: bundledPlayToolsFramework, to: playToolsFramework)
                }
            }
        } catch {
            Log.shared.error(error)
        }
    }
}
