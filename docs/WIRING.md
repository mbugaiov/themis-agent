# Wiring two-factor CR: review (Themis) + isolation (Themis)

Every engine and product PR should show **two** distinct checks (plus gate/tests):

| Check | What it enforces |
|-------|------------------|
| `review (Themis)` | Project `.cursor/rules/code-review.mdc` **+** shared MUST-HAVE `templates/engine-code-review-block.md` (tests with every behavior change) |
| `isolation (Themis)` | Portable isolation — checkout `themis-agent`, run `ci_isolation.sh` |

## 0. Shared MUST-HAVE — tests (all `review (Themis)` jobs)

Canonical text: [`templates/engine-code-review-block.md`](../templates/engine-code-review-block.md).

In the **review** job (not only isolation), checkout `themis-agent` and cite the
template in the `cursor-agent` prompt:

```yaml
      - uses: actions/checkout@v4
        with:
          repository: mbugaiov/themis-agent
          path: .themis-agent
      # …
          PROMPT="… Follow .cursor/rules/code-review.mdc AND .themis-agent/templates/engine-code-review-block.md (MUST-HAVE: new/changed behavior needs new or updated tests → Blocking). …"
```

Local `code-review.mdc` must not weaken that bar. Product-specific blockers may
be added beside it.

## 1. Engine repos (`dev-agent`, `qa-agent`, `ux-agent`, `themis-agent`)

Add a parallel job in `.github/workflows/code-review.yml`:

```yaml
  review:
    name: review (Themis)
    # … existing project review + themis checkout + shared tests template …

  isolation:
    name: isolation (Themis)
    if: github.event.pull_request.draft == false
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/checkout@v4
        with:
          repository: mbugaiov/themis-agent
          path: .themis-agent
      - name: Install Cursor CLI
        run: |
          curl -fsSL https://cursor.com/install | bash
          echo "$HOME/.cursor/bin" >> "$GITHUB_PATH"
          echo "$HOME/.local/bin" >> "$GITHUB_PATH"
      - name: isolation (Themis)
        env:
          CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
          BASE: ${{ github.base_ref }}
        run: |
          git fetch origin "${BASE}" --quiet || true
          bash .themis-agent/scripts/ci_isolation.sh --mode engine --base "origin/${BASE}"
```

Or use the composite action (same repo as this file):

```yaml
      - uses: mbugaiov/themis-agent/.github/actions/run-isolation@main
        with:
          mode: engine
          base-ref: origin/${{ github.base_ref }}
          cursor-api-key: ${{ secrets.CURSOR_API_KEY }}
```

Update auto-merge required check names to include `review (Themis)` and `isolation (Themis)`.

## 2. Product repos (Pantheon / LRM)

Mode=`product`. Pass peer tenants so cross-product leaks fail the scan:

```bash
bash .themis-agent/scripts/ci_isolation.sh --mode product \
  --base origin/main \
  --peer-pattern 'qa_lab_resource|lab-test-booking|lab-rm\.|LAB_RM_'
```

Pantheon: job in `.github/workflows/pr.yml`, `auto-merge` `needs: [gate, review, isolation]`.

LRM (Bitbucket): parallel step `Isolation (Themis)` next to `Cursor code review` / rename review to `Review (Themis)`.

## 3. Local / agent sub-step

Still optional in `code-review.mdc`:

```bash
bash "$THEMIS_AGENT_PATH/scripts/isolation_scan.sh" --mode engine --root "$PWD"
```

Primary enforcement is the **CI check** `isolation (Themis)`, not a section inside the project review comment.

## 4. Follow-ups (Suggestions / Risks) before merge

See [FOLLOWUPS.md](./FOLLOWUPS.md). Engines must run `check_review_followups_disposed.sh` (from this repo under `.themis-agent`) after required checks are green — in `wait_*_pipeline` and auto-merge — so Suggestions/Risks are fixed or filed as **same-repo** backlog issues.
