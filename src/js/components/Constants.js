export class Constants {
  static pipeline = 'Light2D'

  static game = class Game {
    static width = 800
    static height = 600
    static arcadeEngine = 'arcade'
    static matterEngine = 'matter'
    static debug = true
    static debugShowBody = false
    static debugShowStaticBody = false
    static debugShowVelocity = false
  }

  static gameModes = class GameMode {
    static twoVtwo = class TwoVTwo {
      static time = 99
      static timeDelay = 1000
      static timeDelayFinalFast = 500
      static timeDelayFinalSlow = 1000
      static finalProbability = 9
    }
  }

  static fonts = class Fonts {
    static primary20 = '20px monospace'
    static primary18 = '18px monospace'
    static primaryBold25 = 'bold 25px monospace'
    static secondaryBold25 = 'bold 25px sans-serif'
    static secondaryBold50 = 'bold 50px sans-serif'
    static size32 = '32px'
    static size26 = '26px'
  }

  static colors = class Colors {
    static whiteString = '#fff'
    static white = 0xffffff
    static black = 0xffffff
    static blackHEX = 0x000000
    static gray = 0x222222
    static lightGray = 0x555555
    static darkGray = 0xaaaaaa
    static yellow = 0xffffff00
    static red = 0xff0000
    static lightBlue = 0x6666ff
    static darkBlue = 0x4242a3
    static lightRed = 0xff5733
    static darkRed = 0xc70039
    static sisterRed = 0xe63c2e
    static brotherBlue = 0x0000ff
  }

  static scenes = class Scenes {
    static load = 'LoadScene'
    static menu = 'MenuScene'
    static game = 'GameScene'
    static newGame = 'NewGameScene'
    static instructions = 'InstructionsScene'
    static credit = 'CreditScene'
  }

  static texts = class Texts {
    static version = 'v0.5'
    static player1 = 'Player 1'
    static player1 = 'Player 2'
    static movement = 'Movimiento'
    static habilities = 'Habilidades'
    static credits = 'Créditos'
    static developer = 'Desarrollado por: Rafael Jaime Moreno'
    static artist = 'Arte por: Matilde Jaime Moreno'
    static musician = 'Música libre de copyright'
    static thanks = 'Special thanks to you for playing'
    static instructions = 'Instrucciones'
  }

  static events = class EventsStates {
    static progress = 'progress'
    static complete = 'complete'

    static pointer = class Pointer {
      static out = 'pointerout'
      static up = 'pointerup'
      static over = 'pointerover'
    }
  }

  static assets = class Assets {
    static images = class Images {
      static title = 'title'
      static title2 = 'title2'
      static title3 = 'title3'
      static front = 'front'
      static button1 = 'button1'
      static button2 = 'button2'
      static button3 = 'button3'
      static button5 = 'button5'
      static player11 = 'player11'
      static player21 = 'player21'
      static player22 = 'player22'
      static player12 = 'player12'
      static volver = 'volver'
      static wasd1 = 'wasd1'
      static wasd2 = 'wasd2'
      static jkl1 = 'jkl1'
      static jkl2 = 'jkl2'
      static center = 'center'
      static platform = 'platform'
      static redBar = 'redBar'
      static rafael = 'rafael'
      static matilde = 'matilde'
      static bluebeam = 'bluebeam'
      static orangebeam = 'orangebeam'
    }

    static audios = class Audios {
      static bomb = 'bomb'
      static title = 'title_music'
      static credit = 'credit'
      static button = 'button'
    }
  }
}
