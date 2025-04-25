import pygame
from abc import abstractmethod, ABC
from src.utils.Colors import RED

from src.entities.fighter.utils.FighterControls import FighterControls
from src.entities.fighter.actions.Combat import Combat
from src.entities.fighter.actions.Movement import Movement
from src.entities.fighter.utils.Effects import Effects
from src.entities.fighter.utils.Renderer import Renderer

class Fighter(Combat, Movement, Effects, Renderer, ABC):
    def __init__(self, x, y, width, height, color, controls, name):
        Combat.__init__(self)
        Movement.__init__(self)
        Effects.__init__(self)
        Renderer.__init__(self)
        
        self.rect = pygame.Rect(x, y, width, height)
        self.color = color
        self.controls = controls
        self.name = name
        self.secondary_color = RED

    def update(self, opponent):
        """
        Método principal que actualiza el estado del luchador.
        Este método actúa como punto de entrada que orquesta todas las capas de lógica.
        """
        # Si está derrotado, solo actualizar la animación de derrota
        if self.is_defeated:
            self.defeat_animation += 1
            self.update_particles()
            return
            
        self.move(opponent, self.process_input(opponent))
        
    @abstractmethod
    def process_input(self, opponent) -> FighterControls:
        """
        Método abstracto que debe ser implementado por las clases hijas.
        Procesa la entrada del jugador o la IA para determinar las acciones del luchador.
        """
        pass