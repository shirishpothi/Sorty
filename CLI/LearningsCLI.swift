//
//  LearningsCLI.swift
//  FileOrganizer
//
//  CLI tool for The Learnings feature - trainable, local-first file organization
//
//  Usage:
//    learnings init-project --name "My Project" --root ~/Downloads
//    learnings add-example --project project.json --src /path/from --dst /path/to
//    learnings analyze --project project.json --sample-size 100 --export-preview preview.json
//    learnings apply --project project.json --job-id <id> --backup-dir ~/backup
//    learnings rollback --project project.json --job-id <id>
//    learnings export-rules --project project.json --out rules.json
//

import Foundation
import FileOrganizerLib

// MARK: - CLI Entry Point

@main
struct LearningsCLI {
    static func main() async {
        let args = CommandLine.arguments
        
        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }
        
        let command = args[1]
        
        do {
            switch command {
            case "init-project":
                try await handleInitProject(args: Array(args.dropFirst(2)))
            case "add-example":
                try await handleAddExample(args: Array(args.dropFirst(2)))
            case "analyze":
                try await handleAnalyze(args: Array(args.dropFirst(2)))
            case "apply":
                try await handleApply(args: Array(args.dropFirst(2)))
            case "rollback":
                try await handleRollback(args: Array(args.dropFirst(2)))
            case "export-rules":
                try await handleExportRules(args: Array(args.dropFirst(2)))
            case "list-projects":
                try await handleListProjects()
            case "--help", "-h", "help":
                printUsage()
            case "--version", "-v":
                print("learnings CLI v1.0.0")
            default:
                printError("Unknown command: \(command)")
                printUsage()
                exit(1)
            }
        } catch {
            printError(error.localizedDescription)
            exit(1)
        }
    }
    
    // MARK: - Command Handlers
    
    static func handleInitProject(args: [String]) async throws {
        var name: String?
        var rootPaths: [String] = []
        var exampleFolders: [String] = []
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--name", "-n":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--name") }
                name = args[i]
            case "--root", "-r":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--root") }
                rootPaths.append(expandPath(args[i]))
            case "--example", "-e":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--example") }
                exampleFolders.append(expandPath(args[i]))
            default:
                throw CLIError.unknownOption(args[i])
            }
            i += 1
        }
        
        guard let projectName = name else {
            throw CLIError.missingRequired("--name")
        }
        
        let project = LearningsProject(
            name: projectName,
            rootPaths: rootPaths,
            exampleFolders: exampleFolders
        )
        
        let store = LearningsProjectStore()
        try await store.save(project)
        
        printSuccess("Created project '\(projectName)'")
        print("  Root paths: \(rootPaths.count)")
        print("  Example folders: \(exampleFolders.count)")
        print("")
        print("Next: Add examples with 'learnings add-example' or analyze with 'learnings analyze'")
    }
    
    static func handleAddExample(args: [String]) async throws {
        var projectName: String?
        var srcPath: String?
        var dstPath: String?
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--project", "-p":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--project") }
                projectName = args[i]
            case "--src", "-s":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--src") }
                srcPath = expandPath(args[i])
            case "--dst", "-d":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--dst") }
                dstPath = expandPath(args[i])
            default:
                throw CLIError.unknownOption(args[i])
            }
            i += 1
        }
        
        guard let name = projectName else { throw CLIError.missingRequired("--project") }
        guard let src = srcPath else { throw CLIError.missingRequired("--src") }
        guard let dst = dstPath else { throw CLIError.missingRequired("--dst") }
        
        let store = LearningsProjectStore()
        var project = try await store.load(name: name)
        
        let example = LabeledExample(
            srcPath: src,
            dstPath: dst,
            action: .addToExamples
        )
        project.addExample(example)
        
        try await store.save(project)
        
        printSuccess("Added example to '\(name)'")
        print("  From: \(src)")
        print("  To:   \(dst)")
        print("  Total examples: \(project.labeledExamples.count)")
    }
    
    static func handleAnalyze(args: [String]) async throws {
        var projectName: String?
        var sampleSize: Int = 50
        var exportPath: String?
        var dryRun = true
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--project", "-p":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--project") }
                projectName = args[i]
            case "--sample-size", "-s":
                i += 1
                guard i < args.count, let size = Int(args[i]) else { throw CLIError.missingValue("--sample-size") }
                sampleSize = size
            case "--export-preview", "-o":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--export-preview") }
                exportPath = expandPath(args[i])
            case "--no-dry-run":
                dryRun = false
            default:
                throw CLIError.unknownOption(args[i])
            }
            i += 1
        }
        
        guard let name = projectName else { throw CLIError.missingRequired("--project") }
        
        let store = LearningsProjectStore()
        var project = try await store.load(name: name)
        project.options.sampleSize = sampleSize
        project.options.dryRun = dryRun
        
        print("🔍 Analyzing project '\(name)'...")
        print("  Sample size: \(sampleSize)")
        print("  Dry run: \(dryRun)")
        print("")
        
        let analyzer = await LearningsAnalyzer()
        let result = try await analyzer.analyze(project: project)
        
        // Update project with inferred rules
        project.updateRules(result.inferredRules)
        try await store.save(project)
        
        // Print summary
        printHeader("Analysis Results")
        print("")
        
        print("📋 Rules Inferred: \(result.inferredRules.count)")
        for rule in result.inferredRules.prefix(5) {
            print("   • \(rule.explanation)")
        }
        if result.inferredRules.count > 5 {
            print("   ... and \(result.inferredRules.count - 5) more")
        }
        print("")
        
        print("📁 Proposed Mappings: \(result.proposedMappings.count)")
        print("   High confidence:   \(result.confidenceSummary.high)")
        print("   Medium confidence: \(result.confidenceSummary.medium)")
        print("   Low confidence:    \(result.confidenceSummary.low)")
        print("")
        
        if !result.conflicts.isEmpty {
            print("⚠️  Conflicts: \(result.conflicts.count)")
        }
        
        // Export preview if requested
        if let path = exportPath {
            let data = try result.toJSON()
            try data.write(to: URL(fileURLWithPath: path))
            printSuccess("Preview exported to: \(path)")
        }
        
        // Print human summary
        print("")
        printHeader("Summary")
        for line in result.humanSummary {
            print("  \(line)")
        }
    }
    
    static func handleApply(args: [String]) async throws {
        var projectName: String?
        var jobId: String?
        var backupDir: String?
        var staged = false
        var confirm = false
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--project", "-p":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--project") }
                projectName = args[i]
            case "--job-id", "-j":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--job-id") }
                jobId = args[i]
            case "--backup-dir", "-b":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--backup-dir") }
                backupDir = expandPath(args[i])
            case "--staged":
                staged = true
            case "--confirm":
                confirm = true
            default:
                throw CLIError.unknownOption(args[i])
            }
            i += 1
        }
        
        guard let name = projectName else { throw CLIError.missingRequired("--project") }
        
        guard confirm else {
            printWarning("This will move files. Add --confirm to proceed.")
            print("")
            print("Recommended: Run 'learnings analyze' first to review proposed changes.")
            exit(0)
        }
        
        let store = LearningsProjectStore()
        var project = try await store.load(name: name)
        
        // Run analysis to get current proposals
        let analyzer = await LearningsAnalyzer()
        let result = try await analyzer.analyze(project: project)
        
        // Create job manifest
        let backupMode: BackupMode = backupDir != nil ? .copyToBackupDir : .none
        var entries: [JobManifestEntry] = []
        
        for mapping in result.proposedMappings where mapping.confidenceLevel == .high || !staged {
            let backupPath = backupDir.map { "\($0)/\(UUID().uuidString)_\(URL(fileURLWithPath: mapping.srcPath).lastPathComponent)" }
            entries.append(JobManifestEntry(
                originalPath: mapping.srcPath,
                destinationPath: mapping.proposedDstPath,
                backupPath: backupPath
            ))
        }
        
        let job = JobManifest(
            id: jobId ?? UUID().uuidString,
            projectName: name,
            entries: entries,
            backupMode: backupMode
        )
        
        print("📦 Applying \(entries.count) file moves...")
        if let backup = backupDir {
            print("   Backup directory: \(backup)")
        }
        print("")
        
        // Execute moves
        let fm = FileManager.default
        var successCount = 0
        var failCount = 0
        
        for entry in entries {
            do {
                // Create backup if needed
                if let backupPath = entry.backupPath {
                    try fm.createDirectory(
                        at: URL(fileURLWithPath: backupPath).deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try fm.copyItem(atPath: entry.originalPath, toPath: backupPath)
                }
                
                // Create destination directory
                let destDir = URL(fileURLWithPath: entry.destinationPath).deletingLastPathComponent()
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                
                // Move file
                try fm.moveItem(atPath: entry.originalPath, toPath: entry.destinationPath)
                
                successCount += 1
            } catch {
                printError("Failed to move \(entry.originalPath): \(error.localizedDescription)")
                failCount += 1
            }
        }
        
        // Save job to history
        project.addJob(job)
        try await store.save(project)
        
        print("")
        printSuccess("Applied \(successCount) moves, \(failCount) failed")
        print("Job ID: \(job.id)")
    }
    
    static func handleRollback(args: [String]) async throws {
        var projectName: String?
        var jobId: String?
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--project", "-p":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--project") }
                projectName = args[i]
            case "--job-id", "-j":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--job-id") }
                jobId = args[i]
            default:
                throw CLIError.unknownOption(args[i])
            }
            i += 1
        }
        
        guard let name = projectName else { throw CLIError.missingRequired("--project") }
        guard let jid = jobId else { throw CLIError.missingRequired("--job-id") }
        
        let store = LearningsProjectStore()
        let project = try await store.load(name: name)
        
        guard let job = project.jobHistory.first(where: { $0.id == jid }) else {
            throw CLIError.jobNotFound(jid)
        }
        
        print("🔄 Rolling back job \(jid)...")
        print("   Files: \(job.entries.count)")
        print("")
        
        let fm = FileManager.default
        var successCount = 0
        var failCount = 0
        
        for entry in job.entries {
            do {
                // Restore from backup if available
                if let backupPath = entry.backupPath, fm.fileExists(atPath: backupPath) {
                    // Remove current destination
                    if fm.fileExists(atPath: entry.destinationPath) {
                        try fm.removeItem(atPath: entry.destinationPath)
                    }
                    // Restore original
                    try fm.moveItem(atPath: backupPath, toPath: entry.originalPath)
                } else {
                    // Just move back
                    try fm.moveItem(atPath: entry.destinationPath, toPath: entry.originalPath)
                }
                successCount += 1
            } catch {
                printError("Failed to restore \(entry.originalPath): \(error.localizedDescription)")
                failCount += 1
            }
        }
        
        print("")
        printSuccess("Rolled back \(successCount) files, \(failCount) failed")
    }
    
    static func handleExportRules(args: [String]) async throws {
        var projectName: String?
        var outputPath: String?
        
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--project", "-p":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--project") }
                projectName = args[i]
            case "--out", "-o":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--out") }
                outputPath = expandPath(args[i])
            default:
                throw CLIError.unknownOption(args[i])
            }
            i += 1
        }
        
        guard let name = projectName else { throw CLIError.missingRequired("--project") }
        guard let output = outputPath else { throw CLIError.missingRequired("--out") }
        
        let store = LearningsProjectStore()
        let project = try await store.load(name: name)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(project.inferredRules)
        try data.write(to: URL(fileURLWithPath: output))
        
        printSuccess("Exported \(project.inferredRules.count) rules to: \(output)")
    }
    
    static func handleListProjects() async throws {
        let store = LearningsProjectStore()
        let projects = try await store.listProjects()
        
        if projects.isEmpty {
            print("No projects found.")
            print("")
            print("Create one with: learnings init-project --name \"My Project\" --root ~/Downloads")
        } else {
            printHeader("Available Projects")
            for project in projects {
                print("  • \(project)")
            }
        }
    }
    
    // MARK: - Utilities
    
    static func expandPath(_ path: String) -> String {
        if path.hasPrefix("~") {
            return (path as NSString).expandingTildeInPath
        }
        return path
    }
    
    static func printUsage() {
        print("""
        learnings - The Learnings CLI for FileOrganizer
        
        USAGE:
            learnings <command> [options]
        
        COMMANDS:
            init-project    Create a new learnings project
            add-example     Add a labeled example (src → dst mapping)
            analyze         Analyze files and generate proposals
            apply           Apply proposed changes (with backup)
            rollback        Rollback a previous apply job
            export-rules    Export inferred rules to JSON
            list-projects   List all projects
        
        EXAMPLES:
            # Create a new project
            learnings init-project --name "Photos" --root ~/Downloads --example ~/OrganizedPhotos
            
            # Add examples manually
            learnings add-example --project "Photos" --src ~/Downloads/IMG_001.jpg --dst ~/Photos/2024/IMG_001.jpg
            
            # Analyze and export preview
            learnings analyze --project "Photos" --sample-size 100 --export-preview preview.json
            
            # Apply with backup (requires --confirm)
            learnings apply --project "Photos" --backup-dir ~/backup --confirm
            
            # Rollback if needed
            learnings rollback --project "Photos" --job-id <job-id>
        
        OPTIONS:
            --help, -h      Show this help
            --version, -v   Show version
        """)
    }
    
    static func printHeader(_ text: String) {
        print("━━━ \(text) ━━━")
    }
    
    static func printSuccess(_ message: String) {
        print("✅ \(message)")
    }
    
    static func printWarning(_ message: String) {
        print("⚠️  \(message)")
    }
    
    static func printError(_ message: String) {
        fputs("❌ Error: \(message)\n", stderr)
    }
}

// MARK: - CLI Errors

enum CLIError: LocalizedError {
    case missingRequired(String)
    case missingValue(String)
    case unknownOption(String)
    case projectNotFound(String)
    case jobNotFound(String)
    case fileNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRequired(let opt):
            return "Missing required option: \(opt)"
        case .missingValue(let opt):
            return "Missing value for option: \(opt)"
        case .unknownOption(let opt):
            return "Unknown option: \(opt)"
        case .projectNotFound(let name):
            return "Project not found: \(name)"
        case .jobNotFound(let id):
            return "Job not found: \(id)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
