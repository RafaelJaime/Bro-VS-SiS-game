import pygame
from src.utils.Button import Button
from src.utils.Colors import WHITE
from src.utils.Background import Background
from src.screens.Screen import Screen
from src.utils.GameState import GameState

class MainMenu(Screen):
    def __init__(self, screen, width, height):
        super().__init__(screen, width, height)
        
        # Create background
        self.background = Background(width, height)
        
        # Create buttons
        self.start_button = Button(width // 2 - 75, height // 2, 150, 50, "Start Game", (70, 130, 180), (100, 160, 210))
        self.exit_button = Button(width // 2 - 75, height // 2 + 70, 150, 50, "Exit", (180, 70, 70), (210, 100, 100))
        
        # Button navigation
        self.buttons = [self.start_button, self.exit_button]
        self.current_button = 0

    def update(self, mouse_pos):
        # Check if mouse moved to switch to mouse mode
        self.check_mouse_movement()
        
        # Draw background
        self.background.draw(self.screen)
        
        # Draw title
        title_text = "PYGAME FIGHTER"
        self.draw_text(title_text, self.title_font, WHITE, 
                      self.width // 2 - self.title_font.size(title_text)[0] // 2, self.height // 4)
        
        # Draw subtitle
        subtitle_text = "The Ultimate Battle"
        self.draw_text(subtitle_text, self.subtitle_font, (200, 200, 200),
                      self.width // 2 - self.subtitle_font.size(subtitle_text)[0] // 2, self.height // 4 + 70)
        
        # Update button focus in keyboard mode
        self.update_button_focus()
        
        # Update and draw buttons
        self.update_and_draw_buttons(mouse_pos)
        
        # Draw credits
        credit_text = "Use WASD/Arrows to move, F/K to attack, G/L to shoot"
        self.draw_text(credit_text, self.info_font, (200, 200, 200),
                      self.width // 2 - self.info_font.size(credit_text)[0] // 2, self.height - 30)

    def handle_event(self, event) -> GameState:
        if event.type == pygame.KEYDOWN:
            self.is_keyboard_mode = True
            if event.key in [pygame.K_w, pygame.K_UP] and self.current_button > 0:
                self.current_button -= 1
            elif event.key in [pygame.K_s, pygame.K_DOWN] and self.current_button < len(self.buttons) - 1:
                self.current_button += 1
            
            if self.buttons[self.current_button].is_clicked(event):
                if self.current_button == 0:
                    return GameState.DIFFICULTY_SELECT
                else:
                    return GameState.EXIT
        
        # Handle mouse clicks
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.is_keyboard_mode = False
            if self.start_button.is_clicked(event):
                return GameState.DIFFICULTY_SELECT
            elif self.exit_button.is_clicked(event):
                return GameState.EXIT
        
        return None