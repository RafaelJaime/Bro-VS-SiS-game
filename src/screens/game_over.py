import pygame
from src.Button import Button
from src.Colors import WHITE

class GameOver:
    def __init__(self, screen, width, height):
        self.screen = screen
        self.width = width
        self.height = height
        self.title_font = pygame.font.SysFont('Arial', 60, True)
        
        # Create buttons
        self.restart_button = Button(width // 2 - 160, height // 2, 140, 50, 
                                   "Restart", (70, 130, 180), (100, 160, 210))
        self.menu_button = Button(width // 2 + 20, height // 2, 140, 50, 
                                "Main Menu", (180, 70, 70), (210, 100, 100))

    def draw_text(self, text, font, text_col, x, y, shadow=True):
        if shadow:
            shadow_img = font.render(text, True, (0, 0, 0))
            self.screen.blit(shadow_img, (x + 2, y + 2))
        
        img = font.render(text, True, text_col)
        self.screen.blit(img, (x, y))

    def update(self, mouse_pos, winner):
        # Draw semi-transparent overlay
        overlay = pygame.Surface((self.width, self.height), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, 150))
        self.screen.blit(overlay, (0, 0))
        
        # Draw victory text
        victory_text = f"{winner.name} Wins!"
        self.draw_text(victory_text, self.title_font, winner.color,
                      self.width // 2 - self.title_font.size(victory_text)[0] // 2, 
                      self.height // 2 - 100)
        
        # Update and draw buttons
        self.restart_button.update(mouse_pos)
        self.menu_button.update(mouse_pos)
        self.restart_button.draw(self.screen)
        self.menu_button.draw(self.screen)

    def handle_event(self, event):
        if self.restart_button.is_clicked(event):
            return "PLAYING"
        elif self.menu_button.is_clicked(event):
            return "MAIN_MENU"
        return None