import pygame
from abc import ABC, abstractmethod
from src.utils.GameState import GameState

class Screen(ABC):
    """
    Base class for all screens in the game.
    This class defines the common behavior for screens like drawing text,
    updating and handling events.
    """
    def __init__(self, screen, width, height):
        self.screen = screen
        self.width = width
        self.height = height
        
        # Common fonts that can be used by all screens
        self.title_font = pygame.font.SysFont('Arial', 60, True)
        self.subtitle_font = pygame.font.SysFont('Arial', 30)
        self.font = pygame.font.SysFont('Arial', 30)  # Standard font for general use
        self.info_font = pygame.font.SysFont('Arial', 20)
        
        # For keyboard/mouse navigation
        self.is_keyboard_mode = False
        self.buttons = []
        self.current_button = 0

    def draw_text(self, text, font, text_col, x, y, shadow=True):
        """
        Draws text on the screen with an optional shadow effect.
        
        Args:
            text (str): The text to draw
            font (pygame.font.Font): The font to use
            text_col (tuple): The color of the text (r,g,b)
            x (int): X position
            y (int): Y position
            shadow (bool): Whether to add a shadow effect
        """
        if shadow:
            shadow_img = font.render(text, True, (0, 0, 0))
            self.screen.blit(shadow_img, (x + 2, y + 2))
        
        img = font.render(text, True, text_col)
        self.screen.blit(img, (x, y))
    
    def check_mouse_movement(self):
        """Check if mouse moved to switch to mouse mode"""
        if pygame.mouse.get_rel() != (0, 0):
            self.is_keyboard_mode = False
    
    def update_button_focus(self):
        """Update focus for buttons when in keyboard mode"""
        if self.is_keyboard_mode:
            for i, button in enumerate(self.buttons):
                button.is_focused = (i == self.current_button)
    
    def update_and_draw_buttons(self, mouse_pos):
        """Update and draw all buttons"""
        for button in self.buttons:
            button.update(mouse_pos, self.is_keyboard_mode)
            button.draw(self.screen)
    
    @abstractmethod
    def update(self, mouse_pos):
        """
        Update the screen state and draw all elements.
        Must be implemented by subclasses.
        
        Args:
            mouse_pos (tuple): The current mouse position (x,y)
        """
        pass
    
    @abstractmethod
    def handle_event(self, event) -> GameState:
        """
        Handle pygame events.
        Must be implemented by subclasses.
        
        Args:
            event (pygame.event.Event): The event to handle
            
        Returns:
            str or None: The next state to transition to, or None to stay in the current state
        """
        pass