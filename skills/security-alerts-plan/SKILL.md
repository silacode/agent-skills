---
name: security-alerts-plan
description: Fetch all of the repository's open GitHub security alerts (Dependabot, code scanning, secret scanning, and repository security advisories), trace each to its root cause, and write one fix plan. Use when asked to check GitHub security alerts, Dependabot, CodeQL or code scanning, secret scanning, or security advisories, or to plan fixes for flagged vulnerabilities or leaked secrets. Read-only; it never edits code, changes dependencies, or changes alert state on GitHub.
metadata:
  version: "1.1.0"
  argument-hint: <optional expected counts, e.g. "dependabot 38, code scanning 0, secrets 2">
---

# Security Alerts Plan

**Scope: read alerts, investigate, write one plan file. Nothing else.** Do not edit code, run
any install/update/audit-fix command that changes a manifest or lockfile, or dismiss/close
alerts. Fixing is a separate request that follows the plan.

**Never print a secret value** in chat, logs, or the plan. Secret scanning API responses
contain the raw secret in `.secret`; always select fields explicitly with `--jq`, as below.

**The plan describes unfixed vulnerabilities.** If the repo is public, tell the user not to
commit or push the plan until the fixes ship.

## 0. Read repo policy

Read the repo's agent and contributor instructions (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`,
including scoped ones near the affected manifests) and its CI workflows. Note:

- where plans go (default: `plans/`)
- verification gates: lint, typecheck, test, build commands, and what CI does not run
- dependency policy: minimum release age, pinning, override rules, version files
- push and history policy

These decide the plan's steps and verification. Repo policy wins over this skill's defaults.

## 1. Fetch alerts

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

gh api --paginate "repos/$REPO/dependabot/alerts?state=open&per_page=100" --jq '.[] | {
  number, url: .html_url, severity: .security_advisory.severity,
  ghsa: .security_advisory.ghsa_id, summary: .security_advisory.summary,
  ecosystem: .dependency.package.ecosystem, package: .dependency.package.name,
  manifest: .dependency.manifest_path, relationship: .dependency.relationship,
  scope: .dependency.scope, vulnerable: .security_vulnerability.vulnerable_version_range,
  patched: .security_vulnerability.first_patched_version.identifier }'

gh api --paginate "repos/$REPO/code-scanning/alerts?state=open&per_page=100" --jq '.[] | {
  number, url: .html_url, tool: .tool.name, rule: .rule.id,
  severity: (.rule.security_severity_level // .rule.severity), description: .rule.description,
  path: .most_recent_instance.location.path, line: .most_recent_instance.location.start_line,
  message: .most_recent_instance.message.text }'

gh api "repos/$REPO/code-scanning/alerts/<number>" --jq '{rule: .rule.id, help: .rule.help}'

gh api --paginate "repos/$REPO/secret-scanning/alerts?state=open&per_page=100" --jq '.[] | {
  number, url: .html_url, type: .secret_type_display_name, validity,
  created_at, push_protection_bypassed }'

gh api --paginate "repos/$REPO/secret-scanning/alerts/<number>/locations" --jq '.[] | {
  type, path: .details.path, line: .details.start_line, commit: .details.commit_sha }'

gh api --paginate "repos/$REPO/security-advisories?per_page=100" --jq '.[]
  | select(.state == "triage" or .state == "draft") | {
  ghsa: .ghsa_id, url: .html_url, state, severity, summary,
  affected: [.vulnerabilities[]? | {package: .package.name, vulnerable: .vulnerable_version_range}] }'
```

Fetch every source. A 403/404 on one source means no access or the feature is disabled
(code scanning returns "no analysis found"; advisories need admin or security-manager access).
Record that source as unavailable, with the reason, and continue. Stop only if every source fails.

If the user gave expected counts, compare them with the fetched counts and state any mismatch
up front.

Dependabot and code scanning alerts reflect the default branch
(`gh repo view --json defaultBranchRef`), not the current worktree. Before tracing, check whether
the current branch already differs: compare installed versions with each vulnerable range, and
re-read each flagged line.

## 2. Dependabot: trace root causes

Group alerts by package and manifest. Many alerts on one package usually share a single fix.
Use the tools for the manifest's ecosystem; pick the JS package manager from the lockfile.

| Ecosystem      | Why is it installed                | Force a version                           | Audit               |
| -------------- | ---------------------------------- | ----------------------------------------- | ------------------- |
| npm            | `npm explain <pkg>`                | `overrides`                               | `npm audit`         |
| pnpm           | `pnpm why <pkg>`                   | `pnpm.overrides`                          | `pnpm audit`        |
| yarn           | `yarn why <pkg>`                   | `resolutions`                             | `yarn npm audit`    |
| pip / uv       | `uv tree --invert --package <pkg>` | constraints file or direct pin            | `pip-audit`         |
| Go             | `go mod why -m <mod>`              | bump the `require` line                   | `govulncheck ./...` |
| Cargo          | `cargo tree -i <crate>`            | `cargo update -p <crate> --precise <ver>` | `cargo audit`       |
| GitHub Actions | the workflow's `uses:` line        | bump the action ref                       | —                   |

For other ecosystems, use the native reverse-dependency command. If dependencies are not
installed, install from the lockfile without changing it (`npm ci`,
`pnpm install --frozen-lockfile`, `yarn install --immutable`).

For each package:

1. **Find the chain to a direct dependency.** The root cause is the direct dependency, an
   existing override/resolution, or a stale lockfile, not the transitive package itself.
2. **Check existing overrides first.** An override pinning a vulnerable version is the root
   cause itself. Plan to bump or remove it.
3. **Pick the fix, highest rung first:**
   1. The direct dependency is unused → remove it (search imports, config, and scripts).
   2. The parent's version range already allows the patched version → lockfile refresh only.
   3. A newer release of the direct dependency pulls the patched version → upgrade it. Check
      the release's declared dependencies, and read the changelog for major bumps.
   4. No parent release fixes it → a scoped override to the patched version, with a removal
      condition recorded in the plan.
4. **Respect any minimum release age** the repo enforces (for example `.npmrc`
   `min-release-age`, pnpm `minimumReleaseAge`). Check publish dates (`npm view <pkg> time --json`
   or the registry). If the patched version is too new, record the date it becomes installable.
5. **Respect pinned runtimes** (`.nvmrc`, `.node-version`, `.python-version`, `.tool-versions`,
   `go.mod`'s `go` line). Check the target version's engine requirements.
6. **Note the exposure.** `scope: runtime` ships to users or servers; `development` affects
   tooling and CI only. Order the work by severity, then runtime before development.

## 3. Code scanning: verify, then trace

Group alerts by rule, then by the code they share. For each alert, read the rule help, the
flagged code, and its callers. For data-flow rules, trace the flow from source to sink.

1. **Verify it.** It is a false positive only with evidence: the input is already validated or
   sanitized upstream, the code is unreachable, or it is test-only or generated code. If in
   doubt, treat it as real.
2. **Find the root cause.** Fix the shared place every flagged path goes through, such as the
   helper, sanitizer, sink wrapper, or a shared workflow setting. Several alerts that one fix
   resolves share one root-cause row.
3. **Fix the analysis config when the alert is about scope.** Alerts in vendored, generated, or
   build output come from the analysis config (CodeQL `paths-ignore`, or the workflow), not from
   the code.
4. **Never plan an inline suppression** as the fix for a real alert.
5. **Route by kind.** Workflow rules (for example `actions/*`) are fixed in the workflow file.
   Dependency findings from third-party SARIF tools (Trivy, Grype) follow section 2.

Fixed alerts close automatically after the next analysis of the default branch. False positives
are a manual dismissal by the user: `false positive`, `used in tests`, or `won't fix`.

## 4. Secret scanning: classify, then trace

For each alert, read the code around every location and classify it:

- **Test fixture**: a test file, a value that is not a working credential, `validity` is
  `unknown` or `inactive`, and no production code reads it. Root cause: a literal that matches
  the provider's secret pattern. Fix: build the value at runtime in the test (for example,
  the provider prefix plus random bytes), or use a value that fails the provider pattern if the
  code under test does not validate the format. When several files repeat the value, add one
  shared test helper and reuse it.
- **Real credential**: anything else, or any doubt. Plan to (1) rotate it at the provider,
  (2) update every place that stores it (hosting and CI secrets, secret managers, local `.env`
  files), (3) remove the literal and read it from the environment, and (4) check provider logs
  for misuse. Rotation comes first because the value stays in git history.

Never plan a git history rewrite: rotation already neutralizes the leak, and a rewrite needs a
force-push that disrupts every clone and open PR. Plan the GitHub alert closure as a manual step
for the user: `used_in_tests` for fixtures and `revoked` for rotated credentials. Secret alerts
do not close automatically.

## 5. Repository security advisories

Triage and draft advisories are private vulnerability reports against the repo's own code.
Treat each as a confirmed code scanning alert: find the vulnerable code from the summary and
affected versions, then trace the root cause as in section 3. In the plan, reference the GHSA ID
and the affected files only; keep reproduction details out. Publishing the advisory and
requesting a CVE after the fix ships are manual user steps.

## 6. Write the plan

Write `<plans dir>/<YYYY-MM-DD>-security-alerts.md`, creating the directory if missing:

```markdown
# Security alerts fix plan — <date>

Fetched: <n> Dependabot (<critical>/<high>/<medium>/<low>), <n> code scanning, <n> secret scanning,
<n> advisories. Unavailable: <source: reason | none>. Default branch: <branch>.

## Root causes

| #   | Root cause                                   | Fix                              | Closes alerts         | Scope   | Max severity |
| --- | -------------------------------------------- | -------------------------------- | --------------------- | ------- | ------------ |
| 1   | <direct-dep>@<ver> pins <pkg>@<vuln-ver>     | Upgrade <direct-dep> to <ver>    | dependabot #<n>, #<n> | dev     | critical     |
| 2   | Unsanitized input reaches <sink> in <helper> | Sanitize once in <helper>        | code #<n>, #<n>       | runtime | high         |
| 3   | Provider-pattern literal in <n> test files   | Runtime-generated fixture helper | secret #<n>           | test    | —            |

## Steps

Ordered, one commit-sized step each: files touched, exact command, and alerts closed. Rotate
real credentials first, then order by severity, runtime before development.

## Blocked or deferred

Alerts with no upstream fix or inside a minimum-release-age window, with the unblock date or condition.

## Verification

- Clean install from the lockfile; the "why" command shows only patched versions; the audit command agrees.
- The repo's lint, typecheck, and test gates for the consumers of each changed package.
- A build when a runtime or build-tool dependency changes and CI does not build on PRs.
- Fixture changes: the affected test suites.
- Code changes: the tests that cover the fixed path; code scanning re-runs on the PR.

## Manual GitHub steps (user)

- Close secret alerts with reason <used_in_tests | revoked>.
- Dismiss code scanning false positives with reason <false positive | used in tests | won't fix>.
- Publish fixed advisories and request CVEs.
- Dependabot and fixed code scanning alerts close automatically once the fix merges to <default branch>.
```

Every open alert must appear in exactly one root-cause row or in the "Blocked or deferred"
section. Before finishing, check that the alert numbers in the plan match the fetched list.

## Output

In chat: the plan path, the counts, and the root-cause table. Nothing else. Do not offer to
start fixing; the user will ask.
