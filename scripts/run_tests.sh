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
        echo "Features: settings, exclusions, health, cli, duplicates, organize"
        exit 1
        ;;
    esac
done

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
        health)
            TEST_FILTER="WorkspaceHealth"
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
    
    CMD="xcodebuild test -project ${PROJECT_NAME}.xcodeproj -scheme ${PROJECT_NAME} -destination 'platform=macOS'"
    
    if [ -n "$TEST_FILTER" ]; then
        # This is a bit rough, strict mapping is hard without knowing all test names.
        # But we can try -only-testing if we map strictly, or just rely on the user running all UI tests
        # The user wanted "selectively check just that"
        # If I filter unit tests, I might not filter UI tests easily unless I map them.
        
        # Let's try to pass it as -only-testing:FileOrganiserUITests/*Filter*
        # But xcodebuild doesn't verify wildcards well in -only-testing usually requires exact match?
        # Actually in recent XCode, you can do -only-testing:Target/TestClass
        
        # Heuristic mapping
        if [[ "$TEST_FILTER" == "Settings" ]]; then
             CMD="$CMD -only-testing:FileOrganiserUITests/AppUITests/testSettingsWorkflow"
        elif [[ "$TEST_FILTER" == "Exclusion" ]]; then
             CMD="$CMD -only-testing:FileOrganiserUITests/AppUITests/testExclusionRulesWorkflow"
        # Add more mappings as needed
        fi
    else
        CMD="$CMD -only-testing:FileOrganiserUITests"
    fi
     
    echo "Executing: $CMD"
    eval "$CMD" | xcbeautify || eval "$CMD"
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
