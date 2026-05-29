## Description
Briefly describe the changes made in this pull request. Explain the "why" behind the changes, not just the "what".

Example: "Added support for Groq AI provider to enable faster, cheaper local-like inference through their API. This addresses user requests for lower-cost alternatives to OpenAI."

## Related Issues
Link to any related issues or discussions:
- Fixes # (issue number)
- Related to # (issue number)
- Addresses discussion # (discussion number)

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Performance improvement
- [ ] Code refactoring
- [ ] Test addition or improvement
- [ ] Build/CI improvement

## Changes Made
List the specific changes:
- 
- 
- 

## Testing

### Automated Tests
- [ ] Blacksmith Swift CI passed for this branch/PR
- [ ] New tests added for new functionality
- [ ] UI coverage considered; UI tests are currently disabled, so manual UI evidence is attached when UI changed
- [ ] Local tests, if any, were diagnostic only and are listed below

### Manual Testing
Describe what you tested manually:
- [ ] Tested on macOS [version]
- [ ] Tested with AI provider [provider name]
- [ ] Tested edge cases: [list cases]
- [ ] Verified backwards compatibility

### Test Scenarios
If applicable, describe specific test scenarios:

**Scenario 1:** [Brief description]
- Steps: 
- Expected result:
- Actual result:

## Checklist

### Code Quality
- [ ] Code follows Swift API Design Guidelines
- [ ] No compiler warnings
- [ ] No force unwraps or unchecked optional bindings
- [ ] Proper error handling implemented
- [ ] Comments added for complex logic
- [ ] No hardcoded values (use constants/configuration)

### Architecture
- [ ] Changes align with existing architecture (MVVM + Service layers)
- [ ] @MainActor applied where needed
- [ ] Proper use of @EnvironmentObject for dependency injection
- [ ] No retain cycles or memory leaks
- [ ] Async/await used appropriately

### Documentation
- [ ] README.md updated if user-facing changes
- [ ] HelpView.swift updated for new features
- [ ] Code comments added for public APIs
- [ ] CHANGELOG.md updated
- [ ] AGENTS.md updated if build process changed

### UI/UX (if applicable)
- [ ] Accessibility identifiers added for UI tests
- [ ] Dark mode support verified
- [ ] Layout works on different screen sizes
- [ ] Keyboard navigation works
- [ ] Tooltips/help text added for new controls

### AI Provider Integration (if applicable)
- [ ] Implements AIClientProtocol correctly
- [ ] Registered in AIClientFactory
- [ ] Configuration UI added to Settings
- [ ] Error handling for API failures
- [ ] Tested with real API calls

## Screenshots/Videos
Add screenshots or screen recordings to demonstrate UI changes:

**Before:** [if applicable]

**After:**

## Breaking Changes
If this is a breaking change, describe:
- What breaks:
- Migration path for users:
- Deprecation timeline:

## Performance Impact
If this affects performance, include metrics:
- Before: [timing/memory]
- After: [timing/memory]
- Test scenario: [number of files, folder size]

## Additional Notes
Any other information reviewers should know:
- Known limitations
- Future work planned
- Dependencies on other PRs
- Security considerations

---

**By submitting this PR, I confirm that:**
- I have read the [Contributing Guidelines](CONTRIBUTING.md)
- I have read the [Code of Conduct](CODE_OF_CONDUCT.md)
- My changes are my own work or appropriately licensed
- I grant permission to license this contribution under the GPL v3 license
