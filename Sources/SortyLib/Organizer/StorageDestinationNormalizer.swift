import Foundation

/// Rewrites storage-like relative aliases (for example "storage/Excel") into approved absolute storage paths.
enum StorageDestinationNormalizer {
    static func normalize(
        plan: OrganizationPlan,
        allowedStorageLocations: [StorageLocation],
        knownSubfolders: [String: [String]] = [:],
        sourceDirectoryURL: URL? = nil
    ) -> OrganizationPlan {
        let canonicalRoots = Array(Set(allowedStorageLocations.map { StorageLocationPathResolver.canonicalPath($0.path) })).sorted()
        guard !canonicalRoots.isEmpty else { return plan }

        let mergedKnownSubfolders = mergedKnownSubfolders(
            from: knownSubfolders,
            locations: allowedStorageLocations
        )
        let aliasMap = buildAliasMap(
            locations: allowedStorageLocations,
            canonicalRoots: canonicalRoots,
            knownSubfolders: mergedKnownSubfolders
        )
        guard !aliasMap.isEmpty else { return plan }

        let canonicalSourceRoot = sourceDirectoryURL.map { StorageLocationPathResolver.canonicalPath($0.path) }

        var normalizedPlan = plan
        normalizedPlan.suggestions = plan.suggestions.map {
            normalizeFolder($0, aliasMap: aliasMap, canonicalStorageRoots: canonicalRoots, canonicalSourceRoot: canonicalSourceRoot)
        }

        // Fallback: when exactly one storage root exists and NO folder resolved to
        // a storage destination, the AI likely ignored absolute-path instructions.
        // Remap unresolved relative folders as subfolders of the storage root so
        // files actually reach the intended destination.
        if canonicalRoots.count == 1, let onlyRoot = canonicalRoots.first,
           !normalizedPlan.suggestions.isEmpty {
            let anyResolved = normalizedPlan.suggestions.contains {
                hasStorageDestination($0, canonicalRoots: canonicalRoots)
            }
            if !anyResolved {
                normalizedPlan.suggestions = normalizedPlan.suggestions.map {
                    applyStorageRootFallback($0, storageRoot: onlyRoot)
                }
            }
        }

        return normalizedPlan
    }

    /// Check recursively whether a folder suggestion targets a storage destination.
    private static func hasStorageDestination(_ folder: FolderSuggestion, canonicalRoots: [String]) -> Bool {
        if let abs = StorageLocationPathResolver.normalizedAbsolutePath(from: folder.folderName),
           canonicalRoots.contains(where: { StorageLocationPathResolver.isPath(abs, within: $0) }) {
            return true
        }
        return folder.subfolders.contains { hasStorageDestination($0, canonicalRoots: canonicalRoots) }
    }

    /// Remap a relative folder name to be a subfolder of the given storage root.
    private static func applyStorageRootFallback(_ folder: FolderSuggestion, storageRoot: String) -> FolderSuggestion {
        // Already an absolute storage path — keep as-is.
        if StorageLocationPathResolver.normalizedAbsolutePath(from: folder.folderName) != nil {
            return folder
        }
        var updated = folder
        var resolvedURL = URL(fileURLWithPath: storageRoot, isDirectory: true)
        resolvedURL.appendPathComponent(folder.folderName, isDirectory: true)
        updated.folderName = StorageLocationPathResolver.canonicalPath(resolvedURL.path)
        return updated
    }

    private static func normalizeFolder(
        _ folder: FolderSuggestion,
        aliasMap: [String: String],
        canonicalStorageRoots: [String],
        canonicalSourceRoot: String?
    ) -> FolderSuggestion {
        var updated = folder
        updated.folderName = normalizeFolderName(
            folder.folderName,
            aliasMap: aliasMap,
            canonicalStorageRoots: canonicalStorageRoots,
            canonicalSourceRoot: canonicalSourceRoot
        )
        updated.subfolders = folder.subfolders.map {
            normalizeFolder($0, aliasMap: aliasMap, canonicalStorageRoots: canonicalStorageRoots, canonicalSourceRoot: canonicalSourceRoot)
        }
        return updated
    }

    private static func normalizeFolderName(
        _ rawFolderName: String,
        aliasMap: [String: String],
        canonicalStorageRoots: [String],
        canonicalSourceRoot: String?
    ) -> String {
        if let absolutePath = StorageLocationPathResolver.normalizedAbsolutePath(from: rawFolderName) {
            // Already within a valid storage root — keep as-is
            if canonicalStorageRoots.contains(where: { StorageLocationPathResolver.isPath(absolutePath, within: $0) }) {
                return absolutePath
            }

            // Absolute path inside source directory — the AI likely meant to reference a
            // storage location by name but mistakenly prepended the source directory path.
            // Strip the source prefix and run the relative portion through alias matching.
            if let sourceRoot = canonicalSourceRoot,
               StorageLocationPathResolver.isPath(absolutePath, within: sourceRoot),
               absolutePath != sourceRoot {
                let prefix = sourceRoot == "/" ? "/" : sourceRoot + "/"
                let relativePortion = String(absolutePath.dropFirst(prefix.count))
                if !relativePortion.isEmpty {
                    let resolved = resolveRelativeAlias(relativePortion, aliasMap: aliasMap)
                    return resolved
                }
            }

            return absolutePath
        }

        let canonicalRelative = StorageLocationPathResolver.canonicalPath(rawFolderName)
        guard !canonicalRelative.isEmpty else { return canonicalRelative }

        return resolveRelativeAlias(canonicalRelative, aliasMap: aliasMap)
    }

    private static func resolveRelativeAlias(_ relativePath: String, aliasMap: [String: String]) -> String {
        let canonical = StorageLocationPathResolver.canonicalPath(relativePath)
        guard !canonical.isEmpty else { return canonical }

        // Try normal alias on the whole path
        if let rootPath = aliasMap[normalizeAlias(canonical)] {
            return rootPath
        }

        // Try compact alias (strips spaces for PascalCase matching)
        if let rootPath = aliasMap[compactAlias(canonical)] {
            return rootPath
        }

        let segments = canonical
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let first = segments.first else { return canonical }

        // Try normal alias for first segment
        var rootPath: String? = aliasMap[normalizeAlias(first)]

        // Try compact alias for first segment
        if rootPath == nil {
            rootPath = aliasMap[compactAlias(first)]
        }

        guard let resolvedRoot = rootPath else { return canonical }
        guard segments.count > 1 else { return resolvedRoot }

        var resolvedURL = URL(fileURLWithPath: resolvedRoot, isDirectory: true)
        for segment in segments.dropFirst() {
            resolvedURL.appendPathComponent(segment, isDirectory: true)
        }

        return StorageLocationPathResolver.canonicalPath(resolvedURL.path)
    }

    private static func buildAliasMap(
        locations: [StorageLocation],
        canonicalRoots: [String],
        knownSubfolders: [String: [String]] = [:]
    ) -> [String: String] {
        // Phase 1: Collect root-level storage location aliases (these have priority).
        var rootAliasEntries: [String: Set<String>] = [:]

        func addRootAlias(_ alias: String, rootPath: String) {
            let normalized = normalizeAlias(alias)
            guard !normalized.isEmpty else { return }
            rootAliasEntries[normalized, default: []].insert(rootPath)
        }

        func addRootCompact(_ alias: String, rootPath: String) {
            let compact = compactAlias(alias)
            guard !compact.isEmpty else { return }
            rootAliasEntries[compact, default: []].insert(rootPath)
        }

        for location in locations {
            let rootPath = StorageLocationPathResolver.canonicalPath(location.path)
            addRootAlias(location.name, rootPath: rootPath)
            addRootAlias(URL(fileURLWithPath: rootPath).lastPathComponent, rootPath: rootPath)
            addRootCompact(location.name, rootPath: rootPath)
            addRootCompact(URL(fileURLWithPath: rootPath).lastPathComponent, rootPath: rootPath)
        }

        // Resolve root aliases first — unambiguous roots win outright.
        var resolved: [String: String] = [:]
        let rootAliasKeys = Set(rootAliasEntries.keys)
        for (alias, roots) in rootAliasEntries where roots.count == 1 {
            if let rootPath = roots.first {
                resolved[alias] = rootPath
            }
        }

        // Phase 2: Add subfolder aliases, but never override a resolved root alias.
        var subfolderCandidates: [String: Set<String>] = [:]

        func addSubfolderAlias(_ alias: String, subfolderPath: String) {
            let normalized = normalizeAlias(alias)
            guard !normalized.isEmpty else { return }
            guard !rootAliasKeys.contains(normalized) else { return }
            subfolderCandidates[normalized, default: []].insert(subfolderPath)
        }

        func addSubfolderCompact(_ alias: String, subfolderPath: String) {
            let compact = compactAlias(alias)
            guard !compact.isEmpty else { return }
            guard !rootAliasKeys.contains(compact) else { return }
            subfolderCandidates[compact, default: []].insert(subfolderPath)
        }

        for (_, subfolders) in knownSubfolders {
            for subfolder in subfolders {
                let lastComponent = URL(fileURLWithPath: subfolder).lastPathComponent
                addSubfolderAlias(lastComponent, subfolderPath: subfolder)
                addSubfolderCompact(lastComponent, subfolderPath: subfolder)
            }
        }

        for (alias, paths) in subfolderCandidates where paths.count == 1 {
            if let path = paths.first {
                resolved[alias] = path
            }
        }

        // Phase 3: Generic aliases (only when single storage root).
        if canonicalRoots.count == 1, let onlyRoot = canonicalRoots.first {
            let genericAliases = [
                "storage",
                "storage location",
                "storage locations",
                "storage-location",
                "storage-locations",
                "storage folder",
                "archive",
                "archives"
            ]
            for alias in genericAliases {
                let normalized = normalizeAlias(alias)
                if !normalized.isEmpty && resolved[normalized] == nil {
                    resolved[normalized] = onlyRoot
                }
            }
        }

        return resolved
    }

    private static func mergedKnownSubfolders(
        from knownSubfolders: [String: [String]],
        locations: [StorageLocation]
    ) -> [String: [String]] {
        var merged: [String: Set<String>] = [:]

        for (rawRootPath, rawSubfolders) in knownSubfolders {
            let canonicalRootPath = StorageLocationPathResolver.canonicalPath(rawRootPath)
            guard !canonicalRootPath.isEmpty else { continue }

            for rawSubfolderPath in rawSubfolders {
                let canonicalSubfolderPath = StorageLocationPathResolver.canonicalPath(rawSubfolderPath)
                guard !canonicalSubfolderPath.isEmpty else { continue }
                merged[canonicalRootPath, default: []].insert(canonicalSubfolderPath)
            }
        }

        for location in locations {
            let rootPath = StorageLocationPathResolver.canonicalPath(location.path)
            guard !rootPath.isEmpty else { continue }

            if merged[rootPath]?.isEmpty != false {
                let discovered = discoverSubfolders(at: rootPath, maxDepth: 3, maxCount: 500)
                if !discovered.isEmpty {
                    merged[rootPath, default: []].formUnion(discovered)
                }
            }
        }

        return merged.reduce(into: [String: [String]]()) { result, entry in
            result[entry.key] = Array(entry.value).sorted()
        }
    }

    private static func discoverSubfolders(
        at rootPath: String,
        maxDepth: Int,
        maxCount: Int
    ) -> [String] {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }

        var discovered: [String] = []
        var seenPaths: Set<String> = []

        func scan(_ directoryURL: URL, depth: Int) {
            guard depth <= maxDepth, discovered.count < maxCount else { return }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            let subdirectories = contents.compactMap { item -> URL? in
                guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    return nil
                }
                return item
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }

            for subdirectory in subdirectories {
                let canonicalPath = StorageLocationPathResolver.canonicalPath(subdirectory.path)
                guard !canonicalPath.isEmpty else { continue }
                guard seenPaths.insert(canonicalPath).inserted else { continue }

                discovered.append(canonicalPath)
                guard discovered.count < maxCount else { break }

                scan(subdirectory, depth: depth + 1)
                guard discovered.count < maxCount else { break }
            }
        }

        scan(rootURL, depth: 1)
        return discovered
    }

    private static func normalizeAlias(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let lowered = trimmed.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return lowered
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func compactAlias(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
