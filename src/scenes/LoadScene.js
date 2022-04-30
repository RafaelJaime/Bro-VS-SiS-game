export class LoadScene extends Phaser.Scene {
  constructor() {
    super({
      key: "LoadScene",
    });
  }
  preload() {
    // Menu, instructions, credit
    this.load.setPath('./src/assets/');
    this.load.image("title", "images/fondo_cocina.png");
    this.load.image("title2", "images/fondo_nubes.png");
    this.load.image("portada", "images/imagen_titulo.png");
    this.load.image("boton1", "images/boton1.png");
    this.load.image("boton2", "images/boton2.png");
    this.load.image("boton3", "images/boton3.png");
    this.load.image("boton5", "images/boton5.png");
    this.load.image("player21", "images/Ilustracion_m1.png");
    this.load.image("player11", "images/Ilustracion_r1.png");
    this.load.image("player22", "images/Ilustracion_m2.png");
    this.load.image("player12", "images/Ilustracion_r2.png");
    this.load.image("volver", "images/boton4.png");
    this.load.image("wasd1", "images/wasd1.png");
    this.load.image("wasd2", "images/wasd2.png");
    this.load.image("jkl1", "images/jkl.png");
    this.load.image("jkl2", "images/jkl2.png");
    this.load.image("centro", "images/caja-pizza.png");
    this.load.audio("title_music", "audios/The Mystic.mp3");
    this.load.audio("creditMusic", "audios/audioCreditos.mp3");
    this.load.audio("boton", "sounds/boton.mp3");
    // Game
    this.load.audio("bomba", "audios/BOMBA.mp3");
    this.load.image("plataforma", "images/plataformacuadrados.png");
    this.load.image("green-bar", "images/green-bar.png");
    this.load.image("red-bar", "images/red-bar.png");
    this.load.spritesheet("rafael", "images/rafael.png", {
      frameWidth: 1492,
      frameHeight: 1724,
    });
    this.load.spritesheet("matilde", "images/matilde.png", {
      frameWidth: 1492,
      frameHeight: 1724,
    });
    this.load.image("bluebeam", "images/bluebeam.png");
    this.load.image("orangebeam", "images/orangebeam.png");
    // Pantalla de carga
    var progressBar = this.add.graphics();
    var progressBox = this.add.graphics();
    var loadingText = this.make.text({
      x: this.width / 2,
      y: this.height / 2 - 50,
      text: "Loading...",
      style: {
        font: "20px monospace",
        fill: "#ffffff",
      },
    });
    var percentText = this.make.text({
      x: this.width / 2,
      y: this.height / 2 - 5,
      text: "0%",
      style: {
        font: "18px monospace",
        fill: "#ffffff",
      },
    });
    percentText.setOrigin(0.5, 0.5);
    loadingText.setOrigin(0.5, 0.5);
    progressBox.fillStyle(0x222222, 0.8).fillRect(240, 270, 320, 50);
    this.load.on("progress", function (value) {
      progressBar
        .clear()
        .fillStyle(0xffffff, 1)
        .fillRect(250, 280, 300 * value, 30);
      percentText.setText(parseInt(value * 100) + "%");
    });
    this.load.on("complete", function () {
      loadingText.destroy();
      progressBar.destroy();
      progressBox.destroy();
    });
  }
  create() {
    this.scene.start("MenuScene");
  }
  update() {}
}