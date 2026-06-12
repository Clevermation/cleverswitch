# Security policy

CleverSwitch handles OAuth credentials, so security reports get priority.

**Please do not open public issues for vulnerabilities.** Use GitHub's private
vulnerability reporting instead: *Security → Report a vulnerability* on this
repository. You'll get a response within a few days.

In scope: anything that leaks tokens (logs, process arguments, files with weak
permissions), credential corruption, command injection through account handles
or server responses. The threat model and the protections already in place are
documented in `docs/SPEC.md` and the comments in `Sources/CleverSwitchKit/`.

Supported version: the latest release. Older versions are not patched.
