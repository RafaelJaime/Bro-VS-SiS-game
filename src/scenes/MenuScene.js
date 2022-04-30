export class MenuScene extends Phaser.Scene {
  constructor() {
    super({
      key: "MenuScene",
    });
  }
  init() {}
  create() {
    this.lights.enable().setAmbientColor(0x555555);
    this.music = this.sound.add("title_music", {
      loop: true,
      volume: 0.3,
    });
    this.music.play();
    this.fondos();
    this.textos();
    this.botones();
    this.players();
  }
  fondos() {
    this.background2 = this.add
      .tileSprite(0, 0, 2000, 1000, "title2")
      .setOrigin(0, 0)
      .setScale(0.68)
      .setPipeline("Light2D");
    this.background = this.add
      .tileSprite(0, 0, 2000, 1000, "title")
      .setOrigin(0, 0)
      .setScale(0.68)
      .setPipeline("Light2D");
  }
  textos() {
    this.add
      .image(400, 130, "portada")
      .setScale(0.13)
      .setDepth(1)
      .setPipeline("Light2D")
      .setInteractive();
    this.light = this.lights.addLight(
      430,
      130,
      200,
      Phaser.Display.Color.HSVColorWheel()[240].color,
      1
    );
    this.add
      .text(700, 570, "v0.5", { font: "bold 25px ", fill: "#000000" })
      .setDepth(2);
  }
  botones() {
    this.buttonSound = this.sound.add("boton", {
      loop: false,
      volume: 0.3,
    });
    var boton1 = this.add
      .image(400, 300, "boton1")
      .setDepth(1.5)
      .setScale(0.1)
      .setPipeline("Light2D")
      .setInteractive();
    var boton2 = this.add
      .image(430, 368, "boton2")
      .setDepth(1.4)
      .setScale(0.1)
      .setPipeline("Light2D")
      .setInteractive();
    var boton3 = this.add
      .image(378, 443, "boton3")
      .setDepth(1.4)
      .setScale(0.1)
      .setPipeline("Light2D")
      .setInteractive();
    boton1.on("pointerout", () => {
      boton1.clearTint();
    });
    boton1.on("pointerover", () => {
      this.buttonSound.play();
      boton1.tint = 0xffffff00;
    });
    boton1.on("pointerup", () => {
      this.music.stop();
      this.scene.start("GameScene");
    });
    boton2.on("pointerout", () => {
      boton2.clearTint();
    });
    boton2.on("pointerover", () => {
      this.buttonSound.play();
      boton2.tint = 0xffffff00;
    });
    boton2.on("pointerup", () => {
      this.music.stop();
      this.scene.start("InstructionsScene");
    });
    boton3.on("pointerout", () => {
      boton3.clearTint();
    });
    boton3.on("pointerover", () => {
      this.buttonSound.play();
      boton3.tint = 0xffffff00;
    });
    boton3.on("pointerup", () => {
      this.music.stop();
      this.scene.start("CreditScene");
    });
  }
  players() {
    // P1
    this.player1 = this.add
      .sprite(500, 300, "player11")
      .setDepth(1)
      .setScale(0.18)
      .setPipeline("Light2D");
    this.light = this.lights.addLight(
      1000,
      600,
      800,
      Phaser.Display.Color.HSVColorWheel()[20 * 10].color,
      20
    );
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: 700,
      ease: "Power1",
      duration: 750,
      delay: 0,
      onComplete: function () {
        this.madeByTween.destroy;
      }.bind(this),
    });

    // P2
    this.player2 = this.add
      .sprite(300, 350, "player21")
      .setDepth(1)
      .setPipeline("Light2D")
      .setScale(0.18);
    this.light = this.lights.addLight(
      0,
      600,
      2000,
      Phaser.Display.Color.HSVColorWheel()[1 * 10].color,
      5
    );
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      x: 100,
      ease: "Power1",
      duration: 750,
      delay: 750,
      onComplete: function () {}.bind(this),
    });
  }
  update() {
    this.background2.tilePositionX -= 1;
  }
}
