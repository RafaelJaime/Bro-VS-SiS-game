import { Player, PlayerObject } from '../components/Constants.js'

export class pruebaScene extends Phaser.Scene {
  constructor() {
    super({
      key: 'pruebaScene',
    })
  }
  init() {}
  preload() {
    this.load.setPath('./src/assets/')

    this.load.atlas(
      'matilde2',
      'images/atlas/rafael.png',
      'images/atlas/rafael.json'
    )
    this.load.atlas(
      'matilde',
      'images/atlas/matilde.png',
      'images/atlas/matilde.json'
    )
  }
  create() {
    this.add.rectangle(400, 300, 800, 600, 0xff0000).setAlpha(0.6)
    this.add.rectangle(400, -300, 800, 600, 0x0000ff).setAlpha(0.6)
    //  Our animations
    this.down()
    this.up()

    // with good physics
    this.sprite = this.physics.add
      .sprite(0, 300, 'matilde2')
      .setScale(0.1)
      .play('idle')

    this.cameras.main.startFollow(this.sprite)
    this.cameras.main.setZoom(0.5)

    this.circle1 = this.physics.add
      .image()
      .setBounce(1)
      .setDebugBodyColor(0xffff00)
    this.circle1.body.setSize(100, 170)

    /*var player = new Player(
      this,
      0,
      0,
      new PlayerObject('Paquito', 'red', 'matilde2', 'r_')
    )
    player.playIdle()
*/
    // Choque
    this.circle2 = this.physics.add
      .image(100, 300)
      .setBounce(1)
      .setDebugBodyColor(0x000000)
    this.circle2.body.setSize(100, 170)
    this.physics.add.collider(this.circle1, this.circle2, () => {})

    this.cursors = this.input.keyboard.createCursorKeys()
  }
  update() {
    // movement

    if (this.cursors.left.isDown) {
      this.circle1.setVelocity(-200, 0)
      if (this.sprite.anims.getName() !== 'run') {
        this.sprite.play('run')
      }
    } else if (this.cursors.right.isDown) {
      if (this.sprite.anims.getName() !== 'run') {
        this.sprite.play('run')
      }
      this.circle1.setVelocity(200, 0)
    } else if (this.cursors.up.isDown) {
      this.circle1.setVelocityY(-200, 0)
      this.sprite.play('jumpUp')
    } else if (this.cursors.down.isDown) {
      this.circle1.setVelocityY(200, 0)
      this.sprite.play('jumpDown')
    } else {
      this.circle1.setAngularVelocity(0)
      this.circle1.setVelocity(0, 0)
      if (this.sprite.anims.getName() !== 'idle') {
        this.sprite.play('idle')
      }
    }
    this.circle2.setVelocity(0)

    this.centerBodyOnBody(this.sprite.body, this.circle1.body)
  }

  down() {
    this.anims.create({
      key: 'guard',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 1,
        end: 2,
        zeroPad: 3,
      }),
      frameRate: 8,
      repeat: 2,
    })
    this.anims.create({
      key: 'idle',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 1,
        end: 2,
        zeroPad: 3,
      }),
      frameRate: 4,
      repeat: -1,
    })
    this.anims.create({
      key: 'shoot',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 5,
        end: 6,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'shootRepeat',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 5,
        end: 6,
        zeroPad: 3,
      }),
      frameRate: 4,
      repeat: -1,
    })
    this.anims.create({
      key: 'kick',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 7,
        end: 7,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'run',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 8,
        end: 9,
        zeroPad: 3,
      }),
      frameRate: 4,
      repeat: -1,
    })
    this.anims.create({
      key: 'jumpUp',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 10,
        end: 10,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'jumpDown',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 11,
        end: 11,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'jump',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 10,
        end: 11,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'die',
      frames: this.anims.generateFrameNames('matilde2', {
        prefix: 'r_',
        start: 12,
        end: 13,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    // Persons
    this.physics.add
      .sprite(300, 336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('idle')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(450, 336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('shootRepeat')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(600, 336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('run')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(450, 150)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('die')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(600, 150)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('kick')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(300, 150)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('jump')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)

    // down one
    this.player = this.physics.add
      .sprite(700, 100, 'matilde2', 'r_001')
      .setScale(0.1)
      .setCollideWorldBounds(true)
      .play('idle')
    this.player.body.setGravityY(1000).updateFromGameObject()

    this.input.on(
      'pointerdown',
      function () {
        this.player.play('jump', true).on('animationcomplete', () => {
          this.player.anims.play('idle', true)
        })
        /*if (lancelot.anims.getName() === 'idle') {
          lancelot.playAfterRepeat('guardStart')
          lancelot.chain(['guard', 'guardEnd', 'idle'])
        }*/
      },
      this
    )
  }
  up() {
    this.anims.create({
      key: 'guard',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 1,
        end: 2,
        zeroPad: 3,
      }),
      frameRate: 8,
      repeat: 2,
    })
    this.anims.create({
      key: 'matildeIdle',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 1,
        end: 2,
        zeroPad: 3,
      }),
      frameRate: 4,
      repeat: -1,
    })
    this.anims.create({
      key: 'matildeshoot',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 5,
        end: 6,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'matildeshootRepeat',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 5,
        end: 6,
        zeroPad: 3,
      }),
      frameRate: 4,
      repeat: -1,
    })
    this.anims.create({
      key: 'matildekick',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 7,
        end: 7,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'matilderun',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 8,
        end: 9,
        zeroPad: 3,
      }),
      frameRate: 4,
      repeat: -1,
    })
    this.anims.create({
      key: 'jumpUp',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 10,
        end: 10,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'jumpDown',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 11,
        end: 11,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'matildejump',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 10,
        end: 11,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    this.anims.create({
      key: 'matildedie',
      frames: this.anims.generateFrameNames('matilde', {
        prefix: 'm_',
        start: 12,
        end: 13,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
    // Persons
    this.physics.add
      .sprite(300, -336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('matildeIdle')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(450, -336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('matildeshootRepeat')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(600, -336)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('matilderun')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(450, -150)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('matildedie')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(600, -150)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('matildekick')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
    this.physics.add
      .sprite(300, -150)
      .setOrigin(0.5, 1)
      .setScale(8)
      .play('matildejump')
      .setScale(0.1)
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)

    // down one
    this.player2 = this.physics.add
      .sprite(200, -100, 'matilde', 'm_001')
      .setScale(0.1)
      .setCollideWorldBounds(true)
      .play('matildeIdle')

    this.input.on(
      'pointerdown',
      function () {
        this.player2.play('matildejump', true).on('animationcomplete', () => {
          this.player2.anims.play('matildeIdle', true)
        })
        /*if (lancelot.anims.getName() === 'idle') {
          lancelot.playAfterRepeat('guardStart')
          lancelot.chain(['guard', 'guardEnd', 'idle'])
        }*/
      },
      this
    )
  }

  centerBodyOnBody(a, b) {
    a.position.set(
      b.x + b.halfWidth - a.halfWidth,
      b.y + b.halfHeight - a.halfHeight
    )
  }
}
