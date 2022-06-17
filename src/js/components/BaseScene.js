import { Constants } from '../components/Constants.js'

export class BaseScene extends Phaser.Scene {
  constructor(key) {
    super({
      key: key,
    })
  }
  init() {}
  preload() {}
  create() {}
  update() {
    if (this.parallaxBackgroundIsActive) {
      this.parallaxBackground.tilePositionX -= 1
    }
  }

  preloadAssets() {
    this.load.setPath('./src/assets/')
    this.menuCreditInstructionsAssets()
    this.gameAssets()
  }

  menuCreditInstructionsAssets() {
    this.load.image(Constants.assets.images.title, 'images/fondo_cocina.png')
    this.load.image(Constants.assets.images.title2, 'images/fondo_nubes.png')
    this.load.image(Constants.assets.images.title3, 'images/cocina.png')
    this.load.image(Constants.assets.images.front, 'images/imagen_titulo.png')
    this.load.image(Constants.assets.images.button1, 'images/button1.png')
    this.load.image(Constants.assets.images.button2, 'images/button2.png')
    this.load.image(Constants.assets.images.button3, 'images/button3.png')
    this.load.image(Constants.assets.images.button5, 'images/button5.png')
    this.load.image(
      Constants.assets.images.player21,
      'images/Ilustracion_m1.png'
    )
    this.load.image(
      Constants.assets.images.player11,
      'images/Ilustracion_r1.png'
    )
    this.load.image(
      Constants.assets.images.player22,
      'images/Ilustracion_m2.png'
    )
    this.load.image(
      Constants.assets.images.player12,
      'images/Ilustracion_r2.png'
    )
    this.load.image(Constants.assets.images.volver, 'images/button4.png')
    this.load.audio(Constants.assets.audios.title, 'audios/The Mystic.mp3')
    this.load.audio(Constants.assets.audios.credit, 'audios/creditMusic.mp3')
    this.load.audio(Constants.assets.audios.button, 'sounds/button.mp3')
  }

  gameAssets() {
    this.load.audio(Constants.assets.audios.bomb, 'audios/BOMBA.mp3')
    this.load.image(
      Constants.assets.images.platform,
      'images/plataformacuadrados.png'
    )
    this.load.image(Constants.assets.images.redBar, 'images/red-bar.png')
    this.load.spritesheet(Constants.assets.images.rafael, 'images/rafael.png', {
      frameWidth: 1492,
      frameHeight: 1724,
    })
    this.load.spritesheet(
      Constants.assets.images.matilde,
      'images/matilde.png',
      {
        frameWidth: 1492,
        frameHeight: 1724,
      }
    )
    this.load.image(Constants.assets.images.bluebeam, 'images/bluebeam.png')
    this.load.image(Constants.assets.images.orangebeam, 'images/orangebeam.png')
  }

  loadProgressBar() {
    var progressBar = this.add.graphics()
    var progressBox = this.add.graphics()
    progressBox
      .fillStyle(Constants.colors.gray, 0.8)
      .fillRect(
        Constants.game.width / 2 - 160,
        Constants.game.height / 2 - 30,
        320,
        50
      )
    this.load.on(Constants.events.progress, function (value) {
      progressBar
        .clear()
        .fillStyle(Constants.colors.black, 1)
        .fillRect(
          Constants.game.width / 2 - 150,
          Constants.game.height / 2 - 20,
          300 * value,
          30
        )
    })
    this.load.on(Constants.events.complete, function () {
      progressBar.destroy()
      progressBox.destroy()
    })
  }

  setBackground(image, scale) {
    this.add
      .tileSprite(0, 0, 2000, 1000, image)
      .setOrigin(0, 0)
      .setScale(scale)
      .setPipeline(Constants.pipeline)
  }

  setParallaxBackground(image, scale) {
    return (this.parallaxBackground = this.add
      .tileSprite(0, 0, 2000, 1000, image)
      .setOrigin(0, 0)
      .setScale(scale)
      .setPipeline(Constants.pipeline))
  }

  addButton(x, y, image, depth, stopMusic, navigate = null) {
    this.buttonSound = this.sound.add(Constants.assets.audios.button, {
      loop: false,
      volume: 0.3,
    })
    var boton1 = this.add
      .image(x, y, image)
      .setDepth(depth)
      .setScale(0.1)
      .setPipeline(Constants.pipeline)
      .setInteractive()
    boton1.on(Constants.events.pointer.out, () => {
      boton1.clearTint()
    })
    boton1.on(Constants.events.pointer.over, () => {
      this.buttonSound.play()
      boton1.tint = Constants.colors.yellow
    })
    boton1.on(Constants.events.pointer.up, () => {
      if (stopMusic) {
        this.stopMusic()
      }
      if (navigate != null) {
        this.scene.start(navigate)
      }
    })
  }

  addImage(x, y, image, depth = null) {
    this.add
      .image(x, y, image)
      .setScale(0.13)
      .setDepth(depth)
      .setPipeline(Constants.pipeline)
      .setInteractive()
  }

  addText(x, y, text, font, color = Constants.colors.black, depth = 2) {
    return this.add
      .text(x, y, text, {
        font: font,
        fill: color,
      })
      .setDepth(depth)
  }

  setDefaultBackground() {
    this.parallaxBackground = this.setParallaxBackground(
      Constants.assets.images.title2,
      0.68
    )
    this.parallaxBackgroundIsActive = true
    this.setBackground(Constants.assets.images.title, 0.68)
    this.setBackground(Constants.assets.images.title3, 0.68)
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

  playMusic(music, volume, loop = false) {
    this.music = this.sound.add(music, {
      loop: loop,
      volume: volume,
    })
    this.music.play()
  }

  stopMusic() {
    this.music.stop()
  }
}
