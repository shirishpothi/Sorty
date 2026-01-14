//
//  ExclusionRulesView.swift
//  Sorty
//
//  Modern exclusion rules management with grouped cards and improved UX
//

import SwiftUI

struct ExclusionRulesView: View {
    @EnvironmentObject var rulesManager: ExclusionRulesManager
    @State private var showingAddRule = false
    @State private var searchText = ""
    @State private var contentOpacity: Double = 0

    private var filteredRules: [ExclusionRule] {
        if searchText.isEmpty {
            return rulesManager.rules
        }
        return rulesManager.rules.filter {
            $0.displayDescription.localizedCaseInsensitiveContains(searchText) ||
            $0.type.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var groupedRules: [(String, [ExclusionRule])] {
        let groups: [(String, [ExclusionRuleType])] = [
            ("Pattern Rules", [.fileExtension, .fileName, .folderName, .pathContains, .regex]),
            ("Size & Date", [.fileSize, .creationDate, .modificationDate]),
            ("System Rules", [.hiddenFiles, .systemFiles, .fileType]),
            ("Custom", [.customScript])
        ]
        
        return groups.compactMap { (title, types) in
            let rules = filteredRules.filter { types.contains($0.type) }
            return rules.isEmpty ? nil : (title, rules)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()

            ZStack {
                if rulesManager.rules.isEmpty {
                    EmptyExclusionRulesView(onAddRule: {
                        HapticFeedbackManager.shared.tap()
                        showingAddRule = true
                    })
                    .transition(TransitionStyles.scaleAndFade)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Search bar
                            searchBar
                                .padding(.horizontal, 20)
                                .padding(.top, 16)
                            
                            // Grouped rules
                            ForEach(Array(groupedRules.enumerated()), id: \.1.0) { index, group in
                                RuleGroupCard(
                                    title: group.0,
                                    rules: group.1,
                                    rulesManager: rulesManager
                                )
                                .animatedAppearance(delay: Double(index) * 0.05)
                            }
                            
                            if filteredRules.isEmpty && !searchText.isEmpty {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                    Text("No rules match '\(searchText)'")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: rulesManager.rules.isEmpty)
        }
        .navigationTitle("Exclusion Rules")
        .sheet(isPresented: $showingAddRule) {
            AddExclusionRuleView(rulesManager: rulesManager)
                .modalBounce()
        }
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Exclusion Rules")
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Text("\(rulesManager.enabledRulesCount) active")
                        .foregroundStyle(.green)
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text("\(rulesManager.rules.count - rulesManager.enabledRulesCount) disabled")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .contentTransition(.numericText())
            }
            .animatedAppearance(delay: 0.05)

            Spacer()

            Button {
                HapticFeedbackManager.shared.tap()
                showingAddRule = true
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("AddExclusionRuleButton")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            
            TextField("Search rules...", text: $searchText)
                .textFieldStyle(.plain)
            
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Empty State View

struct EmptyExclusionRulesView: View {
    let onAddRule: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "eye.slash.circle")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Exclusion Rules")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Add rules to exclude certain files or folders from organization")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Common use cases:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 6) {
                    RuleExamplePill(icon: "doc.badge.gearshape", text: ".DS_Store")
                    RuleExamplePill(icon: "folder", text: "node_modules")
                    RuleExamplePill(icon: "scalemass", text: "> 100MB")
                }
            }

            Button {
                onAddRule()
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }
}

struct RuleExamplePill: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Rule Group Card

struct RuleGroupCard: View {
    let title: String
    let rules: [ExclusionRule]
    @ObservedObject var rulesManager: ExclusionRulesManager
    
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticFeedbackManager.shared.tap()
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    Text("\(rules.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                VStack(spacing: 0) {
                    ForEach(rules) { rule in
                        ExclusionRuleRow(rule: rule, rulesManager: rulesManager)
                        
                        if rule.id != rules.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Exclusion Rule Row

struct ExclusionRuleRow: View {
    let rule: ExclusionRule
    @ObservedObject var rulesManager: ExclusionRulesManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: iconForType(rule.type))
                .font(.system(size: 14))
                .foregroundStyle(rule.isEnabled ? colorForType(rule.type) : .secondary)
                .frame(width: 28, height: 28)
                .background((rule.isEnabled ? colorForType(rule.type) : .secondary).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.displayDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)
                    
                    if rule.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 6) {
                    Text(rule.type.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let description = rule.description, !description.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()
            
            if isHovered {
                Button {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        rulesManager.removeRule(rule)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    HapticFeedbackManager.shared.selection()
                    var updatedRule = rule
                    updatedRule.isEnabled = newValue
                    rulesManager.updateRule(updatedRule)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private func iconForType(_ type: ExclusionRuleType) -> String {
        switch type {
        case .fileExtension: return "doc.badge.gearshape"
        case .fileName: return "doc"
        case .folderName: return "folder"
        case .pathContains: return "arrow.triangle.branch"
        case .regex: return "text.magnifyingglass"
        case .fileSize: return "scalemass"
        case .creationDate: return "calendar.badge.plus"
        case .modificationDate: return "calendar.badge.clock"
        case .hiddenFiles: return "eye.slash"
        case .systemFiles: return "gearshape.2"
        case .fileType: return "doc.on.doc"
        case .customScript: return "applescript"
        }
    }
    
    private func colorForType(_ type: ExclusionRuleType) -> Color {
        switch type {
        case .fileExtension, .fileName, .folderName, .pathContains, .regex:
            return .blue
        case .fileSize, .creationDate, .modificationDate:
            return .orange
        case .hiddenFiles, .systemFiles, .fileType:
            return .purple
        case .customScript:
            return .green
        }
    }
}

// MARK: - Add Exclusion Rule View

struct AddExclusionRuleView: View {
    @ObservedObject var rulesManager: ExclusionRulesManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedType: ExclusionRuleType = .fileExtension
    @State private var pattern: String = ""
    @State private var description: String = ""
    @State private var numericValue: Double = 100
    @State private var comparisonGreater: Bool = true
    @State private var selectedFileTypeCategory: FileTypeCategory = .images

    @State private var testInput: String = ""
    @State private var isMatch: Bool = false
    @State private var appeared = false
    
    private let ruleCategories: [(String, [ExclusionRuleType])] = [
        ("Pattern", [.fileExtension, .fileName, .folderName, .pathContains, .regex]),
        ("Size & Date", [.fileSize, .creationDate, .modificationDate]),
        ("System", [.hiddenFiles, .systemFiles, .fileType])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    HapticFeedbackManager.shared.tap()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Text("Add Exclusion Rule")
                    .font(.headline)

                Spacer()

                Button("Add Rule") {
                    HapticFeedbackManager.shared.success()
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValidInput)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Rule Type Selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Rule Type")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        ForEach(ruleCategories, id: \.0) { category in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(category.0)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(category.1, id: \.self) { type in
                                        RuleTypeChip(
                                            type: type,
                                            isSelected: selectedType == type
                                        ) {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                                selectedType = type
                                            }
                                            HapticFeedbackManager.shared.selection()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Configuration
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Configuration")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        ruleConfigurationView
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Description
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description (optional)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        TextField("e.g., Skip large media files", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Test Section
                    if selectedType.requiresPattern && selectedType != .fileType {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Test Rule")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                if !testInput.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: isMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        Text(isMatch ? "Matches" : "No match")
                                    }
                                    .font(.caption)
                                    .foregroundColor(isMatch ? .green : .secondary)
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            
                            TextField(testPlaceholder, text: $testInput)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: testInput) { _, _ in checkMatch() }
                                .onChange(of: pattern) { _, _ in checkMatch() }
                                .onChange(of: selectedType) { _, _ in checkMatch() }
                        }
                        .padding(16)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isMatch)
                    }
                    
                    // Help Text
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text(helpTextForType(selectedType))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(20)
            }
        }
        .frame(width: 500, height: 580)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                appeared = true
            }
        }
    }
    
    @ViewBuilder
    private var ruleConfigurationView: some View {
        switch selectedType {
        case .fileSize:
            HStack(spacing: 12) {
                TextField("Size", value: $numericValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                
                Text("MB")
                    .foregroundStyle(.secondary)
                
                Picker("", selection: $comparisonGreater) {
                    Text("Larger than").tag(true)
                    Text("Smaller than").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
        case .creationDate, .modificationDate:
            HStack(spacing: 12) {
                TextField("Days", value: $numericValue, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                
                Text("days ago")
                    .foregroundStyle(.secondary)

                Picker("", selection: $comparisonGreater) {
                    Text("Older than").tag(true)
                    Text("Newer than").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

        case .fileType:
            VStack(alignment: .leading, spacing: 8) {
                Picker("Category", selection: $selectedFileTypeCategory) {
                    ForEach(FileTypeCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.icon)
                            .tag(category)
                    }
                }
                .pickerStyle(.menu)

                Text("Includes: \(selectedFileTypeCategory.extensions.prefix(5).joined(separator: ", "))\(selectedFileTypeCategory.extensions.count > 5 ? "..." : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .hiddenFiles, .systemFiles:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("No configuration needed")
                    .foregroundStyle(.secondary)
            }

        case .customScript:
            Text("Custom scripts are not yet implemented.")
                .font(.caption)
                .foregroundStyle(.orange)

        default:
            VStack(alignment: .leading, spacing: 6) {
                TextField("Pattern", text: $pattern)
                    .textFieldStyle(.roundedBorder)
                
                Text(patternHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var patternHint: String {
        switch selectedType {
        case .fileExtension: return "Enter extension without dot (e.g., 'txt', 'pdf')"
        case .fileName: return "Enter full filename (e.g., '.DS_Store')"
        case .folderName: return "Enter folder name (e.g., 'node_modules')"
        case .pathContains: return "Enter path fragment (e.g., '/backup/')"
        case .regex: return "Enter regular expression pattern"
        default: return ""
        }
    }

    private var isValidInput: Bool {
        switch selectedType {
        case .hiddenFiles, .systemFiles, .fileType:
            return true
        case .fileSize, .creationDate, .modificationDate:
            return numericValue > 0
        case .customScript:
            return false
        default:
            return !pattern.isEmpty
        }
    }

    private func checkMatch() {
        guard !testInput.isEmpty, !pattern.isEmpty else {
            isMatch = false
            return
        }

        let fileName = testInput.contains(".") ? String(testInput.split(separator: ".").dropLast().joined(separator: ".")) : testInput
        let fileExtension = testInput.contains(".") ? String(testInput.split(separator: ".").last ?? "") : ""

        let file = FileItem(
            path: "/path/to/\(testInput)",
            name: fileName,
            extension: fileExtension,
            size: Int64((Double(testInput) ?? 0) * 1024 * 1024),
            isDirectory: false,
            creationDate: Date()
        )

        let rule = ExclusionRule(
            type: selectedType,
            pattern: pattern,
            numericValue: numericValue,
            comparisonGreater: comparisonGreater
        )

        let newMatch = rule.matches(file)
        if newMatch != isMatch {
            HapticFeedbackManager.shared.selection()
        }
        isMatch = newMatch
    }

    private var testPlaceholder: String {
        switch selectedType {
        case .fileExtension: return "document.txt"
        case .fileName: return ".DS_Store"
        case .folderName: return "node_modules"
        case .pathContains: return "/Users/me/backup/file.txt"
        case .regex: return "IMG_0001.jpg"
        default: return "Enter test value"
        }
    }

    private func addRule() {
        var rule: ExclusionRule
        
        switch selectedType {
        case .fileSize, .creationDate, .modificationDate:
            rule = ExclusionRule(
                type: selectedType,
                pattern: pattern,
                description: description.isEmpty ? nil : description,
                numericValue: numericValue,
                comparisonGreater: comparisonGreater
            )
        case .fileType:
            rule = ExclusionRule(
                type: selectedType,
                pattern: "",
                description: description.isEmpty ? nil : description,
                fileTypeCategory: selectedFileTypeCategory
            )
        default:
            rule = ExclusionRule(
                type: selectedType,
                pattern: pattern,
                description: description.isEmpty ? nil : description
            )
        }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            rulesManager.addRule(rule)
        }
        dismiss()
    }

    private func helpTextForType(_ type: ExclusionRuleType) -> String {
        switch type {
        case .fileExtension: return "Excludes all files with this extension"
        case .fileName: return "Excludes files with this exact name"
        case .folderName: return "Excludes all folders with this name"
        case .pathContains: return "Excludes paths containing this text"
        case .regex: return "Excludes files matching this regex pattern"
        case .fileSize: return "Excludes files based on size threshold"
        case .creationDate: return "Excludes files created before/after threshold"
        case .modificationDate: return "Excludes files modified before/after threshold"
        case .hiddenFiles: return "Excludes files starting with '.' (hidden files)"
        case .systemFiles: return "Excludes macOS system files (.DS_Store, etc.)"
        case .fileType: return "Excludes entire categories of file types"
        case .customScript: return "Run custom AppleScript (advanced)"
        }
    }
}

// MARK: - Rule Type Chip

struct RuleTypeChip: View {
    let type: ExclusionRuleType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: iconForType(type))
                    .font(.caption)
                Text(type.rawValue)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.1))
            .foregroundColor(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    private func iconForType(_ type: ExclusionRuleType) -> String {
        switch type {
        case .fileExtension: return "doc.badge.gearshape"
        case .fileName: return "doc"
        case .folderName: return "folder"
        case .pathContains: return "arrow.triangle.branch"
        case .regex: return "text.magnifyingglass"
        case .fileSize: return "scalemass"
        case .creationDate: return "calendar.badge.plus"
        case .modificationDate: return "calendar.badge.clock"
        case .hiddenFiles: return "eye.slash"
        case .systemFiles: return "gearshape.2"
        case .fileType: return "doc.on.doc"
        case .customScript: return "applescript"
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutResult(for: subviews, in: proposal.width ?? 0)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutResult(for: subviews, in: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layoutResult(for subviews: Subviews, in width: CGFloat) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return (positions, y + rowHeight)
    }
}

#Preview {
    ExclusionRulesView()
        .environmentObject(ExclusionRulesManager())
        .frame(width: 600, height: 550)
}
