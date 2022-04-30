export class InstructionsScene extends Phaser.Scene {
  constructor() {
    super({
      key: "InstructionsScene",
    });
  }
  create() {
    this.botonVolver();
    this.fondos();
    // Imagen central
    this.add.image(400, 400, "centro").setScale(0.8);
    // Texto central
    this.texto();
    // Personajes laterales y animacion
    this.lights.enable().setAmbientColor(0xaaaaaa);
    this.personajes();
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
    botonVolver.on("pointerup", () => this.scene.start("MenuScene"));
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
  texto() {
    var columna1 = 330;
    var columna2 = 410;
    var columna3 = 460;
    var color = "#ff0000";
    this.add.text(280, this.game.renderer.heigh, "Instrucciones", {
      font: "bold 50px sans-serif",
      fill: "#000000",
    });
    this.add
      .text(columna1, 260, "Player 1", {
        font: "bold 25px sans-serif",
        fill: color,
      })
      .setDepth(2);
    this.add.text(columna3, 260, "Player 2", {
      font: "bold 25px sans-serif",
      fill: color,
    });
    this.add.text(columna2, 310, "Movimiento", {
      font: "bold 15px sans-serif",
      fill: color,
    });
    this.add.text(columna2, 390, "Habilidades", {
      font: "bold 15px sans-serif",
      fill: color,
    });
  }
  personajes() {
    this.player1 = this.add
      .sprite(-100, 320, "player12")
      .setDepth(1)
      .setPipeline("Light2D")
      .setScale(0.2);
    this.light = this.lights.addLight(
      0,
      600,
      800,
      Phaser.Display.Color.HSVColorWheel()[23 * 10].color,
      10
    );
    this.player2 = this.add
      .sprite(1000, 350, "player22")
      .setDepth(1)
      .setPipeline("Light2D")
      .setScale(0.18);
    this.light = this.lights.addLight(
      800,
      600,
      800,
      Phaser.Display.Color.HSVColorWheel()[1 * 10].color,
      10
    );
    this.madeByTween = this.tweens.add({
      targets: this.player1,
      x: 150,
      ease: "Power1",
      duration: 750,
      delay: 0,
      onComplete: function () {
        this.madeByTween.destroy;
      }.bind(this),
    });
    this.madeByTween = this.tweens.add({
      targets: this.player2,
      x: 700,
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
