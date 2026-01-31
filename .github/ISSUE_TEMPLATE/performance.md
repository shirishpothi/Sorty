---
name: Performance Report
about: Report a performance bottleneck or excessive resource usage
title: '[PERF] '
labels: performance
assignees: ''

---

## Performance Issue Description
Describe the performance problem in detail.

**Type of issue:**
- [ ] Slow AI analysis
- [ ] UI unresponsiveness
- [ ] High CPU usage
- [ ] High memory usage
- [ ] Slow file operations
- [ ] Other

## Environment Details
**System:**
- Hardware: [e.g., MacBook Air M1, MacBook Pro M3 Max]
- macOS Version: [e.g., 15.2]
- RAM: [e.g., 16GB, 32GB]

**Sorty Configuration:**
- Sorty Version: [e.g., 1.0.5]
- AI Provider: [e.g., OpenAI, Ollama local]
- Model: [e.g., gpt-5-mini, llama4]
- Deep Scan enabled: [Yes/No]
- Streaming mode: [Yes/No]

**Test Data:**
- Number of files: [e.g., 50, 500, 5000]
- File types: [e.g., images, documents, mixed]
- Total size: [e.g., 1GB, 50GB]
- Folder depth: [e.g., flat, 3 levels deep]

## Metrics
Provide specific performance data:

**Timing:**
- Operation duration: [e.g., 45 seconds]
- Expected duration: [e.g., 10 seconds]
- Previous performance: [if applicable]

**Resource Usage:**
- CPU usage during operation: [e.g., 80%, check Activity Monitor]
- Memory usage: [e.g., 2GB RAM]
- Disk activity: [e.g., heavy reading/writing]

**Comparisons:**
- Same operation with different AI provider: [timing]
- Same operation with fewer files: [timing]
- Same operation without Deep Scan: [timing]

## Steps to Reproduce
Detailed steps to observe the performance issue:

1. Prepare test folder with [X] files
2. Configure Sorty with [specific settings]
3. Perform [specific action]
4. Measure [specific metric]

## Optimization Ideas
If you have suggestions for improvement:

**Configuration changes:**
- Would different settings help?
- Which features could be disabled?

**Algorithm improvements:**
- Batch processing opportunities?
- Caching possibilities?

**UI improvements:**
- Progress indicators needed?
- Cancellation options?

## Additional Context
- Does performance degrade over time?
- Is this a regression (worked better before)?
- Specific file types causing issues?
- External factors (network, disk speed)?

## Diagnostic Data
Attach if available:
- [ ] Activity Monitor screenshot during operation
- [ ] Console.app logs filtered for Sorty
- [ ] Sample project/folder structure
