import pygame
from abc import abstractmethod, ABC
from src.utils.Colors import RED
import numpy as np
import os

from src.entities.fighter.utils.FighterControls import FighterControls
from src.entities.fighter.utils.FighterBO import FighterBO
from src.entities.fighter.actions.Combat import Combat
from src.entities.fighter.actions.Movement import Movement
from src.entities.fighter.utils.Effects import Effects
from src.entities.fighter.utils.Renderer import Renderer

class Fighter(Combat, Movement, Effects, Renderer, ABC):
    def __init__(self, x, y, width, height, color, name, lowResources=False):
        Combat.__init__(self)
        Movement.__init__(self)
        Effects.__init__(self)
        Renderer.__init__(self)
        
        self.rect = pygame.Rect(x, y, width, height)
        self.color = color
        self.name = name
        self.secondary_color = RED
        self.lowResources = lowResources
        
        # Variables para animación
        self.current_frame = 0
        self.frame_timer = 0  # Nuevo: contador para controlar la duración de cada frame
        self.current_action = "idle"  # acción predeterminada
        self.facing_right = True  # dirección del personaje
        
        # Cargar imágenes si lowResources es falso
        if not lowResources:
            self.fighter_bo = self._load_fighter_data()
        else:
            self.fighter_bo = FighterBO(name, color)  # Sin animaciones
    
    def _load_fighter_data(self):
        """Carga los datos del luchador, incluyendo las animaciones"""
        return FighterBO.load_fighter_data(self.name, self.color, self.lowResources)

    def update(self, opponent):
        """
        Método principal que actualiza el estado del luchador.
        Este método actúa como punto de entrada que orquesta todas las capas de lógica.
        """
        # Si está derrotado, solo actualizar la animación de derrota
        if self.is_defeated:
            # Establecer la acción como "defeated" si no está ya establecida
            if self.current_action != "defeated":
                self.current_action = "defeated"
                self.current_frame = 0  # Reiniciar el frame para comenzar la animación desde el principio
                self.frame_timer = 0  # Reiniciar el contador de frame
                
            # Actualizar el contador de animación (sin prints de depuración)
            self.defeat_animation += 1
            
            # Seguir actualizando el frame de la animación para la secuencia de derrota
            if not self.lowResources and self.fighter_bo.has_animations():
                # Incrementar el contador de tiempo para este frame
                self.frame_timer += 1
                
                # Si hemos alcanzado la duración del frame actual, avanzar al siguiente
                frames = self.fighter_bo.get_animation_frames("defeated")
                if frames:
                    max_frames = len(frames)
                    current_frame_index = int(self.current_frame)
                    
                    # Obtener la duración del frame actual
                    frame_duration = self.fighter_bo.get_frame_duration("defeated", current_frame_index)
                    
                    # Si ha pasado el tiempo suficiente, avanzar al siguiente frame
                    if self.frame_timer >= frame_duration:
                        self.current_frame = (self.current_frame + 1)
                        # Si llegamos al final de la animación, mantenerla en el último frame
                        if self.current_frame >= max_frames:
                            self.current_frame = max_frames - 1
                        self.frame_timer = 0  # Reiniciar el contador
            
            self.update_particles()
            return
        
        # Procesar la entrada y actualizar el estado del luchador
        controls = self.process_input(opponent)
        
        # Actualizar la acción actual según los controles
        if not self.lowResources and self.fighter_bo.has_animations():
            self._update_action_state(controls)
            
            # Sistema de actualización de frames basado en duración
            self.frame_timer += 1  # Incrementar el contador de tiempo del frame actual
            
            # Obtener el índice del frame actual (redondeado a entero)
            current_frame_index = int(self.current_frame)
            
            # Obtener la duración del frame actual
            frame_duration = self.fighter_bo.get_frame_duration(self.current_action, current_frame_index)
            
            # Si ha pasado suficiente tiempo, avanzar al siguiente frame
            if self.frame_timer >= frame_duration:
                frames = self.fighter_bo.get_animation_frames(self.current_action)
                if frames:
                    max_frames = len(frames)
                    self.current_frame = (self.current_frame + 1) % max_frames
                    self.frame_timer = 0  # Reiniciar el contador
        
        # Realizar movimiento
        self.move(opponent, controls)
        
    def _update_action_state(self, controls):
        """Actualiza la acción actual según los controles"""
        # Determinar la acción basada en los controles
        if controls == FighterControls.ATTACK:
            new_action = "attack"
        elif controls == FighterControls.SHOOT:
            new_action = "shoot"
        elif controls == FighterControls.JUMP:
            new_action = "jump"
        elif controls == FighterControls.LEFT or controls == FighterControls.RIGHT:
            new_action = "run"
        else:
            new_action = "idle"
            
        # Actualizar la dirección del personaje
        if controls == FighterControls.RIGHT:
            self.facing_right = True
        elif controls == FighterControls.LEFT:
            self.facing_right = False
            
        # Si cambia la acción, reiniciar el frame y el contador
        if new_action != self.current_action:
            self.current_action = new_action
            self.current_frame = 0
            self.frame_timer = 0
    
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