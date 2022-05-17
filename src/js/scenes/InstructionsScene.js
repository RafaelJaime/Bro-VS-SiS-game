import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'

export class InstructionsScene extends BaseScene {
  constructor() {
    super(Constants.scenes.instructions)
  }
  create() {
    this.addReturnButton()
    this.setDefaultBackground()
    // Imagen central
    this.add.image(400, 400, Constants.assets.images.center).setScale(0.8)
    // Texto central
    this.texto()
    // Personajes laterales y animacion
    this.lights.enable().setAmbientColor(Constants.colors.darkGray)
    this.personajes()
  }

  texto() {
    var columna1 = 330
    var columna2 = 410
    var columna3 = 460
    this.add.text(280, this.game.renderer.heigh, Constants.texts.instructions, {
      font: Constants.fonts.secondaryBold50,
      fill: Constants.colors.black,
    })
    this.addText(
      columna1,
      260,
      Constants.texts.player1,
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      1
    )
    this.addText(
      columna3,
      260,
      Constants.texts.player2,
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      1
    )
    this.addText(
      columna2,
      310,
      Constants.texts.movement,
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      1
    )
    this.addText(
      columna2,
      390,
      Constants.texts.habilities,
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      1
    )
  }

  personajes() {
    this.player1 = this.add
      .sprite(-100, 320, Constants.assets.images.player12)
      .setDepth(1)
      .setPipeline(Constants.pipeline)
      .setScale(0.2)
    this.player2 = this.add
      .sprite(1000, 350, Constants.assets.images.player22)
      .setDepth(1)
      .setPipeline(Constants.pipeline)
      .setScale(0.18)
    this.addLight(0, 600, 800, 23 * 10, 10)
    this.addLight(800, 600, 800, 1 * 10, 10)
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: 150,
      ease: 'Power1',
      duration: 750,
      delay: 0,
      onComplete: function () {
        this.madeByTween.destroy
      }.bind(this),
    })
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      x: 700,
      ease: 'Power1',
      duration: 750,
      delay: 750,
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
