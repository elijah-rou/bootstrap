# Native tool equivalents

Read only the section needed for the task. These are workflows for Codex's shell and native tools, not additional registered tools. Check installed command help before relying on version-specific options. Missing programs are an explicit capability gap, not permission to install packages.

## GitHub PR feedback

Use for review comments, unresolved threads, failing checks, and check annotations. This workflow is read-only; responding, resolving, approving, merging, and pushing require separate authorization.

1. Establish the requested repository and PR. For the current repository, `gh repo view --json nameWithOwner` and `gh pr view --json number,url,headRefOid,state,isDraft,mergeable,reviewDecision,comments,reviews,statusCheckRollup` give the starting context.
2. Fetch review threads with `gh api graphql`, including `isResolved`, `isOutdated`, file/line, comment bodies, authors, and URLs. Paginate both the thread connection and nested comments. Exclude resolved/outdated threads unless requested, and distinguish human feedback from bot output. `gh pr view` alone does not establish that every unresolved thread was retrieved.
3. Inspect check runs for the PR's exact head SHA using `gh api`; fetch annotations for failed runs where available. Use `gh run view` for failed job logs when annotations are insufficient. Do not mistake pending checks or unavailable results for success.
4. Bound retrieval to the relevant PR and failing checks. Start with at most 100 items per connection and ten pages; report truncation, inaccessible checks, and skipped log sections. Continue only where a remaining item can change the local action list.
5. Return actionable findings with source URLs and affected paths. Include PR state, draft status, merge conflicts, aggregate review decision, unresolved threads, and failed/pending checks. Report unknown or unavailable readiness fields explicitly; green checks alone do not establish readiness. Separate required changes, unresolved decisions, and external failures. Do not post, resolve threads, or alter the PR during collection.

## PDF metadata and bounded extraction

Use `pdfinfo` and `pdftotext` when a suitable native PDF tool or installed PDF skill is unavailable. Inspect metadata before selecting ranges in a long document.

- Treat page numbers as absolute, 1-indexed integers. Require `1 <= first <= last <= page_count` and at most 200 pages per extraction. Begin with a small range, not the maximum.
- Run `pdfinfo "$pdf"` to establish page count. Run `pdftotext -f "$first" -l "$last" "$pdf" "$output"` with a private temporary output path outside the repository.
- Check the extraction's exit status before reading its output. A timeout, cancellation, or killed subprocess is not success. Do not hide extraction failures behind a pipe to `head`.
- Read at most 50 KB into the conversation at once and label truncation. Keep absolute page references when continuing or quoting. If page attribution matters, extract individual pages rather than guessing from a chunk's relative position.
- Scanned/image-only PDFs may require OCR or rendered-page inspection. Empty text is not evidence that the page is empty. Report unavailable OCR/rendering instead of inventing content.
- Clean up temporary files when no longer needed. Do not copy confidential documents or extracted text into tracked files without authorization.

## Other mappings and gaps

| Need | Native-first path | Limit |
|---|---|---|
| Tests, lint, typecheck | Run the project's real commands through Codex's shell, with bounded execution and output | Shell success alone does not establish that the intended tests ran; inspect results |
| Source search | `rg`, targeted file reads, existing symbol-aware tooling | Lexical search is not LSP definition/reference resolution |
| LSP diagnostics | Use installed project checks; use an existing approved LSP integration when semantic results are required | Do not report absent diagnostics as clean or install a new server silently |
| Isolated work | `git worktree` and the active client's worktree support | One writer per checkout; no automatic prune or publication; no Pi registry equivalence claimed |
| Web evidence | Native web search/browsing, or bounded shell fetches of known URLs | Preserve exact sources and retrieval gaps; no Pi multi-provider or curator equivalence claimed |
| Questions and delegation | Native Codex tools exposed by the session | T3 may present these differently; unsupported Pi dialogs and orchestration APIs are not available |
| Administrative actions | Native approval boundaries and direct operator execution for privileged work | No Pi privilege bridge or publication interceptor is installed by this port |
| Clipboard, notifications, browser opening | Client UI where available | A host command does not operate the remote client's desktop |

If a missing capability blocks an actual task, identify the required behavior and propose the smallest maintained integration. Do not build an MCP compatibility layer merely to preserve an old tool name.
