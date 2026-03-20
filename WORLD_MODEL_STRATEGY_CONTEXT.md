# World Model Strategy Context

<!-- SHARED_WORLD_MODEL_STRATEGY_START -->
## Strategic Doctrine

Blueprint should assume world models will improve rapidly and that multiple viable model providers, papers, checkpoints, and hosted services will exist over time.

Blueprint should not build the company around one model.

Blueprint's durable moat should be:

1. capture quality and coverage
2. rights-safe, provenance-safe, qualification-first data pipelines
3. site-grounded retrieval, geometry, and conditioning substrates
4. a strong web product and operating system for buyers, operators, and internal ops
5. a compounding capture -> qualification -> preview/runtime -> buyer feedback -> more capture flywheel

The model backend is important, but it should be treated as a replaceable engine behind stable product and data contracts.

## Core Belief

Over time, world models may become more like LLM infrastructure:

- multiple strong frontier and open variants
- hosted APIs and managed services
- periodic capability jumps
- changing price / latency / quality frontiers
- easier model swapping at the application layer for teams with clean interfaces and proprietary data

If that happens, Blueprint should win by being the best source of trusted site-specific capture, conditioning data, qualification outputs, and deployment-facing product surfaces.

## What We Are Optimizing For

Blueprint is qualification-first, not model-first.

That means:

- qualification truth remains authoritative
- downstream preview/runtime/world-model outputs never rewrite qualification truth
- preview/runtime services are downstream product layers
- model backends should be swappable without forcing a redesign of capture, provenance, or web surfaces

## Practical Strategic Conclusion

Do not overfit the platform to any one of:

- a single paper
- a single checkpoint family
- a single hosted provider
- a single inference trick
- a single GPU profile

Instead, build the stack so that better model backends can be dropped in later with minimal changes above the model adapter layer.

## Current Product Truth

Today, the strongest near-term value comes from:

1. trusted qualification records and buyer-safe evidence bundles
2. privacy-safe derived previews and runtime prep artifacts
3. site-grounded scene-memory / retrieval / geometry substrates
4. hosted session surfaces that expose truthful preview, runtime state, and provenance clearly

Native SWM-like interaction is an important direction, but it is not the current platform foundation.

## How To Think About The Runtime

The current runtime should be treated as a bridge architecture:

- immediate interaction should come from cheap, truthful, site-grounded rendering paths
- expensive generative continuation should sit behind that as optional refinement
- the browser/runtime contract should not assume any specific model family

This is the right shape even if the current model is not yet good enough.

## What Must Stay Stable Across Model Swaps

These should be treated as long-lived platform contracts:

- raw capture bundle structure
- timestamps, poses, intrinsics, depth, and device metadata
- consent, rights, and privacy metadata
- qualification outputs and readiness decisions
- scene-memory and retrieval-memory artifacts
- site reference indices and grounding manifests
- runtime session/control/state/media/event contracts
- web attachment and sync contracts
- provenance and truth labeling in UI and APIs

If these remain stable, better world-model backends can be adopted later without redoing the product stack.

## What Must Remain Swappable

These should be deliberately replaceable:

- world-model checkpoints
- world-model providers
- inference services
- retrieval-conditioned generation strategies
- refinement models
- training/export adapters

No repo should assume that one specific model is the permanent backend.

## Platform Moat

Blueprint's moat should come from assets that get stronger when models commoditize:

- better real-site capture coverage
- stronger alignment between capture and deployment questions
- better privacy / rights / qualification enforcement
- better site-grounded conditioning data
- better buyer UX, hosted workflows, and operational surfaces
- better dataset feedback loops from real customer usage

If world models become easier to buy, the value of proprietary site-grounded data and deployment workflow should increase, not decrease.

## Product Implication

The company should be able to say:

- we do not depend on owning the single best world model
- we are the best system for turning real sites into trusted, deployable, buyer-usable world-model inputs and experiences

That is a stronger and more durable position than "we bet on one model stack."

## Build Priorities Right Now

For the current stage, prioritize:

1. capture quality and operator usability
2. data completeness for future training/eval use
3. rights/privacy/qualification rigor
4. robust downstream artifact generation and sync
5. web surfaces that can host truthful preview today and stronger world models later
6. stable runtime contracts that survive backend swaps

Do not spend disproportionate time chasing one more narrow inference optimization if the main blocker is model capability rather than pipeline correctness.

## Data Priority

Collect and preserve data now as if future world-model training and evaluation will depend on it.

That means preserving:

- walkthrough video
- motion / trajectory logs
- camera poses
- intrinsics
- depth when available
- timestamps and temporal alignment data
- device / modality metadata
- task / scenario / deployment context
- privacy / consent / rights metadata
- retrieval / reference relationships when derived

Future model quality will depend heavily on data quality and data structure.

## Repo-Level Guidance

Each repo should optimize for the same strategic posture:

- `BlueprintCapture`: capture the richest, cleanest, most reusable site evidence possible
- `BlueprintCapturePipeline`: materialize authoritative qualification outputs and reusable world-model substrates without coupling the platform to one backend
- `Blueprint-WebApp`: expose buyer, operator, preview, and hosted-session value through stable contracts that can survive backend changes

## Non-Goal

Do not assume the platform is "done" only when a perfect SWM-like runtime exists.

The correct goal is:

- build everything around the model so that when the model is ready, adoption is mostly a backend substitution rather than a company-wide rebuild

## Current External Signal

As of March 2026, the category signal supports this strategy:

- Seoul World Model shows that grounded real-world world models are a serious research direction, but the result comes from a full data + training + retrieval-aware model system, not a trivial runtime patch.
- Major platform vendors continue investing in physical AI / world-model-adjacent infrastructure.
- Capital is flowing into robotics and data-driven embodied AI companies, reinforcing the likelihood of continued model and service improvement.

Representative references:

- Seoul World Model project page: https://seoul-world-model.github.io/
- Seoul World Model paper, arXiv v1 dated March 16, 2026: https://arxiv.org/html/2603.15583v1
- Example market signal: TechCrunch, March 11, 2026, Mind Robotics raises $500M: https://techcrunch.com/2026/03/11/rivian-mind-robotics-series-a-500m-fund-raise-industrial-ai-powered-robots/

These references should inform strategy, not lock the platform to any one approach.

## Decision Rule For Future Sessions

When choosing between:

- investing in model-specific hacks
- investing in reusable platform/data/product infrastructure

default toward reusable infrastructure unless a model-specific change materially improves near-term user-visible value without increasing long-term coupling.
<!-- SHARED_WORLD_MODEL_STRATEGY_END -->
