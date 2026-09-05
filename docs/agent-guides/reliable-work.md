# Reliable agent work

## Shared checkout

Stay on `main`. Before editing, record `git status --short --branch`, staged and unstaged diffs, untracked files, and `git rev-parse HEAD`. Preserve existing work. Agree on the current requested behavior before touching a surface another task recently changed. The latest explicit correction takes precedence over older plans and tests.

Run mutating shell commands through `python3 scripts/agent_run.py -- <command>`. For a sequence, wrap one `bash -c '...'` command around the entire edit, review, and commit operation. The advisory checkout lock fails immediately with exit 75 and the owner's PID and command when another cooperating command is active. Wait for that owner rather than removing the lock. Never nest wrappers. Tool-based edits must wait for active guarded commands to finish; this lock cannot prevent an editor or an uncooperative process from writing files.

Use `python3 scripts/agent_run.py --check -- <command>` for substantive validation. It records HEAD, source content, staged changes, elapsed time, and exit status under ignored `.agent-local/`. It prints a heartbeat every 30 seconds. Exit 76 means inputs changed and the result cannot support acceptance. The guard detects changes at command boundaries, not transient changes that are reverted before completion. Keep all writers idle for the full validation interval.

Stage explicit paths only. Compare the staged diff and HEAD again immediately before committing. If either changed, review the new state before proceeding. Never reset someone else's files, use `git add .`, remove `.git/index.lock`, or force push to resolve contention. A permission error writing Git metadata requires the same narrow command with the required sandbox permission; deleting locks does not fix permissions.

Put traces, fixtures, screenshots, and logs in a task-owned temporary directory. Remove only that task's artifacts. Keep useful evidence until it has been reported. Do not commit incidental `Resources/commit.txt` edits. Guarded checks set `SKIP_GIT_INJECT=true`; normal release metadata remains owned by the release build.

## Build selection and recovery

| Change | Build or check |
| --- | --- |
| Minor source or documentation edit | Review the diff; no local build required |
| App logic | `make test-focused FILTER=TestClass` and the relevant app build for substantial changes |
| SwiftUI runtime behavior | `make now`, then exercise the changed interaction |
| In-process view iteration | `make hot`; use `make now` again for final normal-app acceptance |
| Package, lifecycle, Finder, or widget structure | Normal build; verify Xcode target membership and affected extension target |
| Universal packaging or release | Existing Xcode/Blacksmith release workflow and signed bundle checks |

Do not nest `make test-focused` in the guard; it already acquires the lock. Guard other build commands explicitly, for example `python3 scripts/agent_run.py --check -- make dev`. Raw Swift and Xcode invocations bypass this coordination.

Reuse the normal cache for incremental work. For a `build.db` I/O failure, stop competing builds and retry the same focused check once with `SORTY_BUILD_DIR` set to a task-owned temporary directory. Isolated scratch storage fixes cache contention, not changing source files. Do not repeatedly clean all caches or start duplicate builds because dependency compilation is quiet. Inspect the reported child PID and build logs first. Hot reload already has a separate `SORTY_HOT_BUILD_DIR`; never point it at the normal build directory.

For a normal bundle, inspect its exact executable and libraries for InjectionLite dependencies or markers, its signature, and its actual launch. A fresh build directory alone does not prove that the launched app is the new bundle. Record the app path and commit used. Local tests do not replace required Blacksmith checks.

## Acceptance evidence

Choose the observable acceptance check before editing. Record the current requirement, relevant test or interaction, build identity, result, and any remaining gap in the task report.

| Requested behavior | Required evidence for a runtime claim |
| --- | --- |
| Appearance or animation | Changed screen and state transition, including Reduce Motion when affected |
| Accessibility or keyboard | VoiceOver announcement, focus order, and keyboard action on the actual control |
| Finder menus or windows | Bundle presence, `pluginkit` registration and enablement, then the Finder action and resulting window |
| Window routing or onboarding | Launch/reopen/deeplink path that triggered the issue; actual registered window and focus |
| Bookmarks or lifecycle | Delayed completion, cancellation, reset/removal, and stale-result rejection using controlled fixtures |
| Startup speed | Same configuration and persisted state; repeated launch-to-visible-frame and launch-to-usable-control measurements |
| Website | Successful deployment for the intended commit and the changed public route |

Computer use is appropriate when those interface checks are required for the task. Compile success and Git parity remain separate evidence. For destructive integration behavior such as uninstall or Trash handling, use a disposable installation and fixtures within the user's authorized scope. Do not reset real bookmarks, change signing identity, restart Finder, or delete user data merely to make a check pass.

For lifecycle tests, control asynchronous completion with barriers or continuations rather than sleeps. Assert the resulting state, persistence, and scope release after cancellation or reset. A test that only asserts no crash or mirrors the implementation is insufficient. If an unrelated assertion fails, record it separately and run the relevant filter; do not silently count a partial suite as green or remove the assertion.

## Profiling and external services

Before a long capture, run `xcrun xctrace list templates`, select an installed template, and do a short capture. Check `xcrun xctrace export --help` for this installation, then confirm the trace table of contents exports with `xcrun xctrace export --input <trace> --toc`. Confirm that the intended timing table exports too. A trace file's existence is not usable evidence. Stop repeating the same capture after template or feature export failures. Preserve the error and use a supported template or explicitly report the measurement gap.

Follow [Startup performance](startup-performance.md) for first-frame and usable-control measurement. Constructor logs and `onAppear` timings cannot substitute for either metric. Keep warm launches, cold launches, and window reopening separate.

After a website change committed with `[skip ci]`, dispatch `website.yml` for `main`, wait for the matching run, and verify the public changed route. Check that the deployed revision includes the intended commit. A green deployment does not establish that cached public content has refreshed.

For dependency remediation, report lockfile resolution, installed graph, CI, and Dependabot alert state separately. Registry failures and delayed security graph ingestion do not justify changing a correct lockfile or manually dismissing an alert. Retry external checks with bounded backoff and report a pending service state when it remains unresolved.
