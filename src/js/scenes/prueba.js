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

    this.load.atlas(
      'matilde2',
      'images/atlas2/rafael.png',
      'images/atlas2/rafael.json'
    )
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
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 1,
        end: 3,
        zeroPad: 3,
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
      frames: [
        { frame: 'r_001', key: 'matilde2' },
        { frame: 'r_002', key: 'matilde2' },
        { frame: 'r_003', key: 'matilde2' },
        { frame: 'r_004', key: 'matilde2' },
      ],
      /*frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 1,
        end: 13,
        zeroPad: 3,
      }),*/
      frameRate: 4,
      repeat: -1,
    })
    console.log(
      this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 1,
        end: 3,
        zeroPad: 3,
      })
    )
    console.log(Phaser.VERSION)
    var lancelot = this.physics.add
      .sprite(300, 336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('idle')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)

    lancelot.on(
      Phaser.Animations.Events.SPRITE_ANIMATION_START,
      function (anim) {
        console.log('Playing ' + anim.key)
      }
    )

    /*this.input.on(
      'pointerdown',
      function () {
        if (lancelot.anims.getName() === 'idle') {
          lancelot.playAfterRepeat('guardStart')
          lancelot.chain(['guard', 'guardEnd', 'idle'])
        }
      },
      this
    )*/
  }
  update() {}
}
