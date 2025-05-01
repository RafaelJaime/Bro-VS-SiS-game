import torch
import random
import numpy as np
from collections import deque
from src.ai.Model import Linear_QNet, QTrainer
from src.entities.fighter.utils.FighterControls import FighterControls
from src.entities.fighter.Fighter import Fighter

MAX_MEMORY = 100_000
BATCH_SIZE = 1000
LR = 0.001

class Agent:
    # Singleton instance to be shared across resets
    _instance = None
    
    @classmethod
    def get_instance(cls):
        if cls._instance is None:
            cls._instance = Agent()
        return cls._instance
    
    def __init__(self):
        self.n_games = 0
        self.epsilon = 0  # randomness
        self.gamma = 0.9  # discount rate
        self.memory = deque(maxlen=MAX_MEMORY)
        # Input size: 14 state variables (11 fighter state + 3 game state), output size: number of possible actions
        self.model = Linear_QNet(14, 256, len(FighterControls))
        self.trainer = QTrainer(self.model, lr=LR, gamma=self.gamma)

    def get_state(self, fighter: Fighter, opponent):
        """
        Obtiene el estado completo usando el método unificado get_state de Fighter
        """
        # Obtener el estado base del luchador (11 variables)
        fighter_state = fighter.get_state(opponent)
        
        # Por ahora, usamos valores predeterminados para las variables de estado del juego
        game_state = np.array([
            1.0,  # Tiempo restante normalizado (valor predeterminado)
            0.0,  # Indicador de muerte súbita (valor predeterminado)
            0.0   # Indicador de final de juego (valor predeterminado)
        ], dtype=float)
        
        # Combinar los estados
        return np.concatenate([fighter_state, game_state])

    def remember(self, state, action, reward, next_state, done):
        self.memory.append((state, action, reward, next_state, done))

    def train_long_memory(self):
        if len(self.memory) > BATCH_SIZE:
            mini_sample = random.sample(self.memory, BATCH_SIZE)
        else:
            mini_sample = self.memory

        states, actions, rewards, next_states, dones = zip(*mini_sample)
        self.trainer.train_step(states, actions, rewards, next_states, dones)

    def train_short_memory(self, state, action, reward, next_state, done):
        self.trainer.train_step(state, action, reward, next_state, done)

    def get_action(self, state, fighter):
        # Random moves: tradeoff exploration / exploitation
        self.epsilon = max(80 - self.n_games, 5)  # Minimum 5% random actions
        final_move = [0] * len(FighterControls)
        
        if random.randint(0, 200) < self.epsilon:
            # Random action
            move = random.randint(0, len(FighterControls) - 1)
            final_move[move] = 1
        else:
            # Predicted action
            state0 = torch.tensor(state, dtype=torch.float)
            prediction = self.model(state0)
            move = torch.argmax(prediction).item()
            final_move[move] = 1

        return final_move

    def calculate_reward(self, fighter, opponent, action):
        reward = 0
        
        # Reward for damaging opponent
        if opponent.health < opponent.prev_health:
            reward += 10
            
        # Penalty for taking damage
        if fighter.health < fighter.prev_health:
            reward -= 8
            
        # Small penalty for missing attacks to encourage precision
        if action == FighterControls.ATTACK and fighter.attack_cooldown > 0:
            reward -= 1
            
        # Reward for returning a projectile
        if hasattr(fighter, 'last_bounce_time'):
            # Check if a projectile was bounced in the last frame
            if hasattr(fighter, '_last_checked_bounce_time'):
                if fighter.last_bounce_time > fighter._last_checked_bounce_time:
                    reward += 15  # Significant reward for successfully returning a projectile
            # Store the last time we checked for bounces
            fighter._last_checked_bounce_time = fighter.last_bounce_time
            
        # Reward for maintaining good distance
        dx = opponent.rect.centerx - fighter.rect.centerx
        distance = abs(dx)
        if 100 <= distance <= 300:  # Ideal fighting range
            reward += 0.5
            
        # Reward for winning
        if opponent.is_defeated:
            reward += 100
        elif fighter.is_defeated:
            reward -= 100
            
        return reward
