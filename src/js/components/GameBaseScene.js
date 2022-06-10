import { Constants } from '../components/Constants.js'

export class GameBaseScene extends Phaser.Scene {
  constructor(key) {
    super({
      key: key,
    })
  }
  init() {}

  preload() {}

  create() {
    this.parallaxBackgrounds = this.add.group()
    this.returnButton()
    this.retryButton()
    this.addDetaultParallaxBackground()
  }

  update() {
    for (let i = 0; i < this.parallaxBackgrounds.getLength(); i++) {
      const parallaxBackground = this.parallaxBackgrounds.getChildren()[i]
      parallaxBackground.tilePositionX += 0.5
    }
  }

  // Public methods

  showReturnButton() {
    this.botonVolver.visible = true
  }

  showRetryButton() {
    this.retry.visible = true
  }

  addParallaxBackground(background) {
    this.parallaxBackgrounds.add(background)
  }

  // Private methods

  returnButton() {
    this.botonVolver = this.add
      .image(70, 560, Constants.assets.images.volver)
      .setDepth(2)
      .setScale(0.04)
      .setScrollFactor(0)
      .setInteractive()
    this.botonVolver.setVisible(false)
    this.botonVolver.on(Constants.events.pointer.up, () =>
      this.scene.start(Constants.scenes.menu)
    )
    this.botonVolver.on(Constants.events.pointer.out, () => {
      this.botonVolver.clearTint()
    })
    this.botonVolver.on(Constants.events.pointer.over, () => {
      this.buttonSound.play()
      this.botonVolver.tint = Constants.colors.yellow
    })
    this.botonVolver.visible = false
  }

  retryButton() {
    this.retry = this.add
      .image(400, 350, Constants.assets.images.button5)
      .setDepth(2)
      .setScale(0.04)
      .setScrollFactor(0)
      .setInteractive()
    this.retry.setVisible(false)
    this.retry.on(Constants.events.pointer.up, () =>
      this.scene.start(Constants.scenes.game)
    )
    this.retry.on(Constants.events.pointer.out, () => {
      this.retry.clearTint()
    })
    this.retry.on(Constants.events.pointer.over, () => {
      this.buttonSound.play()
      this.retry.tint = Constants.colors.yellow
    })
  }

  addDetaultParallaxBackground() {
    this.addParallaxBackground(
      this.add
        .tileSprite(0, 0, 2000, 1000, 'title2')
        .setOrigin(0, 0)
        .setScale(0.68)
    )
  }
}
