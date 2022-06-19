import { BaseScene } from '../components/BaseScene.js'
import { Constants, Player } from '../components/Constants.js'

export class CharacterSelectScene extends BaseScene {
  constructor() {
    super(Constants.scenes.characterSelect)
  }
  preload() {}

  create() {
    this.playersSelection = []
    this.setDefaultBackground(false)
    this.addReturnButton(true)
    this.playButton = this.addButton(
      Constants.game.width - 70,
      Constants.game.height - 40,
      Constants.assets.images.button6,
      2,
      null,
      true,
      Constants.scenes.newGame,
      0.04
    )
    this.playButton.setFlip(true, false)
    //this.playButton.setVisible(false)
    this.addText(230, 20, 'Select your fighters', '40px bold')
    this.addSelectPlayer()

    for (let index = 0; index < this.playersSelection.length; index++) {
      const element = this.playersSelection[index]
      console.log(element)
      element.on('pointerout', function (event) {
        console.log(event)
        this.setTint(0xff0000)
      })
    }
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
          200 + this.cellWidth * index2,
          100 + this.cellHeight * index,
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
    var characterImage = new Player(this, x + 100, y + 160, character)
    characterImage.play(Player.animation.face)
    characterImage.setScale(0.1)
    group.add(rectangle)
    group.add(whiteRectangle)
    group.add(text)
    group.add(characterImage)
    this.playersSelection.push(group)
    /*rectangle.on('pointerover', function (event) {
      console.log('event')
      this.setTint(0xff0000)
    })
    characterImage.on('pointerout', function (event) {
      this.clearTint()
    })*/
  }
}
