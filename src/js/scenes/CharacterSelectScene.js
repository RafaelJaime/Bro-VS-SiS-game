import { BaseScene } from '../components/BaseScene.js'
import { Constants } from '../components/Constants.js'
import { Player } from '../components/Objects/Player.js'

export class CharacterSelectScene extends BaseScene {
  constructor() {
    super(Constants.scenes.characterSelect)
  }
  preload() {}

  create() {
    this.playersSelection = []
    this.setDefaultBackground(false)
    this.addReturnButton(false)
    this.playButton = this.addButton(
      Constants.game.width - 70,
      Constants.game.height - 40,
      Constants.assets.images.button6,
      2,
      null,
      true,
      null,
      0.04
    )
    this.playButton.setVisible(false)
    this.playButton.setFlip(true, false)
    this.addText(230, 20, 'Select your fighters', '40px bold')
    this.addSelectPlayer()
    this.decision = []
    this.informationText = this.addText(
      150,
      Constants.game.height - 100,
      [],
      '40px bold'
    )
  }
  update() {
    super.update()
  }

  getOrderedCharacters(characters) {
    var orderCharacters = []
    for (let index = 0; index < this.numberRow; index++) {
      orderCharacters.push([])
    }
    for (let index = 0; index < characters.length; index++) {
      const element = characters[index]
      orderCharacters[index % this.numberRow].push(element)
    }
    return orderCharacters
  }

  addSelectPlayer() {
    var characters = Constants.getCharacterArray()
    this.numberRow = Constants.numberRow
    this.cellWidth =
      (Constants.game.width - 400) /
      ((characters.length % 2 === 0
        ? characters.length
        : characters.length + 1) /
        this.numberRow)
    this.cellHeight = (Constants.game.height - 300) / this.numberRow

    var orderCharacters = this.getOrderedCharacters(characters)

    for (let index = 0; index < orderCharacters.length; index++) {
      const element = orderCharacters[index]
      for (let index2 = 0; index2 < element.length; index2++) {
        const character = element[index2]
        this.addPlayerInfo(
          200 + this.cellWidth * index,
          100 + this.cellHeight * index2,
          this.cellWidth,
          this.cellHeight,
          character
        )
      }
    }
  }

  addPlayerInfo(x, y, width, height, character) {
    var group = this.add.group()
    var rectangle = this.add
      .rectangle(x, y, width, height, character.color)
      .setOrigin(0, 0)
    var whiteRectangle = this.add
      .rectangle(x + 10, y + 10, width - 20, height - 20, 0xffffff)
      .setAlpha(0.4)
      .setOrigin(0)
    var text = this.add
      .text(x + 20, y + 20, character.name, {
        fontSize: '20px',
        color: '#000000',
      })
      .setOrigin(0, 0)
    var characterImage = new Player(
      this,
      x + 100,
      y + 160,
      character,
      false,
      character
    )
    characterImage.play(Player.animation.face)
    characterImage.setScale(0.1)
    group.add(rectangle)
    group.add(whiteRectangle)
    group.add(text)
    group.add(characterImage)

    var rectangle = this.add
      .rectangle(x, y, width, height, 0xffffff, 0)
      .setOrigin(0, 0)
      .setInteractive()
    rectangle.on(Constants.events.pointer.up, function (event) {
      if (character.enabled) {
        this.scene.addCharacter(character)
      }
    })
  }

  addCharacter(character) {
    if (this.decision.length == 1) {
      this.playButton.setVisible(true)
      this.playButton.on(Constants.events.pointer.up, () => {
        this.stopMusic()
        this.scene.start(Constants.scenes.newGame, {
          player1: this.decision[0],
          player2: this.decision[1],
        })
      })
    }
    if (this.decision.length <= 1) {
      this.decision.push(character)
      this.add
        .rectangle(270, 540, 250, 90, character.color)
        .setAlpha(0.5)
        .setStrokeStyle(10, character.color, 0.5)
      this.add
        .rectangle(270, 540, 250, 90, Constants.colors.white)
        .setAlpha(0.3)
      var finalText = []
      for (let index = 0; index < this.decision.length; index++) {
        const character = this.decision[index]
        finalText.push('P' + (index + 1).toString() + ': ' + character.name)
      }
      this.informationText.setText(finalText)
    }
  }
}
