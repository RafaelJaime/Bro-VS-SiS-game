# Hub Model Distribution Specification

## Purpose

How models are advertised, discovered, downloaded, cached, validated and presented in the game: the Hugging Face tag contract, the `bvs.json` sidecar, a repo+revision cache, pre-play validation, a bundled offline default model, and the download UX. Read-only Hub API use by the game is allowed. Verification: Godot smoke tests (`hf_picker.gd` and new ones) with stubbed HTTP.

## Requirements

### Requirement: Tag contract

A model is a candidate when tagged `BVS`. It is Compatible only when it also carries `bvs-schema-N` with N equal to the current playable schema version (`HubModel.BVS_SCHEMA_VERSION`, 4). A `BVS` model with an older schema tag (including schema 3 and schema 2, even though they remain registered for frozen decoding and tests) or with an unknown or future schema tag MUST be listed as "Trained for an older version" (older) or as unsupported (future) and MUST NOT be selectable. A `BVS` model with no schema tag MUST be treated as schema 1.
(Previously: Compatible meant `bvs-schema-3`; schema 3 was current.)

#### Scenario: Compatible
- GIVEN a model tagged `BVS` and `bvs-schema-4`
- WHEN listed in the picker
- THEN it is badged Compatible and selectable

#### Scenario: Schema 3 is older
- GIVEN a model tagged `BVS` and `bvs-schema-3`
- WHEN listed
- THEN it is badged "Trained for an older version" and cannot be selected

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

A model repo MUST provide `bvs.json` with `schema_version`, `obs_dim`, the action layout, `action_repeat`, `trained_on_commit`, and an optional difficulty or label. The game MUST validate the sidecar before play: `schema_version` equals the current playable version (4), `obs_dim` equals that schema's `obs_dim` (149), the action layout equals the schema's layout, and `action_repeat` is a positive integer. A sidecar declaring a registered but non-current version (schema 3 or 2) MUST be rejected with a visible reason naming the version as older.
(Previously: current version was 3 and only schema 2 was named as older.)

#### Scenario: Valid sidecar
- GIVEN a sidecar matching schema 4
- WHEN validated
- THEN validation passes

#### Scenario: Schema 3 sidecar rejected
- GIVEN a sidecar declaring `schema_version` 3
- WHEN validated for play
- THEN it is rejected with a visible reason stating it was trained for an older version

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

### Requirement: Model and ONNX cross-check

Before reporting ready, the game MUST confirm that the ONNX input dimension equals both the sidecar `obs_dim` and the schema's `obs_dim`, and that the model loads in the interpreter (op whitelist satisfied). A failing model MUST be rejected with a visible reason and MUST NOT be cached as ready.

#### Scenario: ONNX dim disagrees with sidecar
- GIVEN an ONNX with input dim 30 and a sidecar declaring 40
- WHEN validated
- THEN it is rejected with a visible reason

#### Scenario: Unsupported op
- GIVEN an ONNX containing an unsupported op
- WHEN validated
- THEN it is rejected with a reason naming the op

### Requirement: Repo and revision cache

Downloaded models MUST be cached under `user://models/<owner>__<name>/<sha>/`, keyed by repo id and the resolved revision sha. The game MUST resolve the revision sha with one metadata call per selection and MUST download `model.onnx` and `bvs.json` from the pinned `resolve/<sha>/` URLs. A cached, previously validated revision MUST be reused without a download. A different revision of the same repo MUST download again. Legacy `user://Agent{N}.onnx` files MUST be ignored and MUST NOT influence controller selection.

#### Scenario: Cache hit
- GIVEN a validated cache entry for repo R at sha S
- WHEN R is selected and the resolved sha is S
- THEN no model download occurs and it is ready immediately

#### Scenario: New revision
- GIVEN a cache entry for R at sha S1
- WHEN R is selected and the resolved sha is S2
- THEN files are downloaded to the S2 directory and S1 is untouched

#### Scenario: Different model, same slot
- GIVEN a model A was previously used by player 1
- WHEN the user selects model B for player 1
- THEN B's own files are used and A's are not

#### Scenario: Legacy file ignored
- GIVEN `user://Agent1.onnx` exists
- WHEN any selection is made
- THEN the file is not read

#### Scenario: Partial download not trusted
- GIVEN a download interrupted after `model.onnx` but before `bvs.json`
- WHEN the repo is selected again
- THEN the entry is not treated as valid and the missing files are re-downloaded

### Requirement: Bundled default model

The default model MUST be bundled under `res://`, trained and exported for the current schema (4), and selectable at character select as "BVS default" without network access, including in the web export. It MUST pass the same validation as Hub models. Selecting it MUST NOT trigger any HTTP request. The schema-3 bundled model MUST NOT remain the Compatible default once the current schema is 4 (a schema-4 runtime cannot play it). If the retrained model fails the acceptance gates in `rl-training-pipeline`, the schema-4 switch MUST NOT ship (see `ai-schema` "Version switch is gated"); the delivery decision at an exhausted time box is made by the user.
(Previously: bundled default trained for schema 3; old model kept on gate failure.)

#### Scenario: Offline selection
- GIVEN no network
- WHEN the user selects "BVS default" for a player
- THEN the model loads from `res://`, validates against schema 4, and the match can start

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
- THEN `schema_version` is 4 and `obs_dim` is 149

### Requirement: Download and loading UX

While a Hub model is resolving or downloading, the UI MUST show a loading state with a cancel action. On cancel, the transfer MUST stop and the selection MUST revert to the previous controller. On any failure (network error, HTTP error, rate limit, validation failure), the UI MUST show a visible error with the reason, MUST NOT start the match with that selection, and MUST NOT silently substitute the scripted CPU.

#### Scenario: Loading state
- GIVEN the user selects an uncached Hub model
- WHEN the download is in progress
- THEN a loading indicator and a cancel button are visible

#### Scenario: Cancel
- GIVEN a download in progress
- WHEN cancel is pressed
- THEN the transfer stops, the previous selection is restored, and no cache entry is marked ready

#### Scenario: Network failure
- GIVEN the Hub is unreachable
- WHEN the user selects an uncached model
- THEN a visible error is shown and the match cannot start with that model

#### Scenario: Rate limit
- GIVEN the Hub returns HTTP 429
- WHEN resolving the revision
- THEN the error states the rate limit and nothing is cached

#### Scenario: No silent CPU fallback
- GIVEN any failure while preparing a policy model
- WHEN the player tries to start the match
- THEN the policy fighter is never replaced by the scripted CPU without the user choosing it

### Requirement: Picker compatibility with the current schema

The existing picker (username search, `BVS` tag search, related-models fallback, compatibility badges, two-step model selection) MUST keep working, using the tag contract above with the current playable schema (4).
(Previously: named schema 3 as the compatible schema.)

#### Scenario: Username search
- GIVEN a username with one schema-4 and one schema-3 BVS model
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
