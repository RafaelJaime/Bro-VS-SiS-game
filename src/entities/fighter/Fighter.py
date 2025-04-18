import pygame
import math
import random
from src.utils.Colors import GREEN, YELLOW, ORANGE, RED, WHITE, BLUE
from src.utils.Particle import Particle
from src.utils.ScreenShake import screen_shake
from src.entities.fighter.Projectile import Projectile

# Importar nuestros componentes refactorizados
from src.entities.fighter.actions.Combat import Combat
from src.entities.fighter.actions.Movement import Movement
from src.entities.fighter.utils.Effects import Effects
from src.entities.fighter.utils.Renderer import Renderer
from src.entities.fighter.ai.FighterAI import FighterAI

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
        
        # Crear colores secundarios para efectos
        r, g, b = self.color
        self.secondary_color = RED