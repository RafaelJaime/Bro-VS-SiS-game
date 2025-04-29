import pygame
from abc import abstractmethod, ABC
from src.utils.Colors import RED
import numpy as np

from src.entities.fighter.utils.FighterControls import FighterControls
from src.entities.fighter.actions.Combat import Combat
from src.entities.fighter.actions.Movement import Movement
from src.entities.fighter.utils.Effects import Effects
from src.entities.fighter.utils.Renderer import Renderer

class Fighter(Combat, Movement, Effects, Renderer, ABC):
    def __init__(self, x, y, width, height, color, name):
        Combat.__init__(self)
        Movement.__init__(self)
        Effects.__init__(self)
        Renderer.__init__(self)
        
        self.rect = pygame.Rect(x, y, width, height)
        self.color = color
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

    def get_state(self, opponent):
        """
        Obtiene el estado actual del luchador en relación a su oponente y el juego.
        Este método es flexible y puede aceptar o bien:
        - Un oponente directo (Fighter)
        - Un objeto game (GamePlay) del cual extraer el oponente
        
        Args:
            opponent_or_game: El oponente directo o la instancia del juego
            
        Returns:
            numpy.array: Vector de estado con las siguientes características normalizadas:
                - Posición X del luchador (normalizada por ancho de pantalla)
                - Posición Y del luchador (normalizada por alto de pantalla)
                - Posición X del oponente
                - Posición Y del oponente
                - Distancia al oponente
                - Dirección X al oponente
                - Dirección Y al oponente
                - Salud del luchador
                - Salud del oponente
                - Estado de cooldown de ataque
                - Estado de cooldown de disparo
        """
        # Valores predeterminados para normalización
        game_width = 800
        game_height = 600
        
        # Calcular vectores de dirección y distancia
        dx = opponent.rect.centerx - self.rect.centerx
        dy = opponent.rect.centery - self.rect.centery
        distance = (dx**2 + dy**2)**0.5
        
        # Vectores de dirección normalizados
        dir_x = dx / distance if distance > 0 else 0
        dir_y = dy / distance if distance > 0 else 0
        
        return np.array([
            self.rect.centerx / game_width,      # Posición X normalizada
            self.rect.centery / game_height,     # Posición Y normalizada
            opponent.rect.centerx / game_width,  # Posición X del oponente
            opponent.rect.centery / game_height, # Posición Y del oponente
            distance / game_width,               # Distancia normalizada
            dir_x,                               # Dirección X al oponente
            dir_y,                               # Dirección Y al oponente
            self.health / 100,                   # Salud normalizada
            opponent.health / 100,               # Salud del oponente
            float(self.attack_cooldown > 0),     # Estado de cooldown de ataque
            float(self.shoot_cooldown > 0)       # Estado de cooldown de disparo
        ], dtype=float)