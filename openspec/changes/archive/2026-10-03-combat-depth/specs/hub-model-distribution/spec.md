# Delta for Hub Model Distribution

"Compatible" now means the current playable schema (3). Schema 2 stays registered for frozen decoding and tests but is no longer playable. Sidecar cross-checks, cache, download UX and bundled-default offline behavior are unchanged except where listed.

## MODIFIED Requirements

### Requirement: Tag contract

A model is a candidate when tagged `BVS`. It is Compatible only when it also carries `bvs-schema-N` with N equal to the current playable schema version (`HubModel.BVS_SCHEMA_VERSION`, 3). A `BVS` model with an older schema tag (including schema 2, even though schema 2 remains registered for frozen decoding and tests) or with an unknown or future schema tag MUST be listed as "Trained for an older version" (older) or as unsupported (future) and MUST NOT be selectable. A `BVS` model with no schema tag MUST be treated as schema 1.
(Previously: Compatible meant any `bvs-schema-N` supported by the registry, so schema 2 was Compatible.)

#### Scenario: Compatible
- GIVEN a model tagged `BVS` and `bvs-schema-3`
- WHEN listed in the picker
- THEN it is badged Compatible and selectable

#### Scenario: Schema 2 is older
- GIVEN a model tagged `BVS` and `bvs-schema-2`
- WHEN listed
- THEN it is badged "Trained for an older version" and cannot be selected

#### Scenario: Older schema
- GIVEN a model tagged `BVS` and `bvs-schema-1`
- WHEN listed
- THEN it is badged "Trained for an older version" and cannot be selected

#### Scenario: Untagged schema
- GIVEN a model tagged `BVS` only
- WHEN listed
- THEN it is treated as schema 1 and not selectable

#### Scenario: Future schema
- GIVEN a model tagged `bvs-schema-9`
- WHEN listed
- THEN it is not selectable and is badged as unsupported

### Requirement: Sidecar `bvs.json`

A model repo MUST provide `bvs.json` with `schema_version`, `obs_dim`, the action layout, `action_repeat`, `trained_on_commit`, and an optional difficulty or label. The game MUST validate the sidecar before play: `schema_version` equals the current playable version, `obs_dim` equals that schema's `obs_dim`, the action layout equals the schema's layout, and `action_repeat` is a positive integer. A sidecar declaring a registered but non-current version (schema 2) MUST be rejected with a visible reason naming the version as older.
(Previously: `schema_version` only had to be supported by the registry.)

#### Scenario: Valid sidecar
- GIVEN a sidecar matching schema 3
- WHEN validated
- THEN validation passes

#### Scenario: Schema 2 sidecar rejected
- GIVEN a sidecar declaring `schema_version` 2
- WHEN validated for play
- THEN it is rejected with a visible reason stating it was trained for an older version

#### Scenario: Obs dim mismatch
- GIVEN a sidecar whose `obs_dim` differs from the schema's
- WHEN validated
- THEN it is rejected with a visible reason naming expected and actual `obs_dim`

#### Scenario: Action layout mismatch
- GIVEN a sidecar with a different branch list
- WHEN validated
- THEN it is rejected with a reason naming the layout mismatch

#### Scenario: Missing or malformed sidecar
- GIVEN a repo with no `bvs.json`, or with invalid JSON
- WHEN selected
- THEN it is rejected with a visible reason and is not played

### Requirement: Bundled default model

The default model MUST be bundled under `res://`, trained and exported for the current schema (3), and selectable at character select as "BVS default" without network access, including in the web export. It MUST pass the same validation as Hub models. Selecting it MUST NOT trigger any HTTP request. If the retrained model fails the acceptance gates in `rl-training-pipeline`, the old bundled model is kept and the gate failure is reported; the delivery decision is then made by the user.
(Previously: no schema requirement on the bundled default.)

#### Scenario: Offline selection
- GIVEN no network
- WHEN the user selects "BVS default" for a player
- THEN the model loads from `res://`, validates against schema 3, and the match can start

#### Scenario: Web export
- GIVEN the web export
- WHEN "BVS default" is chosen
- THEN the model loads and plays with no network request

#### Scenario: Bundle corruption
- GIVEN the bundled files fail validation
- WHEN selected
- THEN a visible error is shown and no silent fallback to the CPU occurs

#### Scenario: Bundled sidecar schema
- GIVEN the committed bundled `bvs.json`
- WHEN read
- THEN `schema_version` is 3

## RENAMED Requirements

### Requirement: Picker compatibility with schema 2 → Picker compatibility with the current schema

(Reason: Compatible now tracks the current playable schema, not schema 2.)
(Migration: tests and docs referencing "schema 2 picker" read "current schema (3) picker".)

## MODIFIED Requirements

### Requirement: Picker compatibility with the current schema

The existing picker (username search, `BVS` tag search, related-models fallback, compatibility badges) MUST keep working, using the tag contract above with the current playable schema (3).
(Previously: named schema 2 as the compatible schema.)

#### Scenario: Username search
- GIVEN a username with one schema-3 and one schema-2 BVS model
- WHEN searched
- THEN the first is Compatible and the second is "Trained for an older version"

#### Scenario: Related-models fallback
- GIVEN a username with no BVS models
- WHEN searched
- THEN the existing related-models fallback behavior still occurs

#### Scenario: Older model not selectable
- GIVEN a listed "Trained for an older version" model
- WHEN the user tries to select it
- THEN selection is refused and no download starts
