import pygame
from src.utils.Colors import RED

from src.entities.fighter.actions.Combat import Combat
from src.entities.fighter.actions.Movement import Movement
from src.entities.fighter.utils.Effects import Effects
from src.entities.fighter.utils.Renderer import Renderer
from src.entities.fighter.ai.FighterAI import FighterAI
from src.entities.fighter.FighterControls import FighterControls

WIDTH, HEIGHT = 800, 600

class Fighter(Combat, Movement, Effects, Renderer, FighterAI):
    def __init__(self, x, y, width, height, color, controls, name):
        # Inicializar todas las clases padre
        Combat.__init__(self)
        Movement.__init__(self)
        Effects.__init__(self)
        Renderer.__init__(self)
        
        # Inicializar atributos básicos específicos de Fighter
        self.rect = pygame.Rect(x, y, width, height)
        self.color = color
        self.controls = controls
        self.name = name
        
        self.secondary_color = RED