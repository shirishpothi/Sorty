#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
source "${SCRIPT_DIR}/utils.sh"

print_header "Running Tests" 60

# Default settings
INCLUDE_UI=false
FEATURE_FILTER=""
CLEAN_BUILD=false
UI_TESTS_DISABLED=true

# Argument Parsing
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --ui)
        INCLUDE_UI=true
        shift
        ;;
        --feature)
        FEATURE_FILTER="$2"
        shift 2
        ;;
        --start-fresh)
        CLEAN_BUILD=true
        shift
        ;;
        *)
        # Assume it's a direct test filter pass-through if unknown, or error?
        # Let's keep it strict for now conforming to user request
        echo "Unknown option: $1"
        echo "Usage: $0 [--ui] [--feature <name>] [--start-fresh]"
        echo "Features: settings, exclusions, cli, duplicates, organize"
        exit 1
        ;;
    esac
done

if [ "$INCLUDE_UI" == "true" ] && [ "$UI_TESTS_DISABLED" == "true" ]; then
    log_item "UI tests are currently disabled and will be skipped."
    exit 0
fi

if [ "$CLEAN_BUILD" == "true" ]; then
    log_item "Cleaning build directory..."
    swift package clean
fi

# Construct Filter
TEST_FILTER=""

if [ -n "$FEATURE_FILTER" ]; then
    case $FEATURE_FILTER in
        settings)
            TEST_FILTER="Settings" 
            # Matches testSettingsWorkflow, testReasoning...
            ;;
        exclusions)
            TEST_FILTER="Exclusion"
            ;;
        cli)
            TEST_FILTER="CLI"
            ;;
        duplicates)
            TEST_FILTER="Duplicate"
            ;;
        organize)
            TEST_FILTER="Organize"
            ;;
        *)
            # Allow custom string
            TEST_FILTER="$FEATURE_FILTER"
            ;;
    esac
    log_item "Filtering tests for: $TEST_FILTER"
fi

# Run logic
start_step_timer "tests"

if [ "$INCLUDE_UI" == "true" ]; then
    log_item "Running UI Tests..."
    
    # xcodebuild filter syntax: -only-testing:Target/ClassName/MethodName
    # We need to map our simple filter to this if possible, or use standard filtering
    # xcodebuild is picky. If we have a filter, we might just grep the output or use specific schemes?
    # Actually, simpler: swift test doesn't do UI tests. xcodebuild does.
    
    # Disable code signing and entitlements for UI tests when no development cert is available.
    CMD="xcodebuild test -project Sorty.xcodeproj -scheme ${SCHEME} -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_ENTITLEMENTS=\"\" ENABLE_APP_SANDBOX=NO"
    
    if [ -n "$TEST_FILTER" ]; then
        # Heuristic mapping
        if [[ "$TEST_FILTER" == "Settings" ]]; then
             CMD="$CMD -only-testing:SortyUITests/AppUITests/testSettingsWorkflow"
        elif [[ "$TEST_FILTER" == "Exclusion" ]]; then
             CMD="$CMD -only-testing:SortyUITests/AppUITests/testExclusionRulesWorkflow"
        # Add more mappings as needed
        fi
    else
        CMD="$CMD -only-testing:SortyUITests"
    fi
     
    echo "Executing: $CMD"
    eval "$CMD"
else
    # Unit Tests Only (swift test)
    CMD="swift test"
    if [ -n "$TEST_FILTER" ]; then
        CMD="$CMD --filter $TEST_FILTER"
    fi
    
    echo "Executing: $CMD"
    eval "$CMD"
fi

log_success "Tests Completed"
