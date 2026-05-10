import re

with open("Sources/SortyLib/Views/AppCommands.swift", "r") as f:
    content = f.read()

replacements = [
    (r'Button\("About Sorty"\)', 'Button("About Sorty", systemImage: "info.circle")'),
    (r'Button\("Check for Updates\.\.\."\)', 'Button("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")'),
    (r'Button\("New Session"\)', 'Button("New Session", systemImage: "plus.square")'),
    (r'Button\("Open Directory\.\.\."\)', 'Button("Open Directory...", systemImage: "folder")'),
    (r'Button\("Export Results\.\.\."\)', 'Button("Export Results...", systemImage: "square.and.arrow.up")'),
    (r'Button\("Select All Files"\)', 'Button("Select All Files", systemImage: "checkmark.circle")'),
    (r'Button\(\(appState\?\.showingSidebar \?\? true\) \? "Hide Sidebar" : "Show Sidebar"\)', 'Button((appState?.showingSidebar ?? true) ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left")'),
    (r'Button\(item\.title\) \{', 'Button(item.title, systemImage: item.systemImage) {'),
    (r'Button\("Start Organization"\)', 'Button("Start Organization", systemImage: "play.circle")'),
    (r'Button\("Regenerate Organization"\)', 'Button("Regenerate Organization", systemImage: "arrow.clockwise")'),
    (r'Button\("Apply Changes"\)', 'Button("Apply Changes", systemImage: "checkmark.circle.fill")'),
    (r'Button\("Preview Changes"\)', 'Button("Preview Changes", systemImage: "eye")'),
    (r'Button\("Cancel"\)', 'Button("Cancel", systemImage: "xmark.circle")'),
    (r'Button\("Open Dashboard"\)', 'Button("Open Dashboard", systemImage: "chart.bar")'),
    (r'Button\("Start Honing Session"\)', 'Button("Start Honing Session", systemImage: "target")'),
    (r'Button\("View Statistics"\)', 'Button("View Statistics", systemImage: "chart.pie")'),
    (r'Button\("Pause Learning"\)', 'Button("Pause Learning", systemImage: "pause.circle")'),
    (r'Button\("Export Learning Profile\.\.\."\)', 'Button("Export Learning Profile...", systemImage: "square.and.arrow.up")'),
    (r'Button\("Import Learning Profile\.\.\."\)', 'Button("Import Learning Profile...", systemImage: "square.and.arrow.down")'),
    (r'Button\("Open History"\)', 'Button("Open History", systemImage: "clock")'),
    (r'Button\("Export History as CSV\.\.\."\)', 'Button("Export History as CSV...", systemImage: "tablecells")'),
    (r'Button\("Export History as JSON\.\.\."\)', 'Button("Export History as JSON...", systemImage: "curlybraces")'),
    (r'Button\("Import History\.\.\."\)', 'Button("Import History...", systemImage: "square.and.arrow.down")'),
    (r'Button\("Clear History\.\.\."\)', 'Button("Clear History...", systemImage: "trash")'),
    (r'Button\("Accreditations"\)', 'Button("Accreditations", systemImage: "rosette")'),
    (r'Button\("Internet Access Policy"\)', 'Button("Internet Access Policy", systemImage: "network")'),
    (r'Button\("Sorty Help"\)', 'Button("Sorty Help", systemImage: "questionmark.circle")'),
    (r'Link\("Documentation", destination: URL\(string: "([^"]+)"\)!\)', r'Link(destination: URL(string: "\1")!) { Label("Documentation", systemImage: "book") }'),
    (r'Link\("Report Issue", destination: URL\(string: "([^"]+)"\)!\)', r'Link(destination: URL(string: "\1")!) { Label("Report Issue", systemImage: "ladybug") }'),
    (r'Link\("Support the Developer", destination: URL\(string: "([^"]+)"\)!\)', r'Link(destination: URL(string: "\1")!) { Label("Support the Developer", systemImage: "heart") }'),
    (r'Button\("Restart Onboarding\.\.\."\)', 'Button("Restart Onboarding...", systemImage: "sparkles")'),
    (r'Button\("Feature Tour\.\.\."\)', 'Button("Feature Tour...", systemImage: "map")'),
    (r'Button\("Delete All Usage Data\.\.\."\)', 'Button("Delete All Usage Data...", systemImage: "trash")'),
    (r'Link\("GitHub Repository", destination: URL\(string: "([^"]+)"\)!\)', r'Link(destination: URL(string: "\1")!) { Label("GitHub Repository", systemImage: "chevron.left.forwardslash.chevron.right") }'),
    (r'Button\("Thank you for using Sorty"\)', 'Button("Thank you for using Sorty", systemImage: "heart.fill")')
]

for old, new in replacements:
    content = re.sub(old, new, content)

with open("Sources/SortyLib/Views/AppCommands.swift", "w") as f:
    f.write(content)
