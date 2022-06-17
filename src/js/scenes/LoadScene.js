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
    this.scene.start(Constants.scenes.characterSelect)
  }
  update() {}
}
