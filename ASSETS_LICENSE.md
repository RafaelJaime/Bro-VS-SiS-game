# Asset licensing

This repository uses more than one license. [LICENSE](LICENSE) (MIT) covers:

- All source code: `game/`, `ui/`, `autoload/`, `training/`, `tests/`, scripts, scenes and `.tres` data files, build/CI configuration.
- The project-own assets listed below as "Rafael (project-own)".

Everything else — Matilde Jaime Moreno's artwork, and the third-party assets listed below — is **excluded from the MIT grant** and is licensed on its own terms, or not licensed for redistribution at all. Read this file before copying, redistributing or forking any asset in this repository.

## Artwork by Matilde Jaime Moreno — All Rights Reserved

The following paths are illustrations, sprites and UI art created by **Matilde Jaime Moreno**. They are **not** covered by the MIT license above. All rights are reserved by their author; no license is granted to copy, modify or redistribute this artwork outside this project without her written permission.

- `assets/images/game/characters/**` (Rafael and Matilde sprites, atlases, illustrations)
- `assets/images/ui/buttons/**`
- `assets/backgrounds/**`
- `assets/logos/**` (also used as the app/PWA icon)

If you want to use this artwork for anything beyond running this project's own code unchanged, contact Matilde Jaime Moreno for permission.

## Rafael Jaime Moreno — project-own, MIT

Licensed under MIT together with the code (see [LICENSE](LICENSE)):

- All code: `game/`, `ui/`, `autoload/`, `training/`, `tests/`, scripts, scenes, `.tres` data files.
- `assets/sounds/button.mp3`
- `game/ai/models/bvs_default/**` (the published Hugging Face twin [RafaelJaime/BVS-default](https://huggingface.co/RafaelJaime/BVS-default) is also MIT)

## Third-party assets

| Path | Author | Source | License | Status |
|------|--------|--------|---------|--------|
| `assets/sounds/freesound/431174__highpixel__fireball-explosion.wav` | Blankened (Freesound username; the filename says "highpixel", but the sound's current Freesound page attributes it to "Blankened" — see note below) | <https://freesound.org/s/431174/> | CC0 (Creative Commons Zero / public domain dedication) | Confirmed (fetched) |
| `assets/sounds/freesound/466126__nightwolfcfm__run-cinematic-music.mp3` | NightWolfCFM | <https://freesound.org/s/466126/> | **CC BY 4.0 (Attribution)** — requires crediting NightWolfCFM | Confirmed (fetched) — corrected; this file is **not** CC0, see note below |
| `assets/sounds/freesound/563356__nicholasdaryl__cartoonpunch.wav` | nicholasdaryl | <https://freesound.org/s/563356/> | CC0 (Creative Commons Zero / public domain dedication) | Confirmed (fetched) |
| `assets/textures/2D Fire  - Tutorial/*` | Channel "Le Lu" (YouTube handle `@Le_x_Lu`) | <https://www.youtube.com/watch?v=8_ryJN7Lsmo> ("GODOT 4 - 2D Fire shader for beginners") | Not stated by the source | **Not confirmed** — no license/terms for the tutorial's textures could be found in the fetchable page content |
| `assets/textures/Confetti/*` | GitHub user `benmccown` | <https://gist.github.com/benmccown/52eb2d9b0a2899fe4d6d6aea6514eafb> | CC0 ("If you want to use my sprite, feel free to do so with a CC0 License (I wave all rights to the file)") | Confirmed (fetched) |
| `addons/godot_rl_agents/**` | Edward Beeching | <https://github.com/edbeeching/godot_rl_agents> | MIT (copyright (c) 2021 Edward Beeching) | Confirmed (fetched); exact upstream text vendored at `addons/godot_rl_agents/LICENSE` |
| `coi-serviceworker.js` (fetched at build time, not stored in the repo) | Guido Zuidhof | <https://github.com/gzuidhof/coi-serviceworker> (pulled in `.github/workflows/deploy-pages.yml`) | MIT (copyright (c) 2021 Guido Zuidhof) | Confirmed (fetched) |

### Note on the Freesound entries

- **431174 — filename/author mismatch.** The file on disk is named `431174__highpixel__fireball-explosion.wav`, which encodes the Freesound username at the time it was downloaded. As of this writing, Freesound's own page for sound id `431174` (<https://freesound.org/s/431174/>, redirecting to `https://freesound.org/people/Blankened/sounds/431174/`) attributes the sound "Fireball Explosion.wav" to the username **Blankened**, not "highpixel". The license (CC0) is unaffected either way; only the credited name differs from the filename. Flagging this so the project owner can decide which name to credit.
- **466126 — license correction.** This project's previous documentation (`assets/sounds/README.md`) stated the whole `assets/sounds/freesound/` folder was CC0. That is **not accurate for this file**: Freesound's page for sound id `466126` ("Run (Cinematic Music)" by NightWolfCFM) links to `https://creativecommons.org/licenses/by/4.0/` — **Attribution 4.0**, which requires crediting the author when the sound (or a derivative) is shared. This file has been re-documented accordingly in `assets/sounds/README.md` and here. Attribution used: "Run (Cinematic Music)" by NightWolfCFM, <https://freesound.org/s/466126/>, licensed under CC BY 4.0.

### Note on the YouTube tutorial textures

`assets/textures/2D Fire  - Tutorial/*` traces back to a YouTube tutorial. The video's title and channel were confirmed via YouTube's oEmbed endpoint ("GODOT 4 - 2D Fire shader for beginners", channel "Le Lu", `@Le_x_Lu`), which matches the texture filenames (e.g. `T_LeLuStar11.jpg`). No explicit license or reuse terms for the tutorial's accompanying texture files could be retrieved from the page content available to this tool (YouTube's description text was not reachable). Treat these textures as **license not confirmed** until the project owner checks the video description/comments directly or contacts the channel.

## Unidentified third-party assets

The following assets are **not covered by any license in this repository** and are not attributed to the project owner or to Matilde Jaime Moreno. Their original source is unknown:

- `assets/images/game/food/**`
- `assets/images/game/plataformacuadrados.png`

The project owner should identify the original source and license of these files, or replace them with assets of known, compatible provenance.
