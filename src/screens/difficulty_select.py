import pygame
from src.Button import Button
from src.Colors import WHITE, BLACK
from src.Background import Background

class DifficultySelect:
    def __init__(self, screen, width, height):
        self.screen = screen
        self.width = width
        self.height = height
        self.title_font = pygame.font.SysFont('Arial', 60, True)
        self.subtitle_font = pygame.font.SysFont('Arial', 24)

        # Create background
        self.background = Background(width, height)

        # Create buttons
        self.pvp_button = Button(width // 2 - 200, height // 2 - 50, 400, 50, "Player vs Player", (70, 130, 180), (100, 160, 210))
        self.pvc_button = Button(width // 2 - 200, height // 2 + 20, 400, 50, "Player vs Computer", (70, 180, 130), (100, 210, 160))
        self.cvc_button = Button(width // 2 - 200, height // 2 + 90, 400, 50, "Computer vs Computer", (130, 70, 180), (160, 100, 210))
        self.back_button = Button(width // 2 - 75, height // 2 + 160, 150, 50, "Back", (180, 70, 70), (210, 100, 100))

    def draw_text(self, text, font, text_col, x, y, shadow=True):
        if shadow:
            shadow_img = font.render(text, True, (0, 0, 0))
            self.screen.blit(shadow_img, (x + 2, y + 2))
        
        img = font.render(text, True, text_col)
        self.screen.blit(img, (x, y))

    def update(self, mouse_pos):
        # Draw background
        self.background.draw(self.screen)
        
        # Draw title
        title_text = "SELECT GAME MODE"
        self.draw_text(title_text, self.title_font, WHITE,
                      self.width // 2 - self.title_font.size(title_text)[0] // 2, self.height // 4)
        
        # Draw subtitle
        subtitle_text = "Choose your battle mode"
        self.draw_text(subtitle_text, self.subtitle_font, (200, 200, 200),
                      self.width // 2 - self.subtitle_font.size(subtitle_text)[0] // 2, self.height // 4 + 70)
        
        # Draw ESC instruction
        esc_text = "Press ESC to go back"
        self.draw_text(esc_text, self.subtitle_font, (200, 200, 200),
                      self.width // 2 - self.subtitle_font.size(esc_text)[0] // 2, self.height - 30)
        
        # Update and draw buttons
        self.pvp_button.update(mouse_pos)
        self.pvc_button.update(mouse_pos)
        self.cvc_button.update(mouse_pos)
        self.back_button.update(mouse_pos)
        
        self.pvp_button.draw(self.screen)
        self.pvc_button.draw(self.screen)
        self.cvc_button.draw(self.screen)
        self.back_button.draw(self.screen)

    def handle_event(self, event):
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return ("MAIN_MENU", None)
            
        if self.pvp_button.is_clicked(event):
            return ("CHARACTER_SELECT", 0)  # 0 = MODE_PVP
        elif self.pvc_button.is_clicked(event):
            return ("CHARACTER_SELECT", 1)  # 1 = MODE_PVC
        elif self.cvc_button.is_clicked(event):
            return ("CHARACTER_SELECT", 2)  # 2 = MODE_CVC
        elif self.back_button.is_clicked(event):
            return ("MAIN_MENU", None)
        return None