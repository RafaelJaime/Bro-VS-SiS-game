import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'

export class MenuScene extends BaseScene {
  constructor() {
    super(Constants.scenes.menu)
  }

  create() {
    this.lights.enable().setAmbientColor(Constants.colors.lightGray)
    this.playMusic(Constants.assets.audios.title, 0.005, true)
    this.setDefaultBackground()
    this.textos()
    this.botones()
    this.players()
  }

  textos() {
    this.addImage(400, 130, Constants.assets.images.front, 1)
    this.addLight(430, 130, 200, 240, 1)
    this.addText(
      700,
      570,
      Constants.texts.version,
      Constants.fonts.primaryBold25
    )
  }

  botones() {
    this.addButton(
      400,
      300,
      Constants.assets.images.button1,
      1.5,
      true,
      Constants.scenes.game
    )
    this.addButton(
      430,
      368,
      Constants.assets.images.button2,
      1.4,
      true,
      Constants.scenes.instructions
    )
    this.addButton(
      378,
      443,
      Constants.assets.images.button3,
      1.4,
      true,
      Constants.scenes.credit
    )
  }

  players() {
    // P1
    this.player1 = this.add
      .sprite(500, 300, Constants.assets.images.player11)
      .setDepth(1)
      .setScale(0.18)
      .setPipeline(Constants.pipeline)
    this.addLight(1000, 600, 800, 20 * 10, 20)
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
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      y: 310,
      ease: 'Power1',
      duration: 2000,
      delay: 750,
      yoyo: true,
      repeat: -1,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: 720,
      ease: 'Power2',
      duration: 2000,
      delay: 750,
      yoyo: true,
      repeat: -1,
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
    this.addLight(0, 600, 2000, 1 * 10, 5)
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
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      x: 120,
      ease: 'Power1',
      duration: 2000,
      delay: 1500,
      yoyo: true,
      repeat: -1,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      y: 340,
      ease: 'Power1',
      duration: 2000,
      delay: 1500,
      yoyo: true,
      repeat: -1,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
  }

  addLight(x, y, length, color, depth) {
    this.lights.addLight(
      x,
      y,
      length,
      Phaser.Display.Color.HSVColorWheel()[color].color,
      depth
    )
  }
}
