# Delta for Match Flow

## MODIFIED Requirements

### Requirement: Controller and difficulty selection UI

Character select MUST let each player choose Human or CPU (Easy/Normal/Hard). The existing ONNX/HF option MUST stay where it is, route via `PolicyController`, and additionally offer the bundled "BVS default" model. A match MUST NOT start while a selected policy model is downloading or invalid: the start action MUST wait for a pending download (showing the loading state from `hub-model-distribution`) and MUST report any download or validation failure before the match begins. The failed selection MUST NOT be replaced by a scripted CPU.
(Previously: the ONNX/HF option only had to stay in place and route via `PolicyController`; pending downloads and failures were not handled.)

#### Scenario: One player vs CPU
- GIVEN character select
- WHEN P1 = Human and P2 = CPU Hard
- THEN the match starts with P2 on a scripted Hard controller

#### Scenario: Two humans
- GIVEN both players = Human
- WHEN the match starts
- THEN both are human controlled

#### Scenario: Selection persists
- GIVEN a rematch
- WHEN it starts
- THEN controller and difficulty choices are retained

#### Scenario: Start waits for download
- GIVEN P2 = an uncached Hub model whose download is in progress
- WHEN the user presses start
- THEN the match does not begin until the model is ready, and the loading state is visible meanwhile

#### Scenario: Start after ready
- GIVEN the pending download completes and validates
- WHEN readiness is reported
- THEN the match starts with P2 on that model

#### Scenario: Failure blocks start
- GIVEN P2's model download or validation fails
- WHEN the user presses start
- THEN an error with the reason is shown, the match does not start, and P2 is not switched to CPU

#### Scenario: Bundled default selectable
- GIVEN no network
- WHEN P2 = "BVS default" and start is pressed
- THEN the match starts with P2 on the bundled model

#### Scenario: Rematch keeps model
- GIVEN a finished match where P2 used a validated model
- WHEN rematch is chosen
- THEN P2 uses the same model handle with no new download

## UNCHANGED Requirements

Pre-match countdown, Sudden death, Instant rematch, Pause toggle, and Instructions text and typo are unchanged by this change.
