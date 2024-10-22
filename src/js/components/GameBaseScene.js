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
    this.healthBars = this.add.group()
    this.returnButton()
    this.retryButton()
    this.addDetaultParallaxBackground()
  }

  update() {
    this.updateParallaxBackgrounds()
    if (this.timerIsActive) {
      if (this.timedEvent.getRepeatCount() > 9) {
        this.timerText.setText(this.timedEvent.getRepeatCount())
      } else {
        if (!this.delayChanged) {
          this.timedEvent.delay =
            Phaser.Math.Between(
              0,
              Constants.gameModes.twoVtwo.finalProbability
            ) == 0
              ? Constants.gameModes.twoVtwo.timeDelayFinalFast
              : Constants.gameModes.twoVtwo.timeDelayFinalSlow
          this.delayChanged = true
        }
        this.timerText.setText('0' + this.timedEvent.getRepeatCount())
      }
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

  updateParallaxBackgrounds() {
    for (let i = 0; i < this.parallaxBackgrounds.getLength(); i++) {
      const parallaxBackground = this.parallaxBackgrounds.getChildren()[i]
      parallaxBackground.tilePositionX += 0.5
    }
  }

  timer(
    repeat = Constants.gameModes.twoVtwo.time,
    delay = Constants.gameModes.twoVtwo.timeDelay
  ) {
    this.add
      .rectangle(
        Constants.game.width / 2,
        40,
        120,
        80,
        Constants.colors.blackHEX
      )
      .setAlpha(0.3)
      .setStrokeStyle(10, Constants.colors.blackHEX, 0.5)
    this.add
      .rectangle(Constants.game.width / 2, 40, 120, 80, Constants.colors.white)
      .setAlpha(0.3)
    this.timerText = this.add
      .text(Constants.game.width / 2 - 20, 15, '', {
        fontSize: '40px bold',
        fill: 'rgba(100,100,100, 1)',
      })
      .setScrollFactor(0)
      .setStroke('rgba(100,100,100, 1)', 3)
    this.timedEvent = this.time.addEvent({
      delay: delay,
      callback: this.onEvent,
      callbackScope: this,
      repeat: repeat,
    })
    this.timerIsActive = true
  }

  addReturnButton(stopMusic = false) {
    var botonVolver = this.add
      .image(70, Constants.game.height - 40, 'volver')
      .setDepth(2)
      .setScale(0.04)
      .setInteractive()
    this.buttonSound = this.sound.add(Constants.assets.audios.button, {
      loop: false,
      volume: 0.3,
    })
    botonVolver.on(Constants.events.pointer.out, () => {
      botonVolver.clearTint()
    })
    botonVolver.on(Constants.events.pointer.over, () => {
      this.buttonSound.play()
      botonVolver.tint = Constants.colors.yellow
    })
    botonVolver.on(Constants.events.pointer.up, () => {
      if (stopMusic) {
        this.stopMusic()
      }
      this.scene.start(Constants.scenes.menu)
    })
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
        .tileSprite(0, 0, 2000, 1000, Constants.assets.images.title2)
        .setOrigin(0, 0)
        .setScale(0.68)
    )
  }

  setHealthBar(text = 'Player', x, y, color) {
    this.add
      .rectangle(x, y - 10, 340, 80, color)
      .setAlpha(0.3)
      .setStrokeStyle(10, color, 0.5)
    this.add.rectangle(x, y - 10, 340, 80, Constants.colors.white).setAlpha(0.3)
    this.backgroundHealthBar = this.add
      .image(x, y, Constants.assets.images.redBar)
      .setScrollFactor(0)
      .setScale(1.5)
    this.healthBars.add(this.add.rectangle(x, y, 300, 30, color))
    this.healthLabel = this.add
      .text(x - 150, y - 40, text, {
        fontSize: '20px',
        fill: Constants.colors.black,
      })
      .setScrollFactor(0)
  }

  udpateHealthBar(position, take = 10, of = 100) {
    this.healthBars.getChildren()[position].width -= (300 * take) / of
  }
}
