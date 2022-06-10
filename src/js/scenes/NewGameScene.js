import { Constants } from '../components/Constants.js'
import { GameBaseScene } from '../components/GameBaseScene.js'

class Player {
  health = 100
  abilitiesCd = 0
  flipX = true
  sprite = null
}

export class NewGameScene extends GameBaseScene {
  constructor() {
    super('NewGameScene')
  }
  create() {
    super.create()
    this.background()
    this.camera()

    //Ground
    this.flat = this.physics.add.staticImage(
      600,
      600,
      Constants.assets.images.platform
    )
  }

  update(time) {
    super.update()
    // Camera y tile
    this.background3.tilePositionX = this.cameraFollow.x / 3
    this.background.tilePositionX = this.cameraFollow.x / 2
    this.cameraFollow.x -= 1
  }

  // METHODS

  background() {
    this.background = this.add
      .tileSprite(0, 0, 3000, 1000, 'title')
      .setOrigin(0, 0)
      .setScale(0.68)
    this.background3 = this.add
      .tileSprite(0, 0, 3000, 1000, 'title3')
      .setOrigin(0, 0)
      .setScale(0.68)
  }

  camera() {
    this.cameraFollow = this.add.text(400, 20)
    this.myCam = this.cameras.main
    this.myCam.setBounds(0, 0, 1400, 0)
    this.myCam.startFollow(this.cameraFollow)
  }

  musica() {
    this.music = this.sound.add(Constants.assets.audios.bomb, {
      loop: true,
      volume: 0.3,
    })
    this.music.play()
  }
}
