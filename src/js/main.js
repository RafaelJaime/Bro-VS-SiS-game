import { MenuScene } from './scenes/MenuScene.js'
import { CreditScene } from './scenes/CreditScene.js'
import { InstructionsScene } from './scenes/InstructionsScene.js'
import { GameScene } from './scenes/GameScene.js'
import { NewGameScene } from './scenes/NewGameScene.js'
import { LoadScene } from './scenes/LoadScene.js'
const config = {
  type: Phaser.AUTO,
  width: 800,
  height: 600,
  parent: 'output',
  scene: [
    LoadScene,
    MenuScene,
    GameScene,
    InstructionsScene,
    CreditScene,
    NewGameScene,
  ],
  physics: {
    default: 'arcade',
    arcade: {
      width: 1400,
      checkCollision: {
        up: false,
      },
      debug: false,
      debugShowBody: false,
      debugShowStaticBody: false,
      debugShowVelocity: false,
    },
  },
}
let game = new Phaser.Game(config)
