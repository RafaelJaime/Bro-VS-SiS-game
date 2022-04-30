export class CreditScene extends Phaser.Scene {
  constructor() {
    super({
      key: "CreditScene",
    });
  }
  create() {
    this.creditMusic = this.sound.add("creditMusic", {
      loop: true,
      volume: 0.3,
    });
    this.creditMusic.play();
    this.botonVolver();
    this.creditsText = this.add.text(0, 0, "Créditos", {
      fontSize: "32px",
      fill: "#fff",
    });
    this.centerText1 = this.add.text(
      0,
      0,
      "Desarrollado por: Rafael Jaime Moreno",
      { fontSize: "26px", fill: "#fff" }
    );
    this.centerText2 = this.add.text(0, 0, "Arte por: Matilde Jaime Moreno", {
      fontSize: "26px",
      fill: "#fff",
    });
    this.centerText3 = this.add.text(0, 0, "Música libre de copyright", {
      fontSize: "26px",
      fill: "#fff",
    });
    this.madeByText = this.add.text(0, 0, "Special thanks to you for playing", {
      fontSize: "26px",
      fill: "#fff",
    });
    var width = this.cameras.main.width;
    var height = this.cameras.main.height;
    this.zone = this.add.zone(width / 2, height / 2, width, height);

    Phaser.Display.Align.In.Center(this.creditsText, this.zone);
    Phaser.Display.Align.In.Center(this.centerText1, this.zone);
    Phaser.Display.Align.In.Center(this.centerText2, this.zone);
    Phaser.Display.Align.In.Center(this.centerText3, this.zone);
    Phaser.Display.Align.In.Center(this.madeByText, this.zone);

    this.centerText1.setY(1000);
    this.centerText2.setY(2000);
    this.centerText3.setY(3000);
    this.madeByText.setY(4000);

    this.creditsTween = this.tweens.add({
      targets: [this.creditsText],
      y: -100,
      ease: "Power1",
      duration: 3000,
      delay: 500,
      onComplete: function () {
        this.destroy;
      },
    });
    this.creditsTween = this.tweens.add({
      targets: [this.centerText1, this.centerText2, this.centerText3],
      y: -300,
      ease: "Power1",
      duration: 6000,
      delay: 1500,
      onComplete: function () {
        this.destroy;
      },
    });
    this.creditsTween = this.tweens.add({
      targets: [this.centerText2],
      y: -300,
      ease: "Power1",
      duration: 9000,
      delay: 1500,
      onComplete: function () {
        this.destroy;
      },
    });
    this.creditsTween = this.tweens.add({
      targets: [this.centerText3],
      y: -300,
      ease: "Power1",
      duration: 12000,
      delay: 1500,
      onComplete: function () {
        this.destroy;
      },
    });
    this.madeByTween = this.tweens.add({
      targets: this.madeByText,
      y: 100,
      ease: "Power1",
      duration: 9000,
      delay: 4500,
      completeDelay: 500,
      onComplete: function () {
        this.madeByTween.destroy;
        this.creditMusic.stop();
        this.scene.start("MenuScene");
      }.bind(this),
    });
  }
  botonVolver() {
    var botonVolver = this.add
      .image(70, 560, "volver")
      .setDepth(2)
      .setScale(0.04)
      .setInteractive();
    this.buttonSound = this.sound.add("boton", {
      loop: false,
      volume: 0.3,
    });
    botonVolver.on("pointerout", () => {
      botonVolver.clearTint();
    });
    botonVolver.on("pointerover", () => {
      this.buttonSound.play();
      botonVolver.tint = 0xffffff00;
    });
    botonVolver.on("pointerup", () => {
      this.creditMusic.stop();
      this.scene.start("MenuScene");
    });
  }
}
