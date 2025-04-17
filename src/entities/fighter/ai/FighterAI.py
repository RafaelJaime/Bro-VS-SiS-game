import random

class FighterAI:
    def ai_make_decision(self, opponent):
        """AI decision making logic"""
        dx = opponent.rect.centerx - self.rect.centerx
        dy = opponent.rect.centery - self.rect.centery
        distance = (dx**2 + dy**2)**0.5

        # Reset decision timer
        self.ai_decision_timer = random.randint(10, 30)  # Random delay between decisions

        # If opponent is close, decide between attack and jump
        if distance < 100:
            if random.random() < 0.7:  # 70% chance to attack when close
                return 'attack'
            else:
                return 'jump'
        
        # If opponent is at medium range, maybe shoot
        elif distance < 300:
            if random.random() < 0.4:  # 40% chance to shoot
                return 'shoot'
        
        # Move towards opponent with some randomness
        if dx > 0:
            return 'move_right'
        else:
            return 'move_left'