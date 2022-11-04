export class Player extends Phaser.GameObjects.Sprite {
  static animation = class animation {
    static face = 'face'
  }

  constructor(scene, x, y, texture, play, playerObject) {
    super(scene, x, y, texture, 'r_001')
    this.scene = scene
    scene.add.existing(this)
    this.player = playerObject
    if (play) {
      this.setScale(0.1)
      this.scene.physics.world.enable(this)
    }

    this.createAnimations()

    if (this.body != null) {
      this.body.setSize(900, 1680)
      this.body.setOffset(740, 1000)
      this.body.setBounce(0.2)
    }

    this.hitDelay = false
    this.jumping = false
  }

  update() {}

  moveL(flip = false) {
    this.flipX = flip
    this.moving = true
    this.body.setVelocityX(-300)
  }

  moveR(flip = false) {
    this.jugador2.anims.play('normal2')
    this.flipX = flip
    this.moving = true
    this.body.setVelocityX(300)
  }

  stay(flip = false) {
    this.flipX = flip
    this.body.setAngularVelocity(0)
    this.body.setVelocityX(0)
    this.moving = null
  }

  jump(flip = false) {
    this.flipX = flip
    this.body.setVelocityY(-600)
    this.moving = null
  }

  createAnimations() {
    this.anims.create({
      key: Player.animation.face,
      frames: this.anims.generateFrameNames(this.player.image, {
        prefix: this.player.prefix,
        suffix: this.player.suffix,
        start: 14,
        end: 14,
        zeroPad: 3,
      }),
      frameRate: 4,
    })
  }
}
