import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'

export class LoadScene extends BaseScene {
  constructor() {
    super(Constants.scenes.load)
  }
  preload() {
    this.preloadAssets()
    this.loadProgressBar()
  }
  create() {
    super.create()
    this.scene.start(Constants.scenes.newGame, {
      player1: Constants.getCharacterArray()[0],
      player2: Constants.getCharacterArray()[1],
    })
  }
  update() {}
}
