export class pruebaScene extends Phaser.Scene {
  constructor() {
    super({
      key: 'pruebaScene',
    })
  }
  init() {}
  preload() {
    this.load.setPath('./src/assets/')
    this.load.atlas('knight', 'images/knight.png', 'images/knight.json')
  }
  create() {
    this.add.rectangle(400, 300, 800, 600, 0xff0000)
    //  Our animations
    this.anims.create({
      key: 'guardStart',
      frames: this.anims.generateFrameNames('knight', {
        prefix: 'guard_start/frame',
        start: 0,
        end: 3,
        zeroPad: 4,
      }),
      frameRate: 8,
    })

    this.anims.create({
      key: 'guard',
      frames: this.anims.generateFrameNames('knight', {
        prefix: 'guard/frame',
        start: 0,
        end: 5,
        zeroPad: 4,
      }),
      frameRate: 8,
      repeat: 2,
    })

    this.anims.create({
      key: 'guardEnd',
      frames: this.anims.generateFrameNames('knight', {
        prefix: 'guard_end/frame',
        start: 0,
        end: 3,
        zeroPad: 4,
      }),
      frameRate: 8,
    })

    this.anims.create({
      key: 'idle',
      frames: this.anims.generateFrameNames('knight', {
        prefix: 'idle/frame',
        start: 0,
        end: 5,
        zeroPad: 4,
      }),
      frameRate: 8,
      repeat: -1,
    })

    var lancelot = this.add.sprite(500, 536)

    lancelot.setOrigin(0.5, 1)
    lancelot.setScale(8)
    lancelot.play('idle')

    lancelot.on(
      Phaser.Animations.Events.SPRITE_ANIMATION_START,
      function (anim) {
        console.log('Playing ' + anim.key)
      }
    )

    this.input.on(
      'pointerdown',
      function () {
        if (lancelot.anims.getName() === 'idle') {
          lancelot.playAfterRepeat('guardStart')
          lancelot.chain(['guard', 'guardEnd', 'idle'])
        }
      },
      this
    )
  }
  update() {}
}
