import Foundation
import InjectionImpl

enum HotReloadPreparationError: LocalizedError {
    case usage

    var errorDescription: String? {
        "usage: SortyHotReloadPreparer <swiftpm-build-directory>"
    }
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw HotReloadPreparationError.usage
    }

    let buildDirectory = URL(
        fileURLWithPath: CommandLine.arguments[1],
        isDirectory: true
    )
    let objectDirectories = Set(["SortyApp.build", "SortyLib.build"])
    let fileManager = FileManager.default
    guard let enumerator = fileManager.enumerator(
        at: buildDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else {
        throw CocoaError(.fileReadNoSuchFile)
    }

    var objectFiles: [URL] = []
    for case let fileURL as URL in enumerator {
        guard fileURL.pathExtension == "o",
              fileURL.path.contains("/debug/"),
              objectDirectories.contains(
                  fileURL.deletingLastPathComponent().lastPathComponent
              ) else {
            continue
        }
        objectFiles.append(fileURL)
    }

    var knownDefinitions: [String: String] = [:]
    var exportedSymbols = 0
    for fileURL in objectFiles.sorted(by: { $0.path < $1.path }) {
        exportedSymbols += Unhider.unhide(
            object: fileURL.path,
            &knownDefinitions
        ).count
    }

    print(
        "Prepared \(objectFiles.count) Debug objects " +
        "(\(exportedSymbols) default-argument symbols exported)."
    )
} catch {
    FileHandle.standardError.write(
        Data("Hot reload preparation failed: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
