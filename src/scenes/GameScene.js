export class GameScene extends Phaser.Scene {
  constructor() {
    super({
      key: "GameScene",
    });
  }
  create() {
    this.cursors = this.input.keyboard.createCursorKeys();
    this.keyboard = this.input.keyboard.addKeys(
      "W,A,S,D,J,K, " + Phaser.Input.Keyboard.KeyCodes.SPACE
    );
    this.fondos();
    this.flat = this.physics.add.staticImage(600, 600, "plataforma");
    this.vida();
    this.contador();
    this.musica();
    this.botones();

    this.player1Method();
    this.player2Method();

    // Camera
    this.cameraFollow = this.add.text(400, 20, "", {
      fontSize: "100px",
      fill: "#000",
    });
    this.myCam = this.cameras.main;
    this.myCam.setBounds(0, 0, 1400, 0);
    this.myCam.startFollow(this.cameraFollow);
  }
  vida() {
    this.backgroundBar = this.add.image(110, 35, "red-bar").setScrollFactor(0);
    this.healthBar1 = this.add.image(110, 35, "green-bar").setScrollFactor(0);
    this.healthBar1.tint = 0xffa500;
    this.backgroundBar2 = this.add.image(690, 35, "red-bar").setScrollFactor(0);
    this.healthBar2 = this.add.image(690, 35, "green-bar").setScrollFactor(0);
    this.healthBar2.tint = 0x0000ff;
    this.healthLabel = this.add
      .text(10, 5, "Player 1", {
        fontSize: "12px",
        fill: "#000000",
      })
      .setScrollFactor(0)
      .setShadow(1, 1, "rgba(0,0,0,0.5)", 1);
    this.healthLabel = this.add
      .text(590, 5, "Player 2", {
        fontSize: "12px",
        fill: "#000000",
      })
      .setScrollFactor(0)
      .setShadow(1, 1, "rgba(0,0,0,0.5)", 1);
    this.text2 = this.add
      .text(110, 200, "", {
        fontSize: "30px",
        fill: "#000000",
      })
      .setScrollFactor(0)
      .setShadow(1, 1, "rgba(0,0,0,0.5)", 1);
  }
  contador() {
    this.text = this.add
      .text(390, 5, "", {
        fontSize: "40px",
        fill: "#000000",
      })
      .setScrollFactor(0)
      .setShadow(1, 1, "rgba(0,0,0,0.5)", 1);
    this.timedEvent = this.time.addEvent({
      delay: 1000,
      callback: this.onEvent,
      callbackScope: this,
      repeat: 99,
    });
  }
  fondos() {
    this.background2 = this.add
      .tileSprite(0, 0, 2000, 1000, "title2")
      .setOrigin(0, 0)
      .setScale(0.68);
    this.background = this.add
      .tileSprite(0, 0, 3000, 1000, "title")
      .setOrigin(0, 0)
      .setScale(0.68);
  }
  musica() {
    this.music = this.sound.add("bomba", {
      loop: true,
      volume: 0.3,
    });
    this.music.play();
    this.buttonSound = this.sound.add("boton", {
      loop: false,
      volume: 0.3,
    });
  }
  botones() {
    this.botonVolver = this.add
      .image(70, 560, "volver")
      .setDepth(2)
      .setScale(0.04)
      .setScrollFactor(0)
      .setInteractive();
    this.botonVolver.setVisible(false);
    this.botonVolver.on("pointerup", () => this.scene.start("MenuScene"));
    this.botonVolver.on("pointerout", () => {
      this.botonVolver.clearTint();
    });
    this.botonVolver.on("pointerover", () => {
      this.buttonSound.play();
      this.botonVolver.tint = 0xffffff00;
    });

    this.retry = this.add
      .image(400, 350, "boton5")
      .setDepth(2)
      .setScale(0.04)
      .setScrollFactor(0)
      .setInteractive();
    this.retry.setVisible(false);
    this.retry.on("pointerup", () => this.scene.start("GameScene"));
    this.retry.on("pointerout", () => {
      this.retry.clearTint();
    });
    this.retry.on("pointerover", () => {
      this.buttonSound.play();
      this.retry.tint = 0xffffff00;
    });
  }
  gameOver(texto, muerto) {
    if (muerto == 1) {
      this.jugador1.anims.play("muerte1", true);
    } else {
      this.jugador2.anims.play("muerte2", false);
    }
    this.text.setText("Fin");
    this.text2.setText(texto);
    this.jugador1.body.stop();
    this.jugador2.body.stop();
    this.botonVolver.setVisible(true);
    this.retry.setVisible(true);
    this.music.stop();
  }
  player1Method() {
    this.jugador1 = this.physics.add
      .sprite(500, 400, "matilde")
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
      .setScale(0.1);
    this.jugador1.health = 100;
    this.jugador1.cd = 0;
    this.jugador1.body.setGravityY(1000).updateFromGameObject();
    this.physics.add.collider(this.jugador1, this.flat);
    this.player1Anims();
    this.disparos1 = this.physics.add.group();
    this.physics.add.collider(this.disparos1, this.jugador2, () => {
      this.dano(this.jugador2, 10);
      this.disparos1.destroy();
    });
    // this.disparo1 = this.disparos1.create(this.jugador1.x, this.jugador1.y, "bluebeam").setScale(0.3).refreshBody();
  }
  player1Anims() {
    this.anims.create({
      key: "muerte1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 8, end: 9 }),
      frameRate: 5,
    });
    this.anims.create({
      key: "golpe1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 8, end: 8 }),
      frameRate: 10,
    });
    this.anims.create({
      key: "abajo1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 7, end: 7 }),
      frameRate: 10,
      repeat: -1,
    });
    this.anims.create({
      key: "arriba1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 6, end: 6 }),
      frameRate: 10,
      repeat: -1,
    });
    this.anims.create({
      key: "punch1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 5, end: 5 }),
      frameRate: 10,
      repeat: 5000,
    });
    this.anims.create({
      key: "andar1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 3, end: 4 }),
      frameRate: 5,
      repeat: -1,
    });
    this.anims.create({
      key: "disparo1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 1, end: 2 }),
      frameRate: 5,
    });
    this.anims.create({
      key: "normal1",
      frames: this.anims.generateFrameNumbers("matilde", { start: 0, end: 0 }),
      frameRate: 10,
      repeat: -1,
    });
  }
  player2Method() {
    this.jugador2 = this.physics.add
      .sprite(900, 400, "rafael")
      .refreshBody()
      .setBounce(0)
      .setCollideWorldBounds(true)
      .setScale(0.1);
    this.jugador2.health = 100;
    this.jugador2.cd = 0;
    this.jugador2.flipX = true;
    this.jugador2.body.setGravityY(1000).updateFromGameObject();
    this.physics.add.collider(this.jugador2, this.flat);
    this.player2Anims();
    this.input.keyboard.on(
      "keydown-NUMPAD_ONE",
      function () {
        if (
          this.jugador2.x - this.jugador1.x <= 150 &&
          this.jugador2.x - this.jugador1.x >= -150
        ) {
          this.dano(this.jugador1, 10);
        }
        this.jugador2.anims.play("golpe2", true);
      },
      this
    );
    this.input.keyboard.on(
      "keydown-NUMPAD_TWO",
      function () {
        this.jugador2.anims.play("disparo2", true);
        this.jugador2Disparo();
      },
      this
    );
  }
  player2Anims() {
    this.anims.create({
      key: "muerte2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 8, end: 9 }),
      frameRate: 5,
    });
    this.anims.create({
      key: "golpe2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 8, end: 8 }),
      frameRate: 10,
    });
    this.anims.create({
      key: "abajo2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 7, end: 7 }),
      frameRate: 10,
      repeat: -1,
    });
    this.anims.create({
      key: "arriba2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 6, end: 6 }),
      frameRate: 10,
      repeat: -1,
    });
    this.anims.create({
      key: "punch2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 5, end: 5 }),
      frameRate: 10,
      repeat: 5000,
    });
    this.anims.create({
      key: "andar2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 3, end: 4 }),
      frameRate: 5,
      repeat: -1,
    });
    this.anims.create({
      key: "disparo2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 1, end: 2 }),
      frameRate: 5,
    });
    this.anims.create({
      key: "normal2",
      frames: this.anims.generateFrameNumbers("rafael", { start: 0, end: 0 }),
      frameRate: 10,
      repeat: -1,
    });
  }
  update(time) {
    this.tiempo = time;
    // Contador
    this.text.setText(this.timedEvent.getRepeatCount());
    // Movimientos jugador 1
    if (this.jugador1.x >= this.jugador2.x) {
      this.jugador1.derecha = true;
    } else {
      this.jugador1.derecha = false;
    }
    this.jugador1Movimiento(time);
    this.jugador2Movimiento(time);
    this.updateGameOver();

    this.udpateHealthBar();
    if (this.disparo2) {
      if (this.beam2.x >= 1360 || this.beam2.x <= 40) {
        this.disparo2 = false;
        this.beam2.destroy();
      }
    }
    if (this.disparo1) {
      if (this.beam1.x >= 1360 || this.beam1.x <= 40) {
        this.disparo1 = false;
        this.beam1.destroy();
      }
    }
    // Camera y tile
    this.background2.tilePositionX += 0.5;
    this.background.tilePositionX = this.cameraFollow.x / 2;
    this.cameraFollow.x = (this.jugador1.x + this.jugador2.x) / 2;
  }
  updateGameOver() {
    if (this.jugador2.health <= 0) {
      this.gameOver(
        "El jugador 2 se quedó sin vida,\n el ganador es jugador 1",
        2
      );
    } else if (this.jugador1.health <= 0) {
      this.gameOver(
        "El jugador 1 se quedó sin vida,\n el ganador es jugador 2",
        1
      );
    } else if (
      this.timedEvent.getRepeatCount() <= 0 &&
      this.jugador1.health >= this.jugador2.health
    ) {
      this.gameOver(
        "Os habéis quedado sin tiempo,\n el ganador es jugador 1",
        2
      );
    } else if (
      this.timedEvent.getRepeatCount() <= 0 &&
      this.jugador2.health >= this.jugador1.health
    ) {
      this.gameOver(
        "Os habéis quedado sin tiempo,\n el ganador es jugador 2",
        1
      );
    } else if (
      this.timedEvent.getRepeatCount() <= 0 &&
      this.jugador1.health == this.jugador2.health
    ) {
      this.gameOver("Os habéis quedado sin tiempo,\n el ganador es Empate");
    }
  }
  udpateHealthBar() {
    this.healthBar1.setScale(this.jugador1.health / 100, 1);
    this.healthBar1.x = 110 + this.jugador1.health - 100;
    this.healthBar2.setScale(this.jugador2.health / 100, 1);
    this.healthBar2.x = 690 + this.jugador2.health - 100;
  }
  dano(sprite, dano) {
    if (sprite == this.jugador1) {
      if (!this.keyboard.S.isDown) {
        sprite.health -= dano;
        sprite.anims.play("golpe1");
      }
    } else {
      if (!this.cursors.down.isDown) {
        sprite.health -= dano;
        sprite.anims.play("golpe2");
      }
    }
  }
  jugador1Movimiento(time) {
    var JisDown = this.input.keyboard.checkDown(this.keyboard.J, time + 1000);
    var KisDown = this.input.keyboard.checkDown(this.keyboard.K, 5000);
    if (this.keyboard.A.isDown && !this.keyboard.S.isDown) {
      this.jugador1.anims.play("andar1", true);
      this.jugador1.setVelocityX(-300);
      if (this.jugador1.derecha) {
        this.jugador1.flipX = this.jugador1.derecha;
      } else {
        this.jugador1.flipX = !this.jugador1.derecha;
      }
    } else if (
      this.keyboard.W.isDown &&
      this.jugador1.body.touching.down &&
      !this.keyboard.S.isDown
    ) {
      this.jugador1.setVelocityY(-600);
    } else if (this.keyboard.D.isDown && !this.keyboard.S.isDown) {
      this.jugador1.anims.play("andar1", true);
      this.jugador1.setVelocityX(300);
      if (this.jugador1.derecha) {
        this.jugador1.flipX = !this.jugador1.derecha;
      } else {
        this.jugador1.flipX = this.jugador1.derecha;
      }
    } else if (JisDown && !this.keyboard.S.isDown) {
      if (
        this.jugador2.x - this.jugador1.x <= 150 &&
        this.jugador2.x - this.jugador1.x >= -150
      ) {
        this.dano(this.jugador2, 10);
      }
      this.jugador1.anims.play("punch1", true);
    } else if (KisDown && !this.keyboard.S.isDown) {
      if (this.jugador1.cd <= time) {
        this.jugador1.anims.play("disparo1", false);
        this.jugador1Disparo();
        this.jugador1.cd = time + 5000;
      }
    } else {
      this.jugador1.clearTint();
      this.jugador1.flipX = this.jugador1.derecha;
      this.jugador1.anims.play("normal1");
      this.jugador1.setVelocityX(0);
      if (this.keyboard.S.isDown && this.jugador1.body.touching.down) {
        this.jugador1.tint = 0xffa500;
      }
    }
    // Altura
    if (this.jugador1.y >= this.alturaPasada1 + 1 && this.jugador1.y <= 450) {
      this.jugador1.anims.play("abajo1", true);
    }
    if (this.jugador1.y <= this.alturaPasada1 - 1 && this.jugador1.y <= 450) {
      this.jugador1.anims.play("arriba1", true);
    }
    this.alturaPasada1 = this.jugador1.y;
  }
  jugador1Disparo() {
    this.disparo1 = true;
    this.beam1 = this.physics.add
      .sprite(this.jugador1.x, this.jugador1.y, "orangebeam")
      .refreshBody()
      .setScale(0.1)
      .setCollideWorldBounds();
    if (!this.jugador1.derecha) {
      this.beam1.flipX = true;
      this.beam1.setVelocityX(300);
    } else {
      this.beam1.flipX = false;
      this.beam1.setVelocityX(-300);
    }
    this.physics.add.collider(this.beam1, this.jugador2, () => {
      this.dano(this.jugador2, 10);
      this.disparo1 = false;
      this.beam1.destroy();
    });
  }
  jugador2Movimiento(time) {
    if (this.cursors.left.isDown && !this.cursors.down.isDown) {
      this.jugador2.anims.play("andar2", true);
      this.jugador2.setVelocityX(-300);
      if (this.jugador1.derecha) {
        this.jugador2.flipX = !this.jugador2.derecha;
      } else {
        this.jugador2.flipX = !this.jugador2.derecha;
      }
    } else if (this.cursors.right.isDown && !this.cursors.down.isDown) {
      this.jugador2.anims.play("andar2", true);
      this.jugador2.setVelocityX(300);
      if (this.jugador1.derecha) {
        this.jugador2.flipX = this.jugador2.derecha;
      } else {
        this.jugador2.flipX = this.jugador2.derecha;
      }
    } else if (
      this.cursors.up.isDown &&
      this.jugador2.body.touching.down &&
      !this.cursors.down.isDown
    ) {
      this.jugador2.setVelocityY(-600);
    } else {
      this.jugador2.clearTint();
      this.jugador2.flipX = !this.jugador1.derecha;
      this.jugador2.anims.play("normal2");
      this.jugador2.setVelocityX(0);
      if (this.cursors.down.isDown && this.jugador2.body.touching.down) {
        this.jugador2.tint = 0x0000ff;
      }
    }

    if (this.jugador2.y >= this.alturaPasada + 1 && this.jugador2.y <= 450) {
      this.jugador2.anims.play("abajo2", true);
    }
    if (this.jugador2.y <= this.alturaPasada - 1 && this.jugador2.y <= 450) {
      this.jugador2.anims.play("arriba2", true);
    }
    this.alturaPasada = this.jugador2.y;
  }
  jugador2Disparo() {
    if (this.jugador2.cd <= this.tiempo) {
      this.disparo2 = true;
      this.beam2 = this.physics.add
        .sprite(this.jugador2.x, this.jugador2.y, "bluebeam")
        .refreshBody()
        .setScale(0.1)
        .setCollideWorldBounds();
      this.jugador2.cd = this.tiempo + 5000;
      if (this.jugador1.derecha) {
        this.beam2.flipX = true;
        this.beam2.setVelocityX(300);
      } else {
        this.beam2.flipX = false;
        this.beam2.setVelocityX(-300);
      }
      this.physics.add.collider(this.beam2, this.jugador1, () => {
        this.dano(this.jugador1, 10);
        this.disparo2 = false;
        this.beam2.destroy();
      });
    }
  }
}
