# Contributing to Sorty

Thank you for your interest in contributing to Sorty. This document provides comprehensive guidelines for development, testing, and submitting changes.

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to uphold these standards. Report violations via [GitHub Discussions](https://github.com/shirishpothi/Sorty/discussions).

## Development Environment

### Prerequisites

- macOS 15.1 or later
- Xcode 16.0 or later (including Swift 6.0)
- Git
- Optional: Ollama for local AI testing

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/shirishpothi/Sorty.git
cd Sorty

# Install dependencies
swift package resolve

# Build the project
make build

# Run tests
make test
```

### Useful Make Commands

| Command | Purpose |
|---------|---------|
| `make build` | Full build with tests |
| `make run` | Build and launch app |
| `make now` | Fast debug build + launch (recommended for dev) |
| `make dev` | Fastest build (debug, no tests, no launch) |
| `make test` | Run unit tests |
| `make test-fast` | Run fast unit tests only |
| `make quick` | Compile only, skip tests |
| `make cli` | Build the `learnings` CLI tool |
| `make install` | Install app to /Applications |
| `make harness` | Preview harness for rapid UI iteration |
| `make ci` | Run CI checks locally (security, build, test, app bundle) |
| `make ci-report` | Run CI locally + report pass/fail to GitHub |
| `make benchmark` | Measure build times |

For the full fast development loop guide, see [docs/agent-guides/fast-loop.md](docs/agent-guides/fast-loop.md).

## Architecture Overview

Sorty uses MVVM with Service Layers. Understanding the architecture helps you make consistent contributions.

### Key Architectural Patterns

**State Management:**
- `@MainActor` classes for thread safety
- `@EnvironmentObject` for dependency injection
- `ObservableObject` for reactive UI updates
- Managers handle business logic, ViewModels handle presentation

**AI Provider System:**
- All AI clients implement `AIClientProtocol`
- Factory pattern via `AIClientFactory`
- Protocol defines: `analyze(files:)`, `generateText(prompt:)`, `checkHealth()`

**Data Flow:**
```
View → ViewModel/Manager → FolderOrganizer → AIClient → OrganizationPlan → Preview → Apply
```

### Project Structure

```
Sources/
├── SortyApp/           # App entry point, AppCoordinator
├── SortyLib/
│   ├── AI/             # AI clients, prompts, parsers
│   ├── FileSystem/     # File operations, bookmarks
│   ├── Models/         # Data models, organization plans
│   ├── Services/       # Business logic, managers
│   ├── ViewModels/     # Presentation logic
│   ├── Views/          # SwiftUI views
│   └── Utilities/      # Helpers, security, deeplinks
└── LearningsCLI/       # CLI tool implementation
```

## Code Style Guidelines

### Swift Conventions

Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/):

- Use descriptive names that read well at call sites
- Prefer methods and properties over free functions
- Use `lowerCamelCase` for variables, `UpperCamelCase` for types
- Prefer strong type inference where clear

### Sorty-Specific Conventions

**Manager Classes:**
```swift
@MainActor
class SomeManager: ObservableObject {
    @Published var state: SomeState
    // Business logic here
}
```

**AI Client Implementation:**
```swift
public struct SomeAIClient: AIClientProtocol {
    public var streamingDelegate: StreamingDelegate?
    
    public func analyze(files: [FileItem], ...) async throws -> OrganizationPlan {
        // Implementation
    }
}
```

**UI Testing Support:**
```swift
// Always add accessibility identifiers
Button("Organize") {}
    .accessibilityIdentifier("OrganizeButton")
```

### Naming Conventions

- **Files**: `PascalCase.swift`
- **Tests**: `ComponentNameTests.swift`
- **Views**: Suffix with `View` (e.g., `SettingsView`)
- **Managers**: Suffix with `Manager` (e.g., `FileSystemManager`)
- **Protocols**: Describe capability (e.g., `AIClientProtocol`)

## Adding a New AI Provider

To add support for a new AI service:

1. **Create Client Implementation** (`Sources/SortyLib/AI/NewProviderClient.swift`):
```swift
import Foundation

public struct NewProviderClient: AIClientProtocol {
    private let apiKey: String
    private let baseURL: URL
    
    public var streamingDelegate: StreamingDelegate?
    
    public init(apiKey: String, baseURL: String) {
        self.apiKey = apiKey
        self.baseURL = URL(string: baseURL)!
    }
    
    public func analyze(files: [FileItem], 
                       persona: Persona,
                       options: OrganizationOptions) async throws -> OrganizationPlan {
        // 1. Build request using PromptBuilder
        // 2. Make network request
        // 3. Parse response with ResponseParser
        // 4. Return OrganizationPlan
    }
    
    public func checkHealth() async throws {
        // Verify API connectivity
    }
}
```

2. **Register in Factory** (`AIClientFactory.swift`):
```swift
case .newProvider:
    return NewProviderClient(apiKey: config.apiKey, baseURL: config.baseURL)
```

3. **Add Configuration** (`AIProvider.swift`):
```swift
public enum AIProvider: String, CaseIterable {
    case newProvider = "New Provider Name"
    
    public var defaultModel: String {
        switch self {
        case .newProvider: return "default-model-name"
        }
    }
}
```

4. **Add Tests** (`Tests/SortyTests/NewProviderClientTests.swift`):
```swift
func testAnalyze() async throws {
    let client = NewProviderClient(apiKey: "test", baseURL: "http://localhost")
    let files = [FileItem(name: "test.txt", path: "/tmp/test.txt")]
    let plan = try await client.analyze(files: files, ...)
    XCTAssertFalse(plan.operations.isEmpty)
}
```

5. **Update Documentation**: Add provider details to README.md and HelpView.swift

## Testing Requirements

### Unit Tests

All new functionality requires unit tests:

```swift
import XCTest
@testable import SortyLib

class FeatureNameTests: XCTestCase {
    func testFeature() {
        // Arrange
        let input = ...
        
        // Act
        let result = feature.process(input)
        
        // Assert
        XCTAssertEqual(result.expected, actual)
    }
}
```

### Testing Standards

- Use `MockAIClient` for testing AI-dependent features
- Create temporary directories in `setUp()`, clean in `tearDown()`
- Test edge cases (empty inputs, invalid paths, network failures)
- Use `XCTAssertThrowsError` for error conditions

### UI Tests

Add `accessibilityIdentifier` to all interactive elements:

```swift
.accessibilityIdentifier("SettingsSidebarItem")
.accessibilityIdentifier("PersonaPickerButton")
```

## Pull Request Process

### Before Submitting

1. **Run Local CI** (recommended — mirrors GitHub Actions):
```bash
make ci              # Run all CI checks locally
make ci-report       # Same, but also reports result to GitHub
```

   Or run tests individually:
```bash
make test
```

2. **Check Code Style**:
   - No warnings in Xcode
   - Consistent with existing code
   - Proper documentation comments for public APIs

3. **Update Documentation**:
   - README.md if user-facing changes
   - HelpView.swift if adding new features
   - AGENTS.md if changing build process

### PR Requirements

- Clear description of what changed and why
- Link to related issues (e.g., "Fixes #123")
- Screenshots for UI changes
- Test results showing what was verified

### Review Process

1. If you ran `make ci-report`, GitHub CI skips redundant checks for that commit
2. Otherwise, automated CI runs tests and security checks
3. Maintainers review for code quality and architecture alignment
3. Feedback is provided within 48 hours
4. Changes may be requested before approval

## Commit Message Guidelines

Use clear, descriptive commit messages:

```
feat: Add support for new AI provider X

- Implement NewProviderClient following AIClientProtocol
- Add configuration UI for API key and model selection
- Include unit tests for client implementation

Fixes #456
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `test`: Adding or fixing tests
- `refactor`: Code change that neither fixes nor adds features
- `perf`: Performance improvement
- `chore`: Build process or auxiliary tool changes

## Documentation

### Code Documentation

Document public APIs with documentation comments:

```swift
/// Analyzes files and generates an organization plan
/// - Parameters:
///   - files: Array of FileItems to analyze
///   - persona: The persona to use for organization logic
///   - options: Organization options (deep scan, temperature, etc.)
/// - Returns: OrganizationPlan containing proposed file operations
/// - Throws: AIClientError if the analysis fails
public func analyze(files: [FileItem], ...) async throws -> OrganizationPlan
```

### User-Facing Documentation

When adding features that affect users:

1. Update relevant HelpView.swift sections
2. Add to README.md if significant
3. Update CHANGELOG.md with user-facing description

## Questions and Support

- **General questions**: Open a GitHub Discussion
- **Bug reports**: Use the bug report template
- **Security issues**: Use [GitHub's private vulnerability reporting](https://github.com/shirishpothi/Sorty/security/advisories/new) (do not open public issues)
- **Code of Conduct violations**: Report via [GitHub Discussions](https://github.com/shirishpothi/Sorty/discussions)

## License

By contributing to Sorty, you agree that your contributions will be licensed under the GPL v3 license.

---

Thank you for helping make Sorty better.
