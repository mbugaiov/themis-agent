# Wiring two-factor CR: review (Themis) + isolation (Themis)

Every engine and product PR should show **two** distinct checks (plus gate/tests):

| Check | What it enforces |
|-------|------------------|
| `review (Themis)` | **Central pack** `themis-agent/review-rules/[0-9]*.md` (via `build_review_prompt.sh`) **+** local `.cursor/rules/code-review.mdc` |
| `isolation (Themis)` | Portable isolation — checkout `themis-agent`, run `ci_isolation.sh` |

## 0. Centralized review rules (no copy-paste across engines)

Canonical pack: [`review-rules/`](../review-rules/README.md).

| Goal | How |
|------|-----|
| Add a must-have for **all** Themis reviews | PR on **themis-agent**: add `review-rules/NN-name.md`, merge to `main` |
| Next review everywhere | Consumer `review` job checkouts themis (**unpinned `main`** for the pack) and runs `build_review_prompt.sh` — new files are inlined automatically |
| Product-specific blockers | Keep in local `code-review.mdc` only; must not weaken the pack |

### Review job shape

```yaml
  review:
    name: review (Themis)
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: actions/checkout@v4
        with:
          repository: mbugaiov/themis-agent
          # Unpinned = next shared rule on themis main applies without engine PR
          path: .themis-agent
      # … install cursor-agent …
      - name: Run Cursor code review
        env:
          CURSOR_API_KEY: ${{ secrets.CURSOR_API_KEY }}
          BASE: ${{ github.base_ref }}
        run: |
          git fetch origin "${BASE}" --quiet || true
          PROMPT="$(bash .themis-agent/scripts/build_review_prompt.sh \
            --pr "${{ github.event.pull_request.number }}" \
            --base "origin/${BASE}" \
            --label "${{ github.event.repository.name }}" \
            --local-rule .cursor/rules/code-review.mdc \
            --agents AGENTS.md \
            --themis-root .themis-agent)"
          cursor-agent --force --api-key "$CURSOR_API_KEY" --output-format text -p "$PROMPT" > review.md || true
```

**Do not** hardcode individual `review-rules/NN-*.md` paths in consumer prompts —
the builder loads the whole pack.

Isolation / follow-up scripts may stay on a **pinned** SHA via `ensure_themis_agent.sh`
for stability; the **review rules pack** should float on `main` so policy updates
propagate without control-C/V across engines.

**Reviewers:** do **not** Blocking-flag unpinned review + pinned isolation/ensure — that split is required. See `review-rules/40-wiring-review-float.md`.

## 1. Engine repos (`dev-agent`, `qa-agent`, `ux-agent`, `themis-agent`)

Add a parallel job in `.github/workflows/code-review.yml`:

```yaml
  review:
    name: review (Themis)
    # … build_review_prompt.sh as above …

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

Pantheon review job should also use `build_review_prompt.sh` (same as engines).

LRM (Bitbucket): parallel step `Isolation (Themis)` next to `Cursor code review` / rename review to `Review (Themis)`.

## 3. Local / agent sub-step

Still optional in `code-review.mdc`:

```bash
bash "$THEMIS_AGENT_PATH/scripts/isolation_scan.sh" --mode engine --root "$PWD"
```

Primary enforcement is the **CI check** `isolation (Themis)`, not a section inside the project review comment.

## 4. Follow-ups (Suggestions / Risks) before merge

See [FOLLOWUPS.md](./FOLLOWUPS.md). Engines must run `check_review_followups_disposed.sh` (from this repo under `.themis-agent`) after required checks are green — in `wait_*_pipeline` and auto-merge — so Suggestions/Risks are fixed or filed as **same-repo** backlog issues.
