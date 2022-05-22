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
    //this.add.image(400, 400, Constants.assets.images.center).setScale(0.8)
    // Texto central
    //this.texto()
    // Personajes laterales y animacion
    this.lights.enable().setAmbientColor(Constants.colors.darkGray)
    this.personajes()
    // Jugador 1 = Cuadrado y cuadraditos
    // this.add.rectangle(330, 330, 160, 160, Constants.colors.white).setDepth(4)
    this.generateRectangles(270, 266, 0x6666ff, 0x4242a3)

    // Jugador 2 = Cuadrado y cuadraditos
    // this.add.rectangle(520, 500, 160, 160, Constants.colors.white).setDepth(4)
    this.generateRectangles(440, 456, 0xff5733, 0xc70039)
  }

  generateRectangles(row, column, color1, color2) {
    let row1 = row + 40 * 0
    let row2 = row1 + 40 * 1
    let column1 = column + 32 * 0
    let column2 = column1 + 32 * 1
    let column3 = column1 + 32 * 2
    let column4 = column1 + 32 * 3
    let column5 = column1 + 32 * 4
    this.add.rectangle(column1, row1, 32, 40, color1).setDepth(4)
    this.add.rectangle(column2, row1, 32, 40, color2).setDepth(4)
    this.addText(
      column2 - 12,
      row1 - 10,
      'W',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    // https://www.htmlsymbols.xyz/arrow-symbols/sans-serif-arrows
    this.add.rectangle(column3, row1, 32, 40, color1).setDepth(4)
    this.add.rectangle(column4, row1, 32, 40, color2).setDepth(4)
    this.add.rectangle(column5, row1, 32, 40, color1).setDepth(4)
    this.add.rectangle(column1, row2, 32, 40, color2).setDepth(4)
    this.addText(
      column1 - 8,
      row2 - 10,
      'A',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.add.rectangle(column2, row2, 32, 40, color1).setDepth(4)
    this.add.rectangle(column3, row2, 32, 40, color2).setDepth(4)
    this.add.rectangle(column4, row2, 32, 40, color1).setDepth(4)
    this.add.rectangle(column5, row2, 32, 40, color2).setDepth(4)
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
