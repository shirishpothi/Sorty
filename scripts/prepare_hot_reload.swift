#!/usr/bin/env swift

import Foundation

enum PreparationError: LocalizedError {
    case usage
    case malformedRecord(URL)

    var errorDescription: String? {
        switch self {
        case .usage:
            return "usage: prepare_hot_reload.swift <project-root> <command-directory> <cache-plist>"
        case .malformedRecord(let url):
            return "malformed frontend command record: \(url.path)"
        }
    }
}

private let outputOptions: Set<String> = [
    "-o",
    "-output-file-map",
    "-supplementary-output-file-map",
    "-emit-dependencies-path",
    "-emit-reference-dependencies-path",
    "-emit-const-values-path",
    "-serialize-diagnostics-path",
    "-index-store-path",
    "-index-unit-output-path",
    "-pch-output-dir",
    "-clang-build-session-file"
]

private func shellEscape(_ value: String) -> String {
    guard !value.isEmpty else { return "''" }

    let safe = CharacterSet.alphanumerics.union(
        CharacterSet(charactersIn: "_@%+=:,./#-")
    )
    return value.unicodeScalars.map { scalar in
        safe.contains(scalar) ? String(scalar) : "\\" + String(scalar)
    }
    .joined()
}

private func strings(in record: Data) -> [String] {
    record.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }
}

private func command(
    frontend: String,
    arguments: [String],
    primaryFile: String,
    workingDirectory: String
) -> String {
    var prepared: [String] = []
    var includedSwiftFiles: Set<String> = []
    var index = 0

    while index < arguments.count {
        let argument = arguments[index]

        if argument == "-primary-file", index + 1 < arguments.count {
            let file = arguments[index + 1]
            if file == primaryFile {
                prepared.append(argument)
                prepared.append(file)
                includedSwiftFiles.insert(file)
            } else if includedSwiftFiles.insert(file).inserted {
                prepared.append(file)
            }
            index += 2
            continue
        }

        if outputOptions.contains(argument), index + 1 < arguments.count {
            index += 2
            continue
        }

        if argument == "-frontend-parseable-output" ||
            argument == "-use-frontend-parseable-output" {
            index += 1
            continue
        }

        if argument.hasSuffix(".swift") {
            if argument != primaryFile, includedSwiftFiles.insert(argument).inserted {
                prepared.append(argument)
            }
            index += 1
            continue
        }

        prepared.append(argument)
        index += 1
    }

    let invocation = ([frontend] + prepared).map(shellEscape).joined(separator: " ")
    return "cd \(shellEscape(workingDirectory)) && \(invocation)"
}

do {
    guard CommandLine.arguments.count == 4 else { throw PreparationError.usage }

    let projectRoot = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL.path
    let commandDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let cacheURL = URL(fileURLWithPath: CommandLine.arguments[3])
    let sourceRoots = [
        projectRoot + "/Sources/SortyApp/",
        projectRoot + "/Sources/SortyLib/"
    ]

    var cache = (NSDictionary(contentsOf: cacheURL) as? [String: String]) ?? [:]
    let records = try FileManager.default.contentsOfDirectory(
        at: commandDirectory,
        includingPropertiesForKeys: [.contentModificationDateKey]
    )
    .sorted {
        let left = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let right = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        return (left ?? .distantPast) < (right ?? .distantPast)
    }
    var updated = 0

    for recordURL in records {
        let values = strings(in: try Data(contentsOf: recordURL))
        guard values.count >= 3 else { throw PreparationError.malformedRecord(recordURL) }

        let workingDirectory = values[0]
        let frontend = values[1]
        let arguments = Array(values.dropFirst(2))
        var primaryFiles: [String] = []
        var index = 0

        while index + 1 < arguments.count {
            if arguments[index] == "-primary-file" {
                primaryFiles.append(arguments[index + 1])
                index += 2
            } else {
                index += 1
            }
        }

        for source in primaryFiles {
            let absoluteSource = URL(fileURLWithPath: source, relativeTo: URL(fileURLWithPath: workingDirectory))
                .standardizedFileURL.path
            guard sourceRoots.contains(where: { absoluteSource.hasPrefix($0) }) else { continue }

            cache[absoluteSource] = command(
                frontend: frontend,
                arguments: arguments,
                primaryFile: source,
                workingDirectory: workingDirectory
            )
            updated += 1
        }
    }

    let plist = try PropertyListSerialization.data(
        fromPropertyList: cache,
        format: .xml,
        options: 0
    )
    try plist.write(to: cacheURL, options: .atomic)
    for recordURL in records {
        try FileManager.default.removeItem(at: recordURL)
    }
    print("Prepared \(cache.count) hot-reload compile commands (\(updated) refreshed).")
} catch {
    FileHandle.standardError.write(Data("Hot reload setup failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
