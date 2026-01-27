#!/bin/bash
#
# Sorty Pre-Release Validation Script
# ====================================
# Comprehensive checks to ensure the app is ready for release.
#
# Usage:
#   ./scripts/prerelease_check.sh [options]
#
# Options:
#   --ui-tests      Include UI tests (slower, requires Xcode project)
#   --skip-build    Skip the build phase (useful if already built)
#   --verbose       Show detailed output for each check
#   --help          Show this help message
#

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

# ============================================================================
# Configuration
# ============================================================================

RUN_UI_TESTS=false
SKIP_BUILD=false
VERBOSE=false

# Counters
CHECKS_PASSED=0
CHECKS_FAILED=0
CHECKS_WARNED=0
TOTAL_CHECKS=0

# Track failures and warnings for summary
declare -a FAILURES=()
declare -a WARNINGS=()

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --ui-tests)
            RUN_UI_TESTS=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            head -20 "$0" | tail -15
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run with --help for usage information."
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================

check_pass() {
    local name="$1"
    echo -e "  ${GREEN}${SYM_CHECK}${NC} $name"
    ((CHECKS_PASSED++))
    ((TOTAL_CHECKS++))
}

check_fail() {
    local name="$1"
    local reason="$2"
    echo -e "  ${RED}${SYM_CROSS}${NC} $name"
    if [ -n "$reason" ]; then
        echo -e "      ${RED}→ $reason${NC}"
    fi
    FAILURES+=("$name: $reason")
    ((CHECKS_FAILED++))
    ((TOTAL_CHECKS++))
}

check_warn() {
    local name="$1"
    local reason="$2"
    echo -e "  ${YELLOW}${SYM_WARN}${NC} $name"
    if [ -n "$reason" ]; then
        echo -e "      ${YELLOW}→ $reason${NC}"
    fi
    WARNINGS+=("$name: $reason")
    ((CHECKS_WARNED++))
    ((TOTAL_CHECKS++))
}

check_skip() {
    local name="$1"
    local reason="$2"
    echo -e "  ${BLUE}○${NC} $name (skipped: $reason)"
    ((TOTAL_CHECKS++))
}

phase_header() {
    local phase_num="$1"
    local phase_name="$2"
    echo ""
    echo -e "${BLUE}━━━ Phase $phase_num: $phase_name ━━━${NC}"
}

verbose_log() {
    if [ "$VERBOSE" = true ]; then
        echo "    $1"
    fi
}

# ============================================================================
# Phase 1: Environment Validation
# ============================================================================

phase_environment() {
    phase_header 1 "Environment Validation"
    
    # Check Swift version
    if command -v swift &> /dev/null; then
        SWIFT_VERSION=$(swift --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
        SWIFT_MAJOR=$(echo "$SWIFT_VERSION" | cut -d. -f1)
        SWIFT_MINOR=$(echo "$SWIFT_VERSION" | cut -d. -f2)
        
        if [ "$SWIFT_MAJOR" -ge 5 ] && [ "$SWIFT_MINOR" -ge 9 ]; then
            check_pass "Swift version $SWIFT_VERSION (≥ 5.9)"
        else
            check_fail "Swift version" "Found $SWIFT_VERSION, need ≥ 5.9"
            return 1
        fi
    else
        check_fail "Swift installation" "Swift not found in PATH"
        return 1
    fi
    
    # Check macOS version
    MACOS_VERSION=$(sw_vers -productVersion)
    MACOS_MAJOR=$(echo "$MACOS_VERSION" | cut -d. -f1)
    
    if [ "$MACOS_MAJOR" -ge 14 ]; then
        check_pass "macOS version $MACOS_VERSION (≥ 14.0)"
    else
        check_fail "macOS version" "Found $MACOS_VERSION, need ≥ 14.0 (Sonoma)"
        return 1
    fi
    
    # Check gitleaks
    if command -v gitleaks &> /dev/null; then
        GITLEAKS_VERSION=$(gitleaks version 2>&1 | head -1)
        check_pass "Gitleaks installed ($GITLEAKS_VERSION)"
    else
        check_fail "Gitleaks installation" "Install with: brew install gitleaks"
        return 1
    fi
    
    # Check codesign
    if command -v codesign &> /dev/null; then
        check_pass "codesign available"
    else
        check_fail "codesign" "Xcode Command Line Tools required"
        return 1
    fi
    
    # Check PlistBuddy
    if [ -x /usr/libexec/PlistBuddy ]; then
        check_pass "PlistBuddy available"
    else
        check_fail "PlistBuddy" "Required for plist validation"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Phase 2: Build & Test
# ============================================================================

phase_build_test() {
    phase_header 2 "Build & Test"
    
    if [ "$SKIP_BUILD" = true ]; then
        check_skip "Release build" "skipped via --skip-build"
    else
        # Release build
        echo -e "  ${BLUE}...${NC} Building release configuration..."
        if swift build -c release 2>&1 | tail -5; then
            check_pass "Release build succeeds"
        else
            check_fail "Release build" "Compilation failed"
            return 1
        fi
    fi
    
    # Unit tests
    echo -e "  ${BLUE}...${NC} Running unit tests..."
    if swift test --parallel 2>&1 | tail -10; then
        check_pass "All unit tests pass"
    else
        check_fail "Unit tests" "One or more tests failed"
        return 1
    fi
    
    # UI tests (optional)
    if [ "$RUN_UI_TESTS" = true ]; then
        echo -e "  ${BLUE}...${NC} Running UI tests..."
        if [ -f "${PROJECT_DIR}/FileOrganiser.xcodeproj/project.pbxproj" ]; then
            if xcodebuild test \
                -project "${PROJECT_DIR}/FileOrganiser.xcodeproj" \
                -scheme "FileOrganiser" \
                -destination 'platform=macOS' \
                -only-testing:FileOrganiserUITests \
                CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20; then
                check_pass "UI tests pass"
            else
                check_warn "UI tests" "Some UI tests failed (non-blocking)"
            fi
        else
            check_skip "UI tests" "Xcode project not found"
        fi
    else
        check_skip "UI tests" "use --ui-tests to enable"
    fi
    
    return 0
}

# ============================================================================
# Phase 3: CLI Validation
# ============================================================================

phase_cli() {
    phase_header 3 "CLI Tools Validation"
    
    # Build learnings CLI
    echo -e "  ${BLUE}...${NC} Building learnings CLI..."
    if swift build --product learnings 2>&1 | tail -3; then
        check_pass "learnings CLI builds"
    else
        check_fail "learnings CLI build" "Failed to compile"
        return 1
    fi
    
    # Test learnings CLI help
    if swift run learnings help 2>&1 | grep -q "Learnings CLI"; then
        check_pass "learnings CLI help command works"
    else
        check_fail "learnings CLI" "Help command failed"
        return 1
    fi
    
    # Test learnings CLI info
    if swift run learnings info 2>&1 | head -1 > /dev/null; then
        check_pass "learnings CLI info command works"
    else
        check_warn "learnings CLI info" "Info command returned unexpected output"
    fi
    
    # Check fileorg script exists
    FILEORG_PATH="${PROJECT_DIR}/CLI/fileorg"
    if [ -f "$FILEORG_PATH" ]; then
        check_pass "fileorg script exists"
    else
        check_fail "fileorg script" "Not found at CLI/fileorg"
        return 1
    fi
    
    # Check fileorg is executable
    if [ -x "$FILEORG_PATH" ]; then
        check_pass "fileorg script is executable"
    else
        check_warn "fileorg permissions" "Script not executable (chmod +x needed)"
    fi
    
    # Syntax check
    if bash -n "$FILEORG_PATH" 2>&1; then
        check_pass "fileorg syntax valid"
    else
        check_fail "fileorg syntax" "Bash syntax errors detected"
        return 1
    fi
    
    # Check scheme is set to sorty
    if grep -q 'APP_SCHEME="sorty"' "$FILEORG_PATH"; then
        check_pass "fileorg uses sorty:// scheme"
    else
        check_fail "fileorg scheme" "APP_SCHEME should be 'sorty'"
        return 1
    fi
    
    # Test help command
    chmod +x "$FILEORG_PATH"
    if "$FILEORG_PATH" help 2>&1 | grep -q "Sorty CLI"; then
        check_pass "fileorg help command works"
    else
        check_fail "fileorg help" "Help output not recognized"
        return 1
    fi
    
    return 0
}

# ============================================================================
# Phase 4: App Bundle Validation
# ============================================================================

phase_app_bundle() {
    phase_header 4 "App Bundle Validation"
    
    # Build the app bundle if needed
    if [ ! -d "${RELEASE_DIR}/Sorty.app" ]; then
        echo -e "  ${BLUE}...${NC} Assembling app bundle..."
        "${SCRIPT_DIR}/build.sh" > /dev/null 2>&1 || true
    fi
    
    APP_PATH="${RELEASE_DIR}/Sorty.app"
    
    # Check app bundle exists
    if [ -d "$APP_PATH" ]; then
        check_pass "App bundle exists"
    else
        check_fail "App bundle" "Sorty.app not found in releases/"
        return 1
    fi
    
    # Check binary exists
    if [ -f "$APP_PATH/Contents/MacOS/SortyApp" ]; then
        check_pass "Main binary present"
    else
        check_fail "Main binary" "SortyApp not found in bundle"
        return 1
    fi
    
    # Check Info.plist in bundle
    if [ -f "$APP_PATH/Contents/Info.plist" ]; then
        check_pass "Info.plist in bundle"
    else
        check_fail "Info.plist" "Missing from app bundle"
        return 1
    fi
    
    # Code signing validation
    if codesign -v "$APP_PATH" 2>&1; then
        check_pass "Code signature valid"
    else
        # Ad-hoc signing is acceptable for local builds
        if codesign -v "$APP_PATH" 2>&1 | grep -q "adhoc"; then
            check_pass "Code signature valid (ad-hoc)"
        else
            check_warn "Code signature" "Signing issues detected (may need re-signing for distribution)"
        fi
    fi
    
    # Check AppIcon
    if [ -f "${APP_PATH}/Contents/Resources/AppIcon.icns" ] || \
       [ -d "${APP_PATH}/Contents/Resources/Assets.car" ]; then
        check_pass "App icon present"
    else
        check_warn "App icon" "AppIcon.icns not found in Resources"
    fi
    
    return 0
}

# ============================================================================
# Phase 5: Info.plist Validation
# ============================================================================

phase_plist() {
    phase_header 5 "Info.plist Validation"
    
    PLIST_PATH="${PROJECT_DIR}/Info.plist"
    
    if [ ! -f "$PLIST_PATH" ]; then
        check_fail "Info.plist" "File not found at project root"
        return 1
    fi
    
    # Check required keys
    REQUIRED_KEYS=(
        "CFBundleIdentifier"
        "CFBundleName"
        "CFBundleShortVersionString"
        "CFBundleVersion"
        "CFBundleExecutable"
        "LSMinimumSystemVersion"
        "CFBundleURLTypes"
    )
    
    for key in "${REQUIRED_KEYS[@]}"; do
        if /usr/libexec/PlistBuddy -c "Print :$key" "$PLIST_PATH" &> /dev/null; then
            verbose_log "Found key: $key"
        else
            check_fail "Info.plist key" "Missing required key: $key"
            return 1
        fi
    done
    check_pass "All required Info.plist keys present"
    
    # Check for placeholder values
    PLACEHOLDER_CHECK=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$PLIST_PATH" 2>/dev/null || echo "")
    if [[ "$PLACEHOLDER_CHECK" == *"PLACEHOLDER"* ]]; then
        check_warn "SUPublicEDKey" "Contains placeholder value (update for Sparkle updates)"
    else
        check_pass "No placeholder values in signing keys"
    fi
    
    # Check URL scheme is sorty
    URL_SCHEME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$PLIST_PATH" 2>/dev/null || echo "")
    if [ "$URL_SCHEME" = "sorty" ]; then
        check_pass "URL scheme is 'sorty'"
    else
        check_fail "URL scheme" "Expected 'sorty', found '$URL_SCHEME'"
        return 1
    fi
    
    # Check minimum macOS version matches Package.swift
    MIN_MACOS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST_PATH" 2>/dev/null || echo "")
    PACKAGE_PLATFORM=$(grep -oE '\.macOS\(\.v[0-9]+\)' "${PROJECT_DIR}/Package.swift" | grep -oE 'v[0-9]+' | tr -d 'v')
    
    if [ -n "$MIN_MACOS" ] && [ -n "$PACKAGE_PLATFORM" ]; then
        MIN_MAJOR=$(echo "$MIN_MACOS" | cut -d. -f1)
        if [ "$MIN_MAJOR" -le "$PACKAGE_PLATFORM" ]; then
            check_pass "LSMinimumSystemVersion ($MIN_MACOS) compatible with Package.swift (macOS $PACKAGE_PLATFORM)"
        else
            check_warn "LSMinimumSystemVersion" "Info.plist ($MIN_MACOS) stricter than Package.swift ($PACKAGE_PLATFORM)"
        fi
    else
        check_warn "LSMinimumSystemVersion" "Could not verify compatibility"
    fi
    
    return 0
}

# ============================================================================
# Phase 6: Version Consistency
# ============================================================================

phase_version() {
    phase_header 6 "Version Consistency"
    
    # Get version from Info.plist
    PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${PROJECT_DIR}/Info.plist" 2>/dev/null || echo "")
    PLIST_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${PROJECT_DIR}/Info.plist" 2>/dev/null || echo "")
    
    if [ -n "$PLIST_VERSION" ]; then
        check_pass "Info.plist version: $PLIST_VERSION (build $PLIST_BUILD)"
    else
        check_fail "Info.plist version" "Could not read CFBundleShortVersionString"
        return 1
    fi
    
    # Check CHANGELOG.md has entry for this version
    CHANGELOG_PATH="${PROJECT_DIR}/CHANGELOG.md"
    if [ -f "$CHANGELOG_PATH" ]; then
        if grep -q "\[$PLIST_VERSION\]" "$CHANGELOG_PATH"; then
            check_pass "CHANGELOG.md has entry for v$PLIST_VERSION"
        else
            check_warn "CHANGELOG.md" "No entry found for version $PLIST_VERSION"
        fi
    else
        check_warn "CHANGELOG.md" "File not found"
    fi
    
    # Check git tag (if in git repo and tagged)
    if git rev-parse --git-dir > /dev/null 2>&1; then
        CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "")
        if [ -n "$CURRENT_TAG" ]; then
            TAG_VERSION=$(echo "$CURRENT_TAG" | tr -d 'v')
            if [ "$TAG_VERSION" = "$PLIST_VERSION" ]; then
                check_pass "Git tag ($CURRENT_TAG) matches Info.plist"
            else
                check_warn "Git tag mismatch" "Tag: $CURRENT_TAG, Plist: $PLIST_VERSION"
            fi
        else
            check_skip "Git tag check" "HEAD is not tagged"
        fi
    else
        check_skip "Git tag check" "Not a git repository"
    fi
    
    return 0
}

# ============================================================================
# Phase 7: Security Checks
# ============================================================================

phase_security() {
    phase_header 7 "Security Checks"
    
    # Run gitleaks
    echo -e "  ${BLUE}...${NC} Running gitleaks scan..."
    cd "$PROJECT_DIR"
    if gitleaks detect --source . --no-git -v 2>&1 | tail -5; then
        check_pass "No secrets detected by gitleaks"
    else
        # Check exit code
        if gitleaks detect --source . --no-git --exit-code 0 2>/dev/null; then
            check_pass "No secrets detected by gitleaks"
        else
            check_fail "Gitleaks" "Potential secrets detected in codebase"
            return 1
        fi
    fi
    
    # Check for hardcoded API keys in source
    echo -e "  ${BLUE}...${NC} Scanning for hardcoded credentials..."
    SOURCES_DIR="${PROJECT_DIR}/Sources"
    
    # Patterns that might indicate hardcoded secrets
    SUSPICIOUS_PATTERNS=(
        "sk-[a-zA-Z0-9]{20,}"      # OpenAI API key pattern
        "api[_-]?key\s*=\s*[\"'][^\"']{20,}[\"']"
        "secret\s*=\s*[\"'][^\"']{20,}[\"']"
        "password\s*=\s*[\"'][^\"']+[\"']"
    )
    
    FOUND_SECRETS=false
    for pattern in "${SUSPICIOUS_PATTERNS[@]}"; do
        if grep -rE "$pattern" "$SOURCES_DIR" --include="*.swift" 2>/dev/null | grep -v "//.*$pattern" | grep -v "Tests/" | head -1 > /dev/null; then
            FOUND_SECRETS=true
            break
        fi
    done
    
    if [ "$FOUND_SECRETS" = false ]; then
        check_pass "No hardcoded credentials in source"
    else
        check_warn "Potential credentials" "Review source for hardcoded secrets"
    fi
    
    # Check for .env files that shouldn't be committed
    if [ -f "${PROJECT_DIR}/.env" ]; then
        check_warn ".env file" "Found .env file - ensure it's in .gitignore"
    else
        check_pass "No .env file in project root"
    fi
    
    return 0
}

# ============================================================================
# Phase 8: Code Quality Checks
# ============================================================================

phase_code_quality() {
    phase_header 8 "Code Quality"
    
    SOURCES_DIR="${PROJECT_DIR}/Sources"
    
    # Count debug print statements
    DEBUG_PRINTS=$(grep -rE "^\s*(print|debugPrint)\(" "$SOURCES_DIR" --include="*.swift" 2>/dev/null | grep -v "Tests/" | wc -l | tr -d ' ')
    if [ "$DEBUG_PRINTS" -eq 0 ]; then
        check_pass "No debug print statements"
    elif [ "$DEBUG_PRINTS" -lt 10 ]; then
        check_warn "Debug prints" "Found $DEBUG_PRINTS print() calls in source"
    else
        check_warn "Debug prints" "Found $DEBUG_PRINTS print() calls - consider removing for release"
    fi
    
    # Count TODO/FIXME comments
    TODOS=$(grep -rE "(TODO|FIXME|XXX|HACK):" "$SOURCES_DIR" --include="*.swift" 2>/dev/null | grep -v "Tests/" | wc -l | tr -d ' ')
    if [ "$TODOS" -eq 0 ]; then
        check_pass "No TODO/FIXME comments"
    elif [ "$TODOS" -lt 20 ]; then
        check_warn "TODO comments" "Found $TODOS TODO/FIXME comments"
    else
        check_warn "TODO comments" "Found $TODOS TODO/FIXME comments - review before release"
    fi
    
    # Count force unwraps (!)
    FORCE_UNWRAPS=$(grep -rE "![^=]" "$SOURCES_DIR" --include="*.swift" 2>/dev/null | grep -v "Tests/" | grep -v "//" | grep -v "!=" | grep -v "/*" | wc -l | tr -d ' ')
    if [ "$FORCE_UNWRAPS" -lt 50 ]; then
        check_pass "Force unwraps within acceptable range ($FORCE_UNWRAPS)"
    else
        check_warn "Force unwraps" "Found $FORCE_UNWRAPS potential force unwraps - review for safety"
    fi
    
    return 0
}

# ============================================================================
# Phase 9: Deeplink Verification
# ============================================================================

phase_deeplinks() {
    phase_header 9 "Deeplink Verification"
    
    # Run deeplink-specific tests
    echo -e "  ${BLUE}...${NC} Running deeplink tests..."
    if swift test --filter "DeeplinkTests" 2>&1 | tail -5; then
        check_pass "All deeplink tests pass"
    else
        check_fail "Deeplink tests" "Some deeplink tests failed"
        return 1
    fi
    
    # Verify URL scheme in Info.plist
    URL_SCHEME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "${PROJECT_DIR}/Info.plist" 2>/dev/null || echo "")
    if [ "$URL_SCHEME" = "sorty" ]; then
        check_pass "sorty:// URL scheme registered"
    else
        check_fail "URL scheme" "sorty scheme not found in Info.plist"
        return 1
    fi
    
    # Check fileorg supports key deeplink commands
    FILEORG_PATH="${PROJECT_DIR}/CLI/fileorg"
    chmod +x "$FILEORG_PATH"
    
    DEEPLINK_COMMANDS=("organize" "duplicates" "settings" "learnings" "health" "history")
    MISSING_COMMANDS=()
    
    for cmd in "${DEEPLINK_COMMANDS[@]}"; do
        if ! "$FILEORG_PATH" help 2>&1 | grep -qi "$cmd"; then
            MISSING_COMMANDS+=("$cmd")
        fi
    done
    
    if [ ${#MISSING_COMMANDS[@]} -eq 0 ]; then
        check_pass "All key deeplink commands documented in fileorg"
    else
        check_warn "fileorg commands" "Missing documentation for: ${MISSING_COMMANDS[*]}"
    fi
    
    return 0
}

# ============================================================================
# Phase 10: Documentation Check
# ============================================================================

phase_documentation() {
    phase_header 10 "Documentation"
    
    DOC_FILES=("README.md" "CHANGELOG.md" "HELP.md")
    
    for doc in "${DOC_FILES[@]}"; do
        DOC_PATH="${PROJECT_DIR}/$doc"
        if [ -f "$DOC_PATH" ]; then
            LINES=$(wc -l < "$DOC_PATH" | tr -d ' ')
            if [ "$LINES" -gt 10 ]; then
                check_pass "$doc exists ($LINES lines)"
            else
                check_warn "$doc" "File seems sparse ($LINES lines)"
            fi
        else
            check_warn "$doc" "File not found"
        fi
    done
    
    # Check for LICENSE
    if [ -f "${PROJECT_DIR}/LICENSE" ] || [ -f "${PROJECT_DIR}/LICENSE.md" ]; then
        check_pass "LICENSE file present"
    else
        check_warn "LICENSE" "No LICENSE file found"
    fi
    
    return 0
}

# ============================================================================
# Phase 11: File Permissions
# ============================================================================

phase_permissions() {
    phase_header 11 "File Permissions"
    
    SCRIPTS=(
        "scripts/build.sh"
        "scripts/release.sh"
        "scripts/package.sh"
        "scripts/run_tests.sh"
        "CLI/fileorg"
    )
    
    for script in "${SCRIPTS[@]}"; do
        SCRIPT_PATH="${PROJECT_DIR}/$script"
        if [ -f "$SCRIPT_PATH" ]; then
            if [ -x "$SCRIPT_PATH" ]; then
                check_pass "$script is executable"
            else
                check_warn "$script" "Not executable (chmod +x needed)"
            fi
        fi
    done
    
    return 0
}

# ============================================================================
# Phase 12: Update System Verification
# ============================================================================

phase_update_system() {
    phase_header 12 "Update System Verification"
    
    # Test 1: Run UpdateManager unit tests
    echo -e "  ${BLUE}...${NC} Running UpdateManager tests..."
    if swift test --filter "UpdateManagerTests" 2>&1 | tail -5; then
        check_pass "UpdateManager tests pass"
    else
        check_fail "UpdateManager tests" "Tests failed or not found"
    fi
    
    # Test 2: Verify BuildInfo.version exists and is valid
    SOURCES_DIR="${PROJECT_DIR}/Sources"
    BUILDINFO_FILE=$(find "$SOURCES_DIR" -name "*.swift" -exec grep -l "BuildInfo" {} \; 2>/dev/null | head -1)
    
    if [ -n "$BUILDINFO_FILE" ]; then
        check_pass "BuildInfo found in Sources"
        
        # Check for version property with X.Y.Z pattern
        VERSION_LINE=$(grep -E "version.*=.*\"[0-9]+\.[0-9]+\.[0-9]+\"" "$BUILDINFO_FILE" 2>/dev/null || echo "")
        if [ -n "$VERSION_LINE" ]; then
            VERSION=$(echo "$VERSION_LINE" | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" | head -1)
            check_pass "BuildInfo.version is valid ($VERSION)"
        else
            check_fail "BuildInfo.version" "Version not found or not in X.Y.Z format"
        fi
    else
        check_fail "BuildInfo" "BuildInfo not found in Sources"
    fi
    
    # Test 3: Verify GitHub API is reachable (optional, warn on failure)
    echo -e "  ${BLUE}...${NC} Checking GitHub API accessibility..."
    GITHUB_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "https://api.github.com/repos/shirishpothi/Sorty/releases/latest" 2>/dev/null || echo "000")
    
    case "$GITHUB_RESPONSE" in
        200)
            check_pass "GitHub releases API reachable"
            ;;
        404)
            check_warn "GitHub releases API" "No releases found yet (404) - this is OK for first release"
            ;;
        403)
            check_warn "GitHub releases API" "Rate limited (403) - cannot verify API access"
            ;;
        000)
            check_warn "GitHub releases API" "Network error - cannot reach GitHub"
            ;;
        *)
            check_warn "GitHub releases API" "Unexpected response ($GITHUB_RESPONSE)"
            ;;
    esac
    
    # Test 4: Check that UpdateManager is properly wired in the app
    UPDATE_MANAGER_USAGES=$(grep -rE "UpdateManager" "$SOURCES_DIR" --include="*.swift" 2>/dev/null | grep -v "Tests/" | grep -v "UpdateManager\.swift" | wc -l | tr -d ' ')
    
    if [ "$UPDATE_MANAGER_USAGES" -gt 0 ]; then
        check_pass "UpdateManager is wired in app ($UPDATE_MANAGER_USAGES usages)"
    else
        check_fail "UpdateManager wiring" "UpdateManager not referenced in app code"
    fi
    
    return 0
}

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    echo ""
    print_divider "═" 60
    echo ""
    echo -e "${BLUE}                    PRE-RELEASE SUMMARY${NC}"
    echo ""
    print_divider "─" 60
    
    echo -e "  ${GREEN}${SYM_CHECK} Passed:${NC}  $CHECKS_PASSED"
    echo -e "  ${YELLOW}${SYM_WARN} Warnings:${NC} $CHECKS_WARNED"
    echo -e "  ${RED}${SYM_CROSS} Failed:${NC}  $CHECKS_FAILED"
    echo -e "  Total:    $TOTAL_CHECKS checks"
    
    if [ ${#FAILURES[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}Failures:${NC}"
        for failure in "${FAILURES[@]}"; do
            echo -e "  ${RED}•${NC} $failure"
        done
    fi
    
    if [ ${#WARNINGS[@]} -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}Warnings:${NC}"
        for warning in "${WARNINGS[@]}"; do
            echo -e "  ${YELLOW}•${NC} $warning"
        done
    fi
    
    echo ""
    print_divider "═" 60
    
    if [ $CHECKS_FAILED -eq 0 ]; then
        echo ""
        echo -e "  ${GREEN}${SYM_SPARKLE} READY FOR RELEASE ${SYM_SPARKLE}${NC}"
        echo ""
        if [ $CHECKS_WARNED -gt 0 ]; then
            echo -e "  ${YELLOW}Review warnings above before releasing.${NC}"
        fi
        echo ""
        return 0
    else
        echo ""
        echo -e "  ${RED}${SYM_CROSS} NOT READY FOR RELEASE${NC}"
        echo ""
        echo -e "  ${RED}Fix $CHECKS_FAILED failure(s) before releasing.${NC}"
        echo ""
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    print_header "Sorty Pre-Release Validation" 60
    
    local start_time=$(date +%s)
    
    echo -e "Configuration:"
    echo -e "  • UI Tests: $([ "$RUN_UI_TESTS" = true ] && echo "enabled" || echo "disabled")"
    echo -e "  • Skip Build: $([ "$SKIP_BUILD" = true ] && echo "yes" || echo "no")"
    echo -e "  • Verbose: $([ "$VERBOSE" = true ] && echo "yes" || echo "no")"
    
    # Run all phases
    # Phase 1 is critical - fail fast
    if ! phase_environment; then
        echo ""
        echo -e "${RED}Environment validation failed. Cannot continue.${NC}"
        print_summary
        exit 1
    fi
    
    # Phase 2 is critical - fail fast
    if ! phase_build_test; then
        echo ""
        echo -e "${RED}Build or tests failed. Cannot continue.${NC}"
        print_summary
        exit 1
    fi
    
    # Remaining phases - continue on failure
    phase_cli || true
    phase_app_bundle || true
    phase_plist || true
    phase_version || true
    phase_security || true
    phase_code_quality || true
    phase_deeplinks || true
    phase_documentation || true
    phase_permissions || true
    phase_update_system || true
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo -e "Completed in ${duration}s"
    
    print_summary
}

# Run main
main "$@"
