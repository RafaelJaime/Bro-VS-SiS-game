import pygame

from src.entities.fighter.Fighter import Fighter
from src.entities.fighter.utils.FighterControls import FighterControls

class FighterHuman(Fighter):
    """
    Clase que representa un luchador humano.
    Esta clase hereda de Fighter y se encarga de manejar la entrada del usuario.
    """
    
    def __init__(self, x, y, width, height, color, controls, name):
        super().__init__(x, y, width, height, color, controls, name)

    def process_input(self, opponent):
        """Procesa la entrada del usuario para determinar la acción a realizar."""
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
        return None