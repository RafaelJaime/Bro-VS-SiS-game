import pygame
from src.utils.Button import Button
from src.utils.Colors import WHITE, BLACK
from src.utils.Background import Background

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

        # Button navigation
        self.buttons = [self.pvp_button, self.pvc_button, self.cvc_button, self.back_button]
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
                return ("MAIN_MENU", None)
            elif event.key in [pygame.K_w, pygame.K_UP] and self.current_button > 0:
                self.current_button -= 1
            elif event.key in [pygame.K_s, pygame.K_DOWN] and self.current_button < len(self.buttons) - 1:
                self.current_button += 1
            
            # Check for button activation
            if self.buttons[self.current_button].is_clicked(event):
                if self.current_button == 0:
                    return ("CHARACTER_SELECT", 0)  # PVP
                elif self.current_button == 1:
                    return ("CHARACTER_SELECT", 1)  # PVC
                elif self.current_button == 2:
                    return ("CHARACTER_SELECT", 2)  # CVC
                else:
                    return ("MAIN_MENU", None)  # Back button
        
        # Handle mouse clicks
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.is_keyboard_mode = False
            if self.pvp_button.is_clicked(event):
                return ("CHARACTER_SELECT", 0)
            elif self.pvc_button.is_clicked(event):
                return ("CHARACTER_SELECT", 1)
            elif self.cvc_button.is_clicked(event):
                return ("CHARACTER_SELECT", 2)
            elif self.back_button.is_clicked(event):
                return ("MAIN_MENU", None)
            
        return None