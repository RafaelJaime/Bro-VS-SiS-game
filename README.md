# BroVSis (BVS)

<div align="center">
  <img src="assets/logos/ico.png" alt="BroVSis Logo" width="300" style="image-rendering: -webkit-optimize-contrast; image-rendering: crisp-edges;">
</div>

A **2D fighting game** built in **Godot 4** designed specifically for **Reinforcement Learning** training and experimentation. Train your own AI fighters and test them against each other in fights!

![Godot](https://img.shields.io/badge/Godot-4.7.2-blue?logo=godot-engine)
![ML-Agents](https://img.shields.io/badge/ML--Agents-Compatible-green)
![HuggingFace](https://img.shields.io/badge/🤗%20HuggingFace-Space%20Ready-orange)
![License](https://img.shields.io/badge/License-MIT-blue)

## 🌟 Features

### 🎮 Game Features
- **2D Fighting Mechanics**: Classic fighting game with movement, jumping, and combat
- **Multiple Characters**: Rafael and Matilde with unique sprites and animations (everyone is free to add Its own)
- **Dynamic Character System**: Modular character loading with animation frames
- **Real-time Combat**: Physics-based fighting with collision detection

### 🤖 AI & Machine Learning
- **Bundled opponent**: a trained "AI: BVS default" model ships with the game and works offline
- **Train your own**: PPO training, ONNX export and evaluation live in [`training/`](training/README.md); the step-by-step guide is [docs/train-your-own-model.md](docs/train-your-own-model.md)
- **Schema v2 (`bvs-schema-2`)**: a 102-float observation and 8 discrete action branches, frozen so published models keep working
- **Built-in inference**: models run in a small GDScript ONNX interpreter (MLP only), with no native dependencies, also in the web export
- **Hugging Face picker**: type a username to list their `BVS` models, or leave it empty to browse all of them

> 📚 **Want to train and publish your own fighter?** Follow the **[Train your own model guide](docs/train-your-own-model.md)**.

### 🌐 Hugging Face Integration
- **Community models**: browse models tagged `BVS` and fight them in the game
- **Compatibility badges**: only models tagged `bvs-schema-2` are selectable; others show why they are not
- **Pinned downloads**: models are fetched at a fixed revision, validated, and cached locally
- **ONNX**: a small, portable model format that runs on every platform the game exports to

## 🚀 Quick Start

### Prerequisites
- **Godot 4.7.2**: Download from [Godot homepage](https://godotengine.org/) or, if you can't find it, [Godot archiv](https://godotengine.org/download/archive/)
- **[uv](https://docs.astral.sh/uv/)**: For training (optional); it installs Python 3.12 and the pinned dependencies
- **Godot RL Agents**: Pre-installed in the project (`addons/godot_rl_agents`)

### 🎯 Running the Game

1. **Clone the repository**:
   ```bash
   git clone https://github.com/RafaelJaime/Bro-VS-SiS-game.git
   cd Bro-VS-SiS-game
   ```

2. **Open in Godot**:
   - Launch Godot Engine
   - Click "Import" and select the project folder
   - Open `project.godot`

3. **Play the game**:
   - Press `F5` or click the play button
   - Use arrow keys + space for Player 1 controls
   - Train AI opponents or play against friends!

### 🌐 Play Online (GitHub Pages)

The game is automatically deployed to GitHub Pages on every push to the `main` branch:

1. **Access the live game**: Visit the GitHub Pages URL for this repository
2. **No installation needed**: Play directly in your browser
3. **Automatic updates**: New features are deployed automatically via GitHub Actions

The deployment workflow:
- Exports the game to HTML5/Web format using Godot 4.7.2
- Deploys to GitHub Pages automatically
- Can be manually triggered from the Actions tab

## 🧠 AI Training

> 📚 **Full walkthrough: [docs/train-your-own-model.md](docs/train-your-own-model.md)** (train, export, evaluate, publish, play). Script reference: [training/README.md](training/README.md).

### Controller modes

Each player can be controlled by:

- **🎮 Human**: keyboard or gamepad
- **🤖 CPU**: scripted opponent at Easy, Normal or Hard
- **🧠 AI: BVS default**: the bundled trained model, no network needed
- **🤗 Hugging Face model**: any compatible `BVS` model chosen in the picker
- **🏋️ Training**: headless scene driven by the Python trainer through Godot RL Agents

### Observation space (schema v2)

`[1, 102]` float32, built by the game from the match state, "me first, opponent second" (authoritative layout: `game/ai/schema/bvs_schema_v2.gd`):

| Values | Content |
|--------|---------|
| 0 to 34 | Own state: position, velocity, facing, damage, stocks, held food, cooldowns, jumps, state one-hot... |
| 35 to 69 | The same 35 features for the opponent |
| 70 to 75 | Relative position, opponent in front, off stage, ledge occupancy |
| 76 to 87 | The 2 nearest foods |
| 88 to 99 | The 2 nearest projectiles |
| 100, 101 | Timer left, sudden death |

### Action space

`MultiDiscrete([3, 3, 2, 5, 2, 2, 2, 2])`, 21 logits, one decision every 4 physics frames:

| Branch | Choices |
|--------|---------|
| `a0_move` | 3 |
| `a1_vertical` | 3 |
| `a2_jump` | 2 |
| `a3_attack` | 5 |
| `a4_special` | 2 |
| `a5_throw` | 2 |
| `a6_block` | 2 |
| `a7_dash` | 2 |

### Training in short

```bash
cd training
uv sync
uv run python -m bvs_training.train --phase P1 --steps 4096 --seed 1   # smoke run
```

The full curriculum, export, evaluation and publishing steps are in the [guide](docs/train-your-own-model.md).

## 🤗 HuggingFace Integration

### In the game

1. On the character select screen, press **Use AI** for a player.
2. Type a Hugging Face username and press **Search** (empty lists every model tagged `BVS`).
3. Pick a model badged **Compatible**. The game downloads, validates and caches it, then shows **Ready**.

The bundled **AI: BVS default** model is also in the controller dropdown and works offline. A model that fails to load shows the reason; the game never silently substitutes the CPU.

### Model format

A model repo contains `model.onnx`, `bvs.json` (schema sidecar) and a `README.md` with the tags `BVS` and `bvs-schema-2`. The graph must be an MLP using the supported ops only. See [the model contract](docs/train-your-own-model.md#the-model-contract).

### Creating your own models

1. **Train** with `training/` ([guide](docs/train-your-own-model.md))
2. **Export** to ONNX with `bvs_training.export`
3. **Publish** to the Hub with tags `BVS` and `bvs-schema-2`
4. **Play** against it by searching your username in the picker

Reference model: [RafaelJaime/BVS-default](https://huggingface.co/RafaelJaime/BVS-default).

## 🏗️ Project Structure

```
bvs/
├── 🎮 game/                    # Core game logic
│   ├── player/                 # Fighters and controllers
│   ├── combat/, food/, stage/  # Combat, projectiles and stage
│   └── ai/                     # AI: schema/ (v2 obs + actions), onnx/ (interpreter),
│                               #     models/ (bundled default), training/ (RL scene)
├── 🧠 autoload/                # Autoloads
│   ├── model_manager.gd        # Hugging Face discovery, download and validation
│   └── scene_manager.gd        # Scene transitions
├── 🏋️ training/                # Python PPO training, ONNX export, evaluation
├── 📚 docs/                    # Guides (train-your-own-model.md)
├── 🎨 assets/                  # Game assets
├── 🔌 addons/                  # Godot plugins
│   └── godot_rl_agents/        # RL integration
└── 🖥️ ui/                      # Interface components (character select, model picker)
```

## 🎨 Character System

### Adding New Characters

1. **Create character folder**: `assets/images/game/characters/new_character/`
2. **Add animation folders**: `idle/`, `walk/`, `jump/`, `attack/`, etc.
3. **Place sprite frames**: Sequential PNG files (1.png, 2.png, ...)
4. **Create a `.tres` file**:
   - Open Godot and create a new `Character` resource.
   - Configure the character's properties (e.g., name, animations, stats).
   - Save the `.tres` file in the character's folder.

5. **Add the character to the selection list**:
   - Open the `character_select` scene.
   - Add the new `.tres` file to the `characters` array in the script or inspector.

## 📚 Learning Resources

### Reinforcement Learning
- [Godot RL Agents Documentation](https://github.com/edbeeching/godot_rl_agents)
- [Stable Baselines3](https://stable-baselines3.readthedocs.io/)
- [OpenAI Gym](https://gym.openai.com/)

### Godot Development
- [Godot Documentation](https://docs.godotengine.org/)
- [GDScript Reference](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/)
- [2D Game Development Guide](https://docs.godotengine.org/en/stable/tutorials/2d/)

## 🏆 Achievements & Metrics

Track your AI training progress:
- **Win Rate**: Against different opponents
- **Training Episodes**: Total learning iterations  
- **Reward Curves**: Performance over time
- **Battle Statistics**: Detailed combat analytics

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Godot Engine**: Amazing open-source game engine
- **Godot RL Agents**: Edward Beeching's fantastic RL integration
- **HuggingFace**: Platform for model sharing and deployment
- **Community**: All contributors and AI researchers

## 📞 Support & Community

- **GitHub Issues**: Bug reports and feature requests
- **Discussions**: Share your trained models and results
- **HuggingFace Space**: Try the live demo
- **Discord**: Join our AI gaming community

---

**Ready to train the ultimate AI fighter?** 🥊 Start your journey in BVS today!

[![HuggingFace Space](https://img.shields.io/badge/🤗-Try%20Live%20Demo-orange)](https://huggingface.co/spaces/RafaelJaime/BroVSister)
[![Training Guide](https://img.shields.io/badge/📚-Training%20Tutorial-blue)](docs/train-your-own-model.md)
