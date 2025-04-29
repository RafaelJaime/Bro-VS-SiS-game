import random
import numpy as np
from src.entities.fighter.Fighter import Fighter
from src.entities.fighter.utils.FighterControls import FighterControls
from src.ai.Agent import Agent

class FighterAI(Fighter):
    def __init__(self, x, y, width, height, color, name):
        super().__init__(x, y, width, height, color, name)
        self.agent = Agent()
        self.prev_health = self.health
        self.prev_state = None
        self.prev_action = None
        
    def process_input(self, opponent):
        # Store previous health for reward calculation
        opponent.prev_health = opponent.health
        
        state = self.agent.get_state(self, opponent)
        
        # Get action from agent
        action_list = self.agent.get_action(state, self)
        action_idx = action_list.index(1)
        action = FighterControls(action_idx)
        
        # Calculate reward if we have a previous state
        if self.prev_state is not None:
            reward = self.agent.calculate_reward(self, opponent, self.prev_action)
            done = self.is_defeated or opponent.is_defeated
            
            # Train the agent
            self.agent.train_short_memory(self.prev_state, action_list, reward, state, done)
            
            # Remember for long-term training
            self.agent.remember(self.prev_state, action_list, reward, state, done)
            
            if done:
                self.agent.train_long_memory()
                self.agent.n_games += 1
        
        # Store current state and action for next frame
        self.prev_state = state
        self.prev_action = action
        self.prev_health = self.health
        
        return action