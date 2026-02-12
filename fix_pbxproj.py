#!/usr/bin/env python3
"""Add 58 missing Swift source files to the Xcode project file."""

import re

PBXPROJ = "/Users/shirishpothi/Code Projects/Sorty/Sorty.xcodeproj/project.pbxproj"

# File mapping: (filename, directory_category)
# Categories: AI, FileSystem, FinderExtension, Models, Organizer, Utilities, ViewModels,
#             Views, Components, Services, Learnings, Settings, Preview, Onboarding, DesignSystem, Managers
files = [
    ("AIProviderRow.swift", "Settings"),
    ("AdvancedSettingsView.swift", "Settings"),
    ("AutomationSettingsView.swift", "Settings"),
    ("BatchOrganizationManager.swift", "Managers"),
    ("BatchOrganizationView.swift", "Views"),
    ("CLIInstaller.swift", "Utilities"),
    ("CommentPopoverView.swift", "Preview"),
    ("CompletionStepView.swift", "Onboarding"),
    ("ConflictResolution.swift", "Models"),
    ("ConflictResolutionSheet.swift", "Views"),
    ("CopyButtonWithAnimation.swift", "Components"),
    ("CostCalculator.swift", "Utilities"),
    ("DemoStepView.swift", "Onboarding"),
    ("DesignSystemReadme.swift", "DesignSystem"),
    ("EnhancedFlatFileRow.swift", "Preview"),
    ("FinderIntegrationSettingsView.swift", "Settings"),
    ("FolderScheduler.swift", "FileSystem"),
    ("FormattedReasoningText.swift", "Preview"),
    ("GlassyBackButton.swift", "Components"),
    ("GlobalShortcutManager.swift", "Utilities"),
    ("HelpSettingsView.swift", "Settings"),
    ("LiquidGlassReasoningPopover.swift", "Preview"),
    ("LoginItemManager.swift", "Utilities"),
    ("MenuBarView.swift", "Views"),
    ("NamingInstructionsGenerator.swift", "AI"),
    ("NamingPreset.swift", "Models"),
    ("NamingPresetManager.swift", "Utilities"),
    ("NotifiCLIStatusCard.swift", "Settings"),
    ("NotificationPermissionCard.swift", "Settings"),
    ("NotificationsSettingsView.swift", "Settings"),
    ("OnboardingAudioManager.swift", "Utilities"),
    ("OnboardingStepProtocol.swift", "Onboarding"),
    ("OrganizationRulesSettingsView.swift", "Settings"),
    ("OrganizationStrategySettingsView.swift", "Settings"),
    ("OrganizingMascotView.swift", "Components"),
    ("ParameterTuningSettingsView.swift", "Settings"),
    ("PermissionsStepView.swift", "Onboarding"),
    ("PersonaChatView.swift", "Views"),
    ("PostOrganizationHoningView.swift", "Preview"),
    ("PreviewActionsView.swift", "Preview"),
    ("PreviewHeaderView.swift", "Preview"),
    ("PreviewListView.swift", "Preview"),
    ("PreviewMocks.swift", "DesignSystem"),
    ("PreviewStatsView.swift", "Preview"),
    ("ProviderSelectionStepView.swift", "Onboarding"),
    ("RefreshManager.swift", "Managers"),
    ("RuleReasoningBadge.swift", "Preview"),
    ("ScheduleEditorView.swift", "Views"),
    ("SettingsCategory.swift", "Settings"),
    ("SettingsComponents.swift", "Settings"),
    ("SimulatedDemoAnimationView.swift", "Onboarding"),
    ("SortyCard.swift", "DesignSystem"),
    ("SortyDesignSystem.swift", "DesignSystem"),
    ("SteeringPromptManager.swift", "Utilities"),
    ("TagDotsView.swift", "Preview"),
    ("TroubleshootingSettingsView.swift", "Settings"),
    ("WelcomeStepView.swift", "Onboarding"),
    ("WorkflowSelectionStepView.swift", "Onboarding"),
]

# Generate IDs
# File refs: AABBCC110001000000000060 + index
# Build files: AABBCC220002000000000060 + index
def file_ref_id(idx):
    return f"AABBCC11000100000000{0x60 + idx:04X}"

def build_file_id(idx):
    return f"AABBCC22000200000000{0x60 + idx:04X}"

# New group IDs
SETTINGS_GROUP_ID = "AABBCC660000000000000001"
PREVIEW_GROUP_ID = "AABBCC660000000000000002"
ONBOARDING_GROUP_ID = "AABBCC660000000000000003"
DESIGNSYSTEM_GROUP_ID = "AABBCC660000000000000004"
MANAGERS_GROUP_ID = "AABBCC660000000000000005"

# Existing group IDs
GROUP_IDS = {
    "AI": "3353FC222F0124320097CD23",
    "FileSystem": "3353FC252F0124320097CD23",
    "FinderExtension": "3353FC282F0124320097CD23",
    "Models": "3353FC2F2F0124320097CD23",
    "Organizer": "3353FC332F0124320097CD23",
    "Utilities": "3353FC382F0124320097CD23",
    "ViewModels": "3353FC3A2F0124320097CD23",
    "Views": "3353FC442F0124320097CD23",
    "Components": "AABBCC550000000000000001",
    "Services": "AABBCC440000000000000001",
    "Learnings": "141AC570FAC743F08B8A7DD4",
    "Settings": SETTINGS_GROUP_ID,
    "Preview": PREVIEW_GROUP_ID,
    "Onboarding": ONBOARDING_GROUP_ID,
    "DesignSystem": DESIGNSYSTEM_GROUP_ID,
    "Managers": MANAGERS_GROUP_ID,
}

with open(PBXPROJ, 'r') as f:
    content = f.read()

# 1. Add PBXFileReference entries (after line with AutomationManager.swift file ref, before AppIcon.icns)
file_ref_entries = []
for idx, (fname, cat) in enumerate(files):
    fid = file_ref_id(idx)
    file_ref_entries.append(
        f'\t\t{fid} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};'
    )

file_ref_block = "\n".join(file_ref_entries)

# Insert after the AutomationManager.swift file ref line
content = content.replace(
    '\t\tAABBCC110001000000000031 /* AutomationManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AutomationManager.swift; sourceTree = "<group>"; };',
    '\t\tAABBCC110001000000000031 /* AutomationManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AutomationManager.swift; sourceTree = "<group>"; };\n' + file_ref_block,
    1
)

# 2. Add PBXBuildFile entries (after AutomationManager.swift build file, before blank line)
build_file_entries = []
for idx, (fname, cat) in enumerate(files):
    bid = build_file_id(idx)
    fid = file_ref_id(idx)
    build_file_entries.append(
        f'\t\t{bid} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fid} /* {fname} */; }};'
    )

build_file_block = "\n".join(build_file_entries)

content = content.replace(
    '\t\tAABBCC220002000000000031 /* AutomationManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABBCC110001000000000031 /* AutomationManager.swift */; };\n\n\t\tAABBCC220002000000000002',
    '\t\tAABBCC220002000000000031 /* AutomationManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABBCC110001000000000031 /* AutomationManager.swift */; };\n' + build_file_block + '\n\n\t\tAABBCC220002000000000002',
    1
)

# 3. Add files to existing groups
# For each existing group, we need to add the file ref IDs to the children list

# Collect files per group
files_per_group = {}
for idx, (fname, cat) in enumerate(files):
    fid = file_ref_id(idx)
    files_per_group.setdefault(cat, []).append((fid, fname))

# Add to AI group - insert before closing ");" of children
def add_to_group(content, group_marker, new_children):
    """Add children to an existing group by finding its children block."""
    lines = content.split('\n')
    result = []
    in_target_group = False
    found_group = False
    brace_depth = 0
    
    for i, line in enumerate(lines):
        result.append(line)
        if group_marker in line and '= {' in line and 'isa = PBXGroup' not in line:
            # Check if next line has isa = PBXGroup
            pass
        if group_marker in line and ('isa = PBXGroup' in line or '/* ' in line):
            in_target_group = True
            found_group = True
            continue
        if in_target_group:
            if 'isa = PBXGroup;' in line:
                continue
            if 'children = (' in line:
                continue
            if line.strip() == ');' and not found_group:
                continue
    
    return '\n'.join(result)

# Better approach: use regex to find groups and add children
for cat, children in files_per_group.items():
    if cat in ("Settings", "Preview", "Onboarding", "DesignSystem", "Managers"):
        continue  # These are new groups, handled separately
    
    group_id = GROUP_IDS[cat]
    children_lines = ""
    for fid, fname in children:
        children_lines += f"\n\t\t\t\t{fid} /* {fname} */,"
    
    # Find the group and add before the closing ");" of children
    # Pattern: group_id /* GroupName */ = { ... children = ( ... ); 
    # We need to find the last child entry before ");" in this group
    
    if cat == "AI":
        # Add after AppleVisionIntelligenceAnalyzer.swift in AI group
        content = content.replace(
            '\t\t\t\tAABBCC11000100000000001D /* AppleVisionIntelligenceAnalyzer.swift */,\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/AI;',
            '\t\t\t\tAABBCC11000100000000001D /* AppleVisionIntelligenceAnalyzer.swift */,' + children_lines + '\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/AI;',
            1
        )
    elif cat == "FileSystem":
        content = content.replace(
            '\t\t\t\tAABBCC11000100000000000A /* ImageVisionAnalyzer.swift */,\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/FileSystem;',
            '\t\t\t\tAABBCC11000100000000000A /* ImageVisionAnalyzer.swift */,' + children_lines + '\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/FileSystem;',
            1
        )
    elif cat == "Models":
        content = content.replace(
            '\t\t\t\tAABBCC11000100000000000E /* ExclusionEnforcer.swift */,\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/Models;',
            '\t\t\t\tAABBCC11000100000000000E /* ExclusionEnforcer.swift */,' + children_lines + '\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/Models;',
            1
        )
    elif cat == "Utilities":
        content = content.replace(
            '\t\t\t\tAABBCC110001000000000016 /* HashUtility.swift */,\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/Utilities;',
            '\t\t\t\tAABBCC110001000000000016 /* HashUtility.swift */,' + children_lines + '\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/Utilities;',
            1
        )
    elif cat == "Components":
        content = content.replace(
            '\t\t\t\tAABBCC110001000000000028 /* UpdateDialogView.swift */,\n\t\t\t);\n\t\t\tpath = Components;',
            '\t\t\t\tAABBCC110001000000000028 /* UpdateDialogView.swift */,' + children_lines + '\n\t\t\t);\n\t\t\tpath = Components;',
            1
        )
    elif cat == "Views":
        content = content.replace(
            '\t\t\t\tAABBCC11000100000000002D /* OnboardingView.swift */,\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/Views;',
            '\t\t\t\tAABBCC11000100000000002D /* OnboardingView.swift */,' + children_lines + '\n\t\t\t);\n\t\t\tpath = Sources/SortyLib/Views;',
            1
        )

# 4. Create new groups (Settings, Preview, Onboarding as children of Views; DesignSystem and Managers at SortyLib level)

# Settings group
settings_children = files_per_group.get("Settings", [])
settings_children_str = "\n".join([f"\t\t\t\t{fid} /* {fname} */," for fid, fname in settings_children])
settings_group = f"""\t\t{SETTINGS_GROUP_ID} /* Settings */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{settings_children_str}
\t\t\t);
\t\t\tpath = Settings;
\t\t\tsourceTree = "<group>";
\t\t}};"""

# Preview group
preview_children = files_per_group.get("Preview", [])
preview_children_str = "\n".join([f"\t\t\t\t{fid} /* {fname} */," for fid, fname in preview_children])
preview_group = f"""\t\t{PREVIEW_GROUP_ID} /* Preview */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{preview_children_str}
\t\t\t);
\t\t\tpath = Preview;
\t\t\tsourceTree = "<group>";
\t\t}};"""

# Onboarding group
onboarding_children = files_per_group.get("Onboarding", [])
onboarding_children_str = "\n".join([f"\t\t\t\t{fid} /* {fname} */," for fid, fname in onboarding_children])
onboarding_group = f"""\t\t{ONBOARDING_GROUP_ID} /* Onboarding */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{onboarding_children_str}
\t\t\t);
\t\t\tpath = Onboarding;
\t\t\tsourceTree = "<group>";
\t\t}};"""

# DesignSystem group
designsystem_children = files_per_group.get("DesignSystem", [])
designsystem_children_str = "\n".join([f"\t\t\t\t{fid} /* {fname} */," for fid, fname in designsystem_children])
designsystem_group = f"""\t\t{DESIGNSYSTEM_GROUP_ID} /* DesignSystem */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{designsystem_children_str}
\t\t\t);
\t\t\tpath = Sources/SortyLib/DesignSystem;
\t\t\tsourceTree = "<group>";
\t\t}};"""

# Managers group
managers_children = files_per_group.get("Managers", [])
managers_children_str = "\n".join([f"\t\t\t\t{fid} /* {fname} */," for fid, fname in managers_children])
managers_group = f"""\t\t{MANAGERS_GROUP_ID} /* Managers */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{managers_children_str}
\t\t\t);
\t\t\tpath = Sources/SortyLib/Managers;
\t\t\tsourceTree = "<group>";
\t\t}};"""

# Insert new groups before /* End PBXGroup section */
new_groups = "\n".join([settings_group, preview_group, onboarding_group, designsystem_group, managers_group])
content = content.replace(
    '/* End PBXGroup section */',
    new_groups + '\n/* End PBXGroup section */',
    1
)

# 5. Add new groups as children of Views group (Settings, Preview, Onboarding)
# Add after Components child in Views group
content = content.replace(
    '\t\t\t\tAABBCC550000000000000001 /* Components */,',
    f'\t\t\t\tAABBCC550000000000000001 /* Components */,\n\t\t\t\t{SETTINGS_GROUP_ID} /* Settings */,\n\t\t\t\t{PREVIEW_GROUP_ID} /* Preview */,\n\t\t\t\t{ONBOARDING_GROUP_ID} /* Onboarding */,',
    1
)

# 6. Add DesignSystem and Managers groups to SortyLib root group (3353FC462F0124320097CD23)
# Add after Services group ref in the SortyLib group
content = content.replace(
    '\t\t\t\tAABBCC440000000000000001 /* Services */,',
    f'\t\t\t\tAABBCC440000000000000001 /* Services */,\n\t\t\t\t{DESIGNSYSTEM_GROUP_ID} /* DesignSystem */,\n\t\t\t\t{MANAGERS_GROUP_ID} /* Managers */,',
    1
)

# 7. Add all 58 build file refs to the Sources build phase
build_phase_entries = []
for idx, (fname, cat) in enumerate(files):
    bid = build_file_id(idx)
    build_phase_entries.append(f"\t\t\t\t{bid} /* {fname} in Sources */,")

build_phase_block = "\n".join(build_phase_entries)

content = content.replace(
    '\t\t\t\tAABBCC220002000000000031 /* AutomationManager.swift in Sources */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n\t\t33A1286B2F01230200A86470 /* Sources */',
    '\t\t\t\tAABBCC220002000000000031 /* AutomationManager.swift in Sources */,\n' + build_phase_block + '\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n\t\t33A1286B2F01230200A86470 /* Sources */',
    1
)

with open(PBXPROJ, 'w') as f:
    f.write(content)

print(f"Done! Added {len(files)} files to the project.")
print(f"File ref IDs: {file_ref_id(0)} to {file_ref_id(len(files)-1)}")
print(f"Build file IDs: {build_file_id(0)} to {build_file_id(len(files)-1)}")
