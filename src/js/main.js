import { MenuScene } from './scenes/MenuScene.js'
import { CreditScene } from './scenes/CreditScene.js'
import { InstructionsScene } from './scenes/InstructionsScene.js'
import { GameScene } from './scenes/GameScene.js'
import { NewGameScene } from './scenes/NewGameScene.js'
import { LoadScene } from './scenes/LoadScene.js'
import { CharacterSelectScene } from './scenes/CharacterSelectScene.js'
import { Constants } from './components/Constants.js'
import { pruebaScene } from './scenes/prueba.js'

const config = {
  title: Constants.game.gameName,
  url: Constants.game.url,
  version: Constants.game.version,
  type: Phaser.AUTO,
  width: Constants.game.width,
  height: Constants.game.height,
  parent: 'output',
  scene: [
    LoadScene,
    MenuScene,
    GameScene,
    InstructionsScene,
    CreditScene,
    NewGameScene,
    CharacterSelectScene,
  ],
  physics: {
    default: Constants.game.arcadeEngine,
    arcade: {
      width: 1400,
      checkCollision: {
        up: false,
      },
      debug: Constants.game.debug,
      debugShowBody: Constants.game.debugShowBody,
      debugShowStaticBody: Constants.game.debugShowStaticBody,
      debugShowVelocity: Constants.game.debugShowVelocity,
    },
  },
}
let game = new Phaser.Game(config)
