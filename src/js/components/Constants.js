export class Constants {
  static pipeline = 'Light2D'

  static fonts = class Fonts {
    static primary20 = '20px monospace'
    static primary18 = '18px monospace'
    static primaryBold25 = 'bold 25px monospace'
  }
  static colors = class Colors {
    static black = 0xffffff
    static gray = 0x222222
    static lightGray = 0x555555
    static yellow = 0xffffff00
  }

  static scenes = class Scenes {
    static load = 'LoadScene'
    static menu = 'MenuScene'
    static game = 'GameScene'
    static instructions = 'instructionsScene'
    static credit = 'CreditScene'
  }

  static texts = class Texts {
    static version = 'v0.5'
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
      static greenBar = 'greenBar'
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
