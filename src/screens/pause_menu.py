import pygame
from src.Button import Button
from src.Colors import WHITE

class PauseMenu:
    def __init__(self, screen, width, height):
        self.screen = screen
        self.width = width
        self.height = height
        self.title_font = pygame.font.SysFont('Arial', 60, True)
        
        # Create buttons for pause menu
        self.continue_button = Button(width // 2 - 100, height // 2 - 30, 200, 50, 
                                    "Continue", (70, 130, 180), (100, 160, 210))
        self.menu_button = Button(width // 2 - 100, height // 2 + 30, 200, 50, 
                                "Main Menu", (180, 70, 70), (210, 100, 100))

        # Button navigation
        self.buttons = [self.continue_button, self.menu_button]
        self.current_button = 0
        self.is_keyboard_mode = False

    def draw_text(self, text, font, text_col, x, y, shadow=True):
        if shadow:
            shadow_img = font.render(text, True, (0, 0, 0))
            self.screen.blit(shadow_img, (x + 2, y + 2))
        
        img = font.render(text, True, text_col)
        self.screen.blit(img, (x, y))

    def update(self, mouse_pos):
        # Check if mouse moved to switch to mouse mode
        if pygame.mouse.get_rel() != (0, 0):
            self.is_keyboard_mode = False
            
        # Draw semi-transparent overlay
        overlay = pygame.Surface((self.width, self.height), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 150))
        self.screen.blit(overlay, (0, 0))
        
        # Draw pause menu text
        pause_text = "PAUSED"
        self.draw_text(pause_text, self.title_font, WHITE,
                      self.width // 2 - self.title_font.size(pause_text)[0] // 2, self.height // 4)
        
        # Update button focus in keyboard mode
        if self.is_keyboard_mode:
            for i, button in enumerate(self.buttons):
                button.is_focused = (i == self.current_button)
        
        # Update and draw buttons
        for button in self.buttons:
            button.update(mouse_pos, self.is_keyboard_mode)
            button.draw(self.screen)

    def handle_event(self, event):
        if event.type == pygame.KEYDOWN:
            self.is_keyboard_mode = True
            if event.key == pygame.K_ESCAPE:
                return "PLAYING"
            elif event.key in [pygame.K_w, pygame.K_UP] and self.current_button > 0:
                self.current_button -= 1
            elif event.key in [pygame.K_s, pygame.K_DOWN] and self.current_button < len(self.buttons) - 1:
                self.current_button += 1
            
            # Check for button activation
            if self.buttons[self.current_button].is_clicked(event):
                if self.current_button == 0:  # Continue button
                    return "PLAYING"
                else:  # Main Menu button
                    return "MAIN_MENU"
        
        # Handle mouse clicks
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.is_keyboard_mode = False
            if self.continue_button.is_clicked(event):
                return "PLAYING"
            elif self.menu_button.is_clicked(event):
                return "MAIN_MENU"
            
        return None