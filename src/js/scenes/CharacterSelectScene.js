import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'

export class CharacterSelectScene extends BaseScene {
  constructor() {
    super(Constants.scenes.characterSelect)
  }
  preload() {}
  create() {
    this.add.rectangle(10, 20, 50, 50, 0xffffff)
  }
  update() {}
}
