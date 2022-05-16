import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'

export class MenuScene extends BaseScene {
  constructor() {
    super(Constants.scenes.menu)
  }
  create() {
    this.lights.enable().setAmbientColor(Constants.colors.lightGray)
    this.music = this.sound.add(Constants.assets.audios.title, {
      loop: true,
      volume: 0.05,
    })
    this.music.play()
    this.fondos()
    this.textos()
    this.botones()
    this.players()
  }
  fondos() {
    this.setParallaxBackground(Constants.assets.images.title2, 0.68)
    this.setBackground(Constants.assets.images.title, 0.68)
  }
  textos() {
    this.addImage(400, 130, Constants.assets.images.front, 1)
    this.light = this.lights.addLight(
      430,
      130,
      200,
      Phaser.Display.Color.HSVColorWheel()[240].color,
      1
    )
    this.addText(
      700,
      570,
      Constants.texts.version,
      Constants.fonts.primaryBold25
    )
  }
  botones() {
    this.addButton(400, 300, Constants.assets.images.button1, 1.5)
    this.addButton(430, 368, Constants.assets.images.button2, 1.4)
    this.addButton(378, 443, Constants.assets.images.button3, 1.4)
  }

  navigateGame() {
    this.music.stop()
    this.scene.start(Constants.scenes.game)
  }

  navigateInstructions() {
    this.music.stop()
    this.scene.start(Constants.scenes.instructions)
  }

  navigateCredits() {
    this.music.stop()
    this.scene.start(Constants.scenes.credit)
  }

  players() {
    // P1
    this.player1 = this.add
      .sprite(500, 300, Constants.assets.images.player11)
      .setDepth(1)
      .setScale(0.18)
      .setPipeline(Constants.pipeline)
    this.lights.addLight(
      1000,
      600,
      800,
      Phaser.Display.Color.HSVColorWheel()[20 * 10].color,
      20
    )
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: 700,
      ease: 'Power1',
      duration: 750,
      delay: 0,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })

    // P2
    this.player2 = this.add
      .sprite(300, 350, Constants.assets.images.player21)
      .setDepth(1)
      .setPipeline(Constants.pipeline)
      .setScale(0.18)
    this.lights.addLight(
      0,
      600,
      2000,
      Phaser.Display.Color.HSVColorWheel()[1 * 10].color,
      5
    )
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      x: 100,
      ease: 'Power1',
      duration: 750,
      delay: 750,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
  }
  update() {}
}
