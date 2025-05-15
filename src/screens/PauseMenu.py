import pygame
from src.utils.Button import Button
from src.utils.Colors import WHITE
from src.screens.Screen import Screen
from src.utils.GameState import GameState

class PauseMenu(Screen):
    def __init__(self, screen, width, height):
        super().__init__(screen, width, height)
        
        # Create buttons for pause menu
        self.continue_button = Button(width // 2 - 100, height // 2 - 30, 200, 50, 
                                    "Continue", (70, 130, 180), (100, 160, 210))
        self.menu_button = Button(width // 2 - 100, height // 2 + 30, 200, 50, 
                                "Main Menu", (180, 70, 70), (210, 100, 100))

        # Button navigation
        self.buttons = [self.continue_button, self.menu_button]
        self.current_button = 0

    def update(self, mouse_pos):
        # Check if mouse moved to switch to mouse mode
        self.check_mouse_movement()
            
        # Draw semi-transparent overlay
        overlay = pygame.Surface((self.width, self.height), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 150))
        self.screen.blit(overlay, (0, 0))
        
        # Draw pause menu text
        pause_text = "PAUSED"
        self.draw_text(pause_text, self.title_font, WHITE,
                      self.width // 2 - self.title_font.size(pause_text)[0] // 2, self.height // 4)
        
        # Update button focus in keyboard mode
        self.update_button_focus()
        
        # Update and draw buttons
        self.update_and_draw_buttons(mouse_pos)

    def handle_event(self, event) -> GameState:
        if event.type == pygame.KEYDOWN:
            self.is_keyboard_mode = True
            if event.key == pygame.K_ESCAPE:
                return GameState.PLAYING
            elif event.key in [pygame.K_w, pygame.K_UP] and self.current_button > 0:
                self.current_button -= 1
            elif event.key in [pygame.K_s, pygame.K_DOWN] and self.current_button < len(self.buttons) - 1:
                self.current_button += 1
            
            if self.buttons[self.current_button].is_clicked(event):
                if self.current_button == 0:
                    return GameState.PLAYING
                else:
                    return GameState.MAIN_MENU

        if event.type == pygame.MOUSEBUTTONDOWN:
            self.is_keyboard_mode = False
            if self.continue_button.is_clicked(event):
                return GameState.PLAYING
            elif self.menu_button.is_clicked(event):
                return GameState.MAIN_MENU
            
        return None