# Architecture

## Client
Flutter installed clients render protocols, schedule audio, collect responses, cache events and display explainable results.

## Protocol engine
A deterministic state machine owns trial selection, adaptive values, reversals, stopping, scoring and reliability. It is versioned independently from the UI.

## Audio/content
Stimulus packs contain manifests, hashes, licensing, talker/acoustic tags and validation state. Generated demo speech uses en-IN voices; psychoacoustic WAVs are generated at 48 kHz.

## API
FastAPI exposes profiles, catalog, sessions, trial events, results and recommendations. SQLite is the development store; production should use PostgreSQL with encrypted object storage.

## AI
The initial recommender is explainable and rules-first. Later contextual-bandit or Bayesian models may rank training tasks. Locked assessment behavior remains outside ML.

## Event lineage
Every trial records profile/session condition, output device, module/group/mode, target/response, correctness, latency, replay count, parameters, app version, protocol version and stimulus version.
