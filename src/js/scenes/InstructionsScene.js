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
    this.addText(
      280,
      0,
      Constants.texts.instructions,
      Constants.fonts.secondaryBold50,
      Constants.colors.black,
      5
    )
    // Jugador 1 = Cuadrado y cuadraditos
    // this.add.rectangle(330, 330, 160, 160, Constants.colors.white).setDepth(4)
    this.generateRectangles(
      270,
      266,
      Constants.colors.lightBlue,
      Constants.colors.darkBlue
    )
    this.addP1Text()

    // Jugador 2 = Cuadrado y cuadraditos
    // this.add.rectangle(520, 500, 160, 160, Constants.colors.white).setDepth(4)
    this.generateRectangles(
      440,
      456,
      Constants.colors.lightRed,
      Constants.colors.darkRed
    )
    this.addP2Text()
  }

  generateRectangles(
    row,
    column,
    color1,
    color2,
    width = 32,
    height = 40,
    depth = 0
  ) {
    let row1 = row + height * 0
    let row2 = row1 + height * 1
    let column1 = column + width * 0
    let column2 = column1 + width * 1
    let column3 = column1 + width * 2
    let column4 = column1 + width * 3
    let column5 = column1 + width * 4
    this.add.rectangle(column1, row1, width, height, color1).setDepth(depth)
    this.add.rectangle(column2, row1, width, height, color2).setDepth(depth)
    this.add.rectangle(column3, row1, width, height, color1).setDepth(depth)
    this.add.rectangle(column4, row1, width, height, color2).setDepth(depth)
    this.add.rectangle(column5, row1, width, height, color1).setDepth(depth)
    this.add.rectangle(column1, row2, width, height, color2).setDepth(depth)
    this.add.rectangle(column2, row2, width, height, color1).setDepth(depth)
    this.add.rectangle(column3, row2, width, height, color2).setDepth(depth)
    this.add.rectangle(column4, row2, width, height, color1).setDepth(depth)
    this.add.rectangle(column5, row2, width, height, color2).setDepth(depth)
  }

  addP1Text() {
    this.addText(
      290,
      260,
      '🡑',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      386,
      260,
      '1',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      258,
      298,
      '🡐',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      290,
      298,
      '🡓',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      322,
      298,
      '🡒',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      386,
      298,
      '2',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
  }

  addP2Text() {
    // https://www.htmlsymbols.xyz/arrow-symbols/sans-serif-arrows
    this.addText(
      476,
      430,
      'W',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      578,
      430,
      'J',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      448,
      468,
      'A',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      480,
      468,
      'S',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      512,
      468,
      'D',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
    this.addText(
      576,
      468,
      'K',
      Constants.fonts.secondaryBold25,
      Constants.colors.black,
      5
    )
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
