# UnityUpdates Demo - Build Tracker

**Spec:** [`unityupdates-demo-spec.md`](unityupdates-demo-spec.md)
**Process:** `OPEN-SOURCE-PLAYBOOK.md` steps 4-12
**Boilerplate:** open-base (scaffolded with `new-open-app.sh unityupdates "UnityUpdates" "..."`)

| # | Phase | Status |
|---|---|---|
| 1 | Branding and config: `.env(.example)`, layout fallback name, accent CSS, landing page, base dashboard removed | `[x]` |
| 2 | Models: `StoryDraft`, `SourceCheck` migrations, validations, constants, associations | `[x]` |
| 3 | Routes and controllers: `StoryDraftsController` CRUD, `SourceChecksController` (index redirect, rate limit, rescues) | `[x]` |
| 4 | Views and Stimulus: dashboard, form, draft page, result page, `generating`, `form_submit`, `download_markdown` | `[x]` |
| 5 | AI integration: `unityupdates_source_check_v1` prompt, parser, `SourceNameCheck`, `PersonNameCheck`, one-line fields | `[x]` |
| 6 | Seeds: template, Alder Park garden example draft with a completed check, `demo_placeholder_v1` removed (seed, case file, DB row) | `[x]` |
| 7 | Guardrails and evals: `config/ai_guards.yml`, `evals/cases/unityupdates_source_check_v1.yml` (8 cases, each code rule mirrored) | `[x]` |
| 8 | Specs: models, both checks, seeds, requests; `bundle exec rspec` green; `bin/rails evals:guardrails` PASS | `[x]` |
| 9 | README rewrite, UI journey manifest (port 3131), pre-publish check, local commit | `[x]` |

## Quick reference

```
story_drafts_path                         GET  /drafts   (also /dashboard)
new_story_draft_path                      GET  /drafts/new
story_draft_path(d)                       GET  /drafts/:id
edit_story_draft_path(d)                  GET  /drafts/:id/edit
story_draft_source_checks_path(d)         POST /drafts/:id/checks   (GET redirects to the draft)
story_draft_source_check_path(d, c)       GET  /drafts/:id/checks/:id
```

```
Template:   unityupdates_source_check_v1   (gemini-2.5-flash, 8192 max tokens, temperature 0.3)
Variables:  headline, label, beat, sources_text, notes
JSON:       claims[0-15]{claim, state: sourced|single_source|unsourced, source_name, how_to_firm_up},
            affected_not_heard[0-5], loaded_words[0-6]{word, why}, questions_to_ask[3-6], label_fit
Code rules: state enum; cited sources in the Sources box; no person not in the input; 3-6 questions; one-line fields
```

## Not done here (needs the owner)

- Live runs: `bin/rails evals:run` and `./ui-journey-fleet.sh --yes open-unityupdates` (real Gemini calls), and `./ui-journey-fleet.sh --free open-unityupdates`.
- `Open/README.md` app count and `git open repos.md` remote line (shared files, updated by the coordinator).
- GitHub repo creation and push.
