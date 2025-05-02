import random
import numpy as np
from src.entities.fighter.Fighter import Fighter
from src.entities.fighter.utils.FighterControls import FighterControls
from src.ai.Agent import Agent

class FighterAI(Fighter):
    def __init__(self, x, y, width, height, color, name):
        super().__init__(x, y, width, height, color, name)
        # Use the shared instance of Agent
        self.agent = Agent.get_instance()
        self.prev_health = self.health
        self.prev_state = None
        self.prev_action = None
        self.last_reward = 0  # Añadido para tracking de recompensas
        self.training_frames = 0  # Counter for training frames
        self.has_processed_game_end = False  # Flag to track if game end has been processed
        print(f"FighterAI initialized: {name}")
    
    def process_game_over(self, opponent):
        """
        Process game over logic - to be called when the game ends.
        Handles final rewards, training, and game counting.
        
        Args:
            opponent: The opponent fighter
        """
        print(f"GAME DONE! {self.name} defeated: {self.is_defeated}, Opponent defeated: {opponent.is_defeated}")
        print(f"Training long memory. Agent games before: {self.agent.n_games}")
        
        # Calculate final reward
        final_reward = self.agent.calculate_reward(self, opponent, self.prev_action)
        
        # Train with the final state and reward
        final_state = self.agent.get_state(self, opponent)
        action_list = [0] * len(FighterControls)
        if self.prev_action:
            action_list[self.prev_action.value] = 1
            
        self.agent.train_short_memory(self.prev_state, action_list, final_reward, final_state, True)
        self.agent.remember(self.prev_state, action_list, final_reward, final_state, True)
        
        # Train long memory and increment game counter
        self.agent.train_long_memory()
        self.agent.n_games += 1
        print(f"Increased games counter to: {self.agent.n_games}")
        
        # Mark that we've processed this game end
        self.has_processed_game_end = True
        
    def process_input(self, opponent):
        # Store previous health for reward calculation
        opponent.prev_health = opponent.health
        
        # Get current state
        state = self.agent.get_state(self, opponent)
        
        # Get action from agent
        action_list = self.agent.get_action(state, self)
        action_idx = action_list.index(1)
        action = FighterControls(action_idx)
        
        # Calculate reward if we have a previous state
        if self.prev_state is not None and not self.has_processed_game_end:
            self.training_frames += 1
            reward = self.agent.calculate_reward(self, opponent, self.prev_action)
            self.last_reward = reward  # Guardamos la última recompensa para tracking
            
            # Train the agent
            self.agent.train_short_memory(self.prev_state, action_list, reward, state, False)
            
            # Remember for long-term training
            self.agent.remember(self.prev_state, action_list, reward, state, False)
        elif self.prev_state is None:
            print(f"First frame for {self.name}, prev_state is None")
        
        # Store current state and action for next frame
        self.prev_state = state
        self.prev_action = action
        self.prev_health = self.health
        
        return action