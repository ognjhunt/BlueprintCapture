# Blueprint Autonomous Organization Guide

> **Source of truth:** [Blueprint Hub on Notion](https://www.notion.so/16d80154161d80db869bcfba4fe70be3)
> The live company package and current org definition are maintained from `Blueprint-WebApp`.
> This repo-side file is a synced mirror for people working in `BlueprintCapture`.

## Current Authority

Treat these as the canonical operating files:

1. `/Users/nijelhunt_1/workspace/Blueprint-WebApp/AUTONOMOUS_ORG.md`
2. `/Users/nijelhunt_1/workspace/Blueprint-WebApp/ops/paperclip/blueprint-company/.paperclip.yaml`
3. `/Users/nijelhunt_1/workspace/Blueprint-WebApp/ops/paperclip/BLUEPRINT_AUTOMATION.md`

If this file drifts from those, update this file immediately rather than inventing a repo-local org shape.

## Platform Posture

Blueprint remains:

- capture-first
- world-model-product-first
- exact-site package and hosted-access focused
- rights-safe, privacy-safe, provenance-safe
- built so Paperclip owns execution state while agents operate on top of software and product systems

Do not reframe the company as qualification-first, model-checkpoint-first, or generic marketplace-first.

## Current Org Reality

Blueprint now runs as a Paperclip-centered operating system with Hermes used selectively for continuity-heavy roles.

Current high-level split:

- `Paperclip` is the execution record for issues, routines, assignments, and work state.
- `Notion` is the workspace, knowledge, review, and operator-visibility surface.
- `Hermes` is the persistent runtime for the chief of staff plus selected ops, growth, research, and commercial roles.
- `Claude` remains the default executive/review lane and the default lane for sensitive ops/review roles.
- `Codex` remains the default implementation lane for repo specialists.

## Department Snapshot

### Executive

- `blueprint-ceo` — Claude
- `blueprint-chief-of-staff` — Hermes
- `blueprint-cto` — Claude
- `investor-relations-agent` — Hermes
- `notion-manager-agent` — Hermes
- `revenue-ops-pricing-agent` — Hermes

### Engineering

- `webapp-codex`, `webapp-claude`
- `pipeline-codex`, `pipeline-claude`
- `capture-codex`, `capture-claude`
- `beta-launch-commander`
- `docs-agent`

### Ops

- `ops-lead`
- `intake-agent`
- `capture-qa-agent`
- `field-ops-agent`
- `finance-support-agent`
- `buyer-solutions-agent`
- `solutions-engineering-agent`
- `rights-provenance-agent`
- `security-procurement-agent`
- `capturer-success-agent`
- `site-catalog-agent`
- `buyer-success-agent`

### Growth

- `growth-lead`
- `conversion-agent`
- `analytics-agent`
- `community-updates-agent`
- `market-intel-agent`
- `supply-intel-agent`
- `capturer-growth-agent`
- `city-launch-agent`
- `demand-intel-agent`
- `robot-team-growth-agent`
- `site-operator-partnership-agent`
- `city-demand-agent`
- `outbound-sales-agent`

## What Touches BlueprintCapture

These are the primary agents with direct responsibility for this repo:

- `capture-codex` — implementation specialist for `BlueprintCapture`
- `capture-claude` — review and planning specialist for `BlueprintCapture`
- `field-ops-agent` — capture scheduling, assignment, reminders, and operator coordination on top of product systems
- `capturer-success-agent` — capturer activation, retention, recapture guidance, and operational feedback loops

Capture work is issue-driven in Paperclip: `capture-codex` should receive assigned issues, and ops or growth work that touches this repo should enter through Paperclip issues rather than only GitHub-originated events.

These agents regularly read this repo or create work against it:

- `blueprint-cto`
- `blueprint-chief-of-staff`
- `ops-lead`
- `beta-launch-commander`
- `docs-agent`

## Current Operational Shape

The live Paperclip package currently runs from the shared trusted host and includes:

- a continuous chief-of-staff managerial loop
- active repo autonomy loops for Capture, Pipeline, and WebApp
- issue-assignment-driven engineering loops for `capture-codex`, `pipeline-codex`, and `webapp-codex`
- active executive reporting routines
- active weekly or daily routines across growth and commercial lanes
- explicit paused routines for lanes that are intentionally not running continuously yet

For the exact current task and routine inventory, read:

- `/Users/nijelhunt_1/workspace/Blueprint-WebApp/ops/paperclip/blueprint-company/.paperclip.yaml`

## Rules For Capture Repo Work

When autonomous-org work touches `BlueprintCapture`, keep these constraints explicit:

- optimize for truthful real-site evidence collection
- preserve capture quality, bundle integrity, and provenance
- keep rights, privacy, and site-operator boundaries explicit
- route blockers, delegation, and validation through Paperclip issues, not prose alone
- do not let growth or ops copy overstate what the capture product or field workflows can currently support

## Maintenance Rule

This mirror should change whenever one of these changes:

- the role registry in `/Users/nijelhunt_1/workspace/Blueprint-WebApp/AUTONOMOUS_ORG.md`
- the live company package in `/Users/nijelhunt_1/workspace/Blueprint-WebApp/ops/paperclip/blueprint-company/.paperclip.yaml`
- the Paperclip/Hermes runtime split in `/Users/nijelhunt_1/workspace/Blueprint-WebApp/ops/paperclip/BLUEPRINT_AUTOMATION.md`

Do not keep an older repo-local org chart alive once the shared control plane has moved on.
