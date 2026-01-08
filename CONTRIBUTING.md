# Contributing to Sorty

Thank you for your interest in contributing to Sorty! This document provides guidelines and instructions for contributing to this project.

## Code of Conduct

By participating in this project, you are expected to uphold our Code of Conduct. Please report unacceptable behavior to [conduct@sorty.app](mailto:conduct@sorty.app).r organizational improvement.

## How to Contribute

### Reporting Bugs

Before submitting a bug report, please verify that the issue has not already been documented in the repository's issue tracker. When submitting a report, include:

1.  A descriptive title.
2.  Clear steps to reproduce the issue.
3.  The expected behavior and the actual observed behavior.
4.  Environment details, including macOS version and hardware architecture.

### Suggesting Enhancements

Proposed enhancements should be submitted as feature requests. Provide a detailed explanation of the proposed functionality and the rationale for its inclusion in the project.

### Developing and Submitting Changes

1.  Fork the repository and create a new branch from the `main` branch.
2.  Ensure that all code adheres to the project's existing style and structure.
3.  Include unit tests for any new functionality or bug fixes.
4.  Verify that all tests pass locally before submitting a pull request.
5.  Submit a pull request with a descriptive title and a comprehensive summary of the changes.

## Development Environment

### Prerequisites

*   macOS 15.1 or later.
*   Xcode 16.0 or later.
*   Swift 6.0 or later.

### Building the Project

The project can be built using Xcode or the provided `Makefile`.

To build via terminal:
```bash
make build
```

To run tests:
```bash
make test
```

## Pull Request Guidelines

*   Keep pull requests focused on a single change or a group of logically related changes.
*   Update documentation if the changes affect user-facing features or public APIs.
*   Maintain clear and concise commit messages.
*   Pull requests require a technical review and approval before merging.

## Style Guidelines

The project follows standard Swift API Design Guidelines. Maintain consistency with existing naming conventions and architectural patterns (MVVM/Service layer).
