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
    this.addImage(
      Constants.game.width / 2,
      130,
      Constants.assets.images.front,
      1
    )
    this.addLight(Constants.game.width / 2 + 30, 130, 200, 240, 1)
    this.addText(
      Constants.game.width - 100,
      570,
      Constants.texts.version,
      Constants.fonts.primaryBold25
    )
  }

  botones() {
    this.addButton(
      Constants.game.width / 2,
      Constants.game.height / 2,
      Constants.assets.images.button1,
      1.5,
      true,
      false,
      Constants.scenes.characterSelect
    )
    this.addButton(
      Constants.game.width / 2 + 30,
      Constants.game.height / 2 + 68,
      Constants.assets.images.button2,
      1.4,
      true,
      false,
      Constants.scenes.instructions
    )
    this.addButton(
      Constants.game.width / 2 - 22,
      Constants.game.height / 2 + 143,
      Constants.assets.images.button3,
      1.4,
      true,
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
    this.addLight(
      Constants.game.width + 200,
      Constants.game.height,
      800,
      20 * 10,
      20
    )
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: Constants.game.width - 100,
      ease: 'Power1',
      duration: 750,
      delay: 0,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      y: Constants.game.height / 2 + 10,
      ease: 'Power1',
      duration: 8000,
      delay: 750,
      yoyo: true,
      repeat: -1,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: Constants.game.width - 80,
      ease: 'Power2',
      duration: 8000,
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
    this.addLight(0, Constants.game.height, 2000, 1 * 10, 5)
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
      duration: 8000,
      delay: 1500,
      yoyo: true,
      repeat: -1,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      y: Constants.game.height / 2 + 40,
      ease: 'Power1',
      duration: 8000,
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
