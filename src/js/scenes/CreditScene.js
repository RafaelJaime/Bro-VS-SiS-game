import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'

export class CreditScene extends BaseScene {
  constructor() {
    super(Constants.scenes.credit)
  }
  create() {
    // this.creditMusic = this.sound.add('creditMusic', {loop: true,volume: 0.3,})
    // this.creditMusic.play()
    this.addReturnButton()
    this.addTexts()
    this.addAnimations()
  }

  addTexts() {
    this.creditsText = this.add.text(0, 0, 'Créditos', {
      fontSize: Constants.fonts.size32,
      fill: Constants.colors.white,
    })
    this.centerText1 = this.add.text(
      0,
      0,
      'Desarrollado por: Rafael Jaime Moreno',
      { fontSize: Constants.fonts.size26, fill: Constants.colors.white }
    )
    this.centerText2 = this.add.text(0, 0, 'Arte por: Matilde Jaime Moreno', {
      fontSize: Constants.fonts.size26,
      fill: Constants.colors.white,
    })
    this.centerText3 = this.add.text(0, 0, 'Música libre de copyright', {
      fontSize: Constants.fonts.size26,
      fill: Constants.colors.white,
    })
    this.madeByText = this.add.text(0, 0, 'Special thanks to you for playing', {
      fontSize: Constants.fonts.size26,
      fill: Constants.colors.white,
    })

    var width = this.cameras.main.width
    var height = this.cameras.main.height
    this.zone = this.add.zone(width / 2, height / 2, width, height)

    Phaser.Display.Align.In.Center(this.creditsText, this.zone)
    Phaser.Display.Align.In.Center(this.centerText1, this.zone)
    Phaser.Display.Align.In.Center(this.centerText2, this.zone)
    Phaser.Display.Align.In.Center(this.centerText3, this.zone)
    Phaser.Display.Align.In.Center(this.madeByText, this.zone)

    this.centerText1.setY(1000)
    this.centerText2.setY(2000)
    this.centerText3.setY(3000)
    this.madeByText.setY(4000)
  }

  addAnimations() {
    this.creditsTween = this.tweens.add({
      targets: [this.creditsText],
      y: -100,
      ease: 'Power1',
      duration: 3000,
      delay: 500,
      onComplete: function () {
        this.destroy
      },
    })
    this.creditsTween = this.tweens.add({
      targets: [this.centerText1, this.centerText2, this.centerText3],
      y: -300,
      ease: 'Power1',
      duration: 6000,
      delay: 1500,
      onComplete: function () {
        this.destroy
      },
    })
    this.creditsTween = this.tweens.add({
      targets: [this.centerText2],
      y: -300,
      ease: 'Power1',
      duration: 9000,
      delay: 1500,
      onComplete: function () {
        this.destroy
      },
    })
    this.creditsTween = this.tweens.add({
      targets: [this.centerText3],
      y: -300,
      ease: 'Power1',
      duration: 12000,
      delay: 1500,
      onComplete: function () {
        this.destroy
      },
    })
    this.madeByTween = this.tweens.add({
      targets: this.madeByText,
      y: 100,
      ease: 'Power1',
      duration: 9000,
      delay: 4500,
      completeDelay: 500,
      onComplete: function () {
        this.madeByTween.destroy
        this.creditMusic.stop()
        this.scene.start(Constants.scenes.menu)
      }.bind(this),
    })
  }
}
