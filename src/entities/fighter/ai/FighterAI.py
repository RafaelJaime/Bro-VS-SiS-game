import random
from src.entities.fighter.Fighter import Fighter
from src.entities.fighter.utils.FighterControls import FighterControls

class FighterAI(Fighter):
    def process_input(self, opponent):
        # AI decision making
        if self.ai_decision_timer <= 0:
            self.ai_decision_timer = 0  # Ajustar según necesidad
            return self.ai_make_decision(opponent)
        else:
            self.ai_decision_timer -= 1

    def ai_make_decision(self, opponent):
        """AI decision making logic"""
        dx = opponent.rect.centerx - self.rect.centerx
        dy = opponent.rect.centery - self.rect.centery
        distance = (dx**2 + dy**2)**0.5

        # If opponent is close, decide between attack and jump
        if distance < 100:
            if random.random() < 0.7:  # 70% chance to attack when close
                return FighterControls.ATTACK
            else:
                return FighterControls.UP
        
        # If opponent is at medium range, maybe shoot
        elif distance < 300:
            if random.random() < 0.4:  # 40% chance to shoot
                return FighterControls.SHOOT
        
        # Move towards opponent with some randomness
        if dx > 0:
            return FighterControls.RIGHT
        else:
            return FighterControls.LEFT