import pygame
from src.utils.Colors import RED
from src.entities.fighter.FighterControls import FighterControls

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
            
        # Procesamos la entrada (teclado o IA) para determinar la acción
        action = self.process_input(opponent)
        
        # Aplicamos la acción para mover al luchador
        self.move(opponent, action)

    def process_input(self, opponent):
        """Procesa la entrada del usuario para determinar la acción a realizar."""
        # Regular player controls
        key = pygame.key.get_pressed()
        
        # Shooting mechanic
        if self.shoot_cooldown > 0:
            self.shoot_cooldown -= 1
            
        # Verificar cada control y determinar la acción más prioritaria
        if key[self.controls[FighterControls.SHOOT]] and self.can_shoot():
            return FighterControls.SHOOT
        elif key[self.controls[FighterControls.PROTECT]] and not self.protecting and self.protect_cooldown == 0:
            return FighterControls.PROTECT
        elif not self.attacking and not self.protecting:
            if key[self.controls[FighterControls.ATTACK]] and self.attack_cooldown == 0:
                return FighterControls.ATTACK
            elif key[self.controls[FighterControls.UP]] and not self.jumping:
                return FighterControls.UP
            elif key[self.controls[FighterControls.LEFT]]:
                return FighterControls.LEFT
            elif key[self.controls[FighterControls.RIGHT]]:
                return FighterControls.RIGHT
        action = None
        
        if self.is_ai:
            # AI decision making
            if self.ai_decision_timer <= 0:
                self.ai_current_action = self.ai_make_decision(opponent)
                self.ai_decision_timer = 10  # Ajustar según necesidad
            else:
                self.ai_decision_timer -= 1
                
            # Map AI decision to FighterControls
            if self.ai_current_action == 'move_right':
                action = FighterControls.RIGHT
            elif self.ai_current_action == 'move_left':
                action = FighterControls.LEFT
            elif self.ai_current_action == 'jump':
                action = FighterControls.UP
            elif self.ai_current_action == 'attack':
                action = FighterControls.ATTACK
            elif self.ai_current_action == 'shoot':
                action = FighterControls.SHOOT
            elif self.ai_current_action == 'protect':
                action = FighterControls.PROTECT

        return action