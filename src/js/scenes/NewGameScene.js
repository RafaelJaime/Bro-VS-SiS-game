import { Constants } from '../components/Constants.js'
import { GameBaseScene } from '../components/GameBaseScene.js'
import { Player } from '../components/Objects/Player.js'

export class NewGameScene extends GameBaseScene {
  init(data) {
    this.decision = [data.player1, data.player2]
    console.log(this.decision)
  }

  constructor() {
    super(Constants.scenes.newGame)
  }
  create() {
    super.create()
    this.staticsObjects = this.physics.add.staticGroup()

    this.setBackground()
    this.setFlat()
    this.addReturnButton()
    this.camera()
    this.playersHealthBars()
    this.timer()

    // Player
    this.player1 = new Player(
      this,
      300,
      100,
      Constants.assets.images.rafaelAtlas,
      true,
      this.decision[0]
    )
    this.player1.createAnimations()
    this.physics.add.collider([this.player1], this.staticsObjects)
    this.cursor = this.input.keyboard.createCursorKeys()
    /*this.anims.create({
      key: 'idle',
      frames: this.anims.generateFrameNames(
        Constants.assets.images.matildeAtlas,
        {
          prefix: 'm_',
          suffix: '.png',
          start: 1,
          end: 2,
          zeroPad: 3,
        }
      ),
      frameRate: 4,
      repeat: -1,
    })*/
    //this.prueba = this.add.sprite(0, 0, Constants.assets.images.matildeAtlas)
    //this.prueba.play('idle')
  }

  update(time) {
    super.update()
    this.player1.update()
    // Camera y tile
    this.background3.tilePositionX = this.cameraFollow.x / 3
    this.background.tilePositionX = this.cameraFollow.x / 2
    this.cameraFollow.x -= 1

    if (this.cursor.left.isDown && !this.cursor.down.isDown) {
      this.player1.moveL()
    } else if (this.cursor.right.isDown && !this.cursor.down.isDown) {
      this.player1.moveR()
    } else if (
      this.cursor.up.isDown &&
      this.player1.body.touching.down &&
      !this.cursor.down.isDown
    ) {
      this.player1.jump()
    } else {
      this.player1.stay()
    }
  }

  // METHODS

  setBackground() {
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

  playersHealthBars() {
    this.setHealthBar(this.decision[0].name, 170, 50, this.decision[0].color)
    this.setHealthBar(
      this.decision[1].name,
      Constants.game.width - 170,
      50,
      this.decision[1].color
    )
  }

  music() {
    this.music = this.sound.add(Constants.assets.audios.bomb, {
      loop: true,
      volume: 0.3,
    })
    this.music.play()
  }

  setFlat() {
    this.staticsObjects.create(
      Constants.game.width / 2,
      Constants.game.height,
      Constants.assets.images.platform
    )
  }
}
