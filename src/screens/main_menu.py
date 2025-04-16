import pygame
from src.Button import Button
from src.Colors import WHITE, BLACK
from src.Background import Background

class MainMenu:
    def __init__(self, screen, width, height):
        self.screen = screen
        self.width = width
        self.height = height
        self.title_font = pygame.font.SysFont('Arial', 60, True)
        self.subtitle_font = pygame.font.SysFont('Arial', 30)
        self.small_font = pygame.font.SysFont('Arial', 20)
        
        # Create background
        self.background = Background(width, height)
        
        # Create buttons
        self.start_button = Button(width // 2 - 75, height // 2, 150, 50, "Start Game", (70, 130, 180), (100, 160, 210))
        self.exit_button = Button(width // 2 - 75, height // 2 + 70, 150, 50, "Exit", (180, 70, 70), (210, 100, 100))
        
        # Button navigation
        self.buttons = [self.start_button, self.exit_button]
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
        title_text = "PYGAME FIGHTER"
        self.draw_text(title_text, self.title_font, WHITE, 
                      self.width // 2 - self.title_font.size(title_text)[0] // 2, self.height // 4)
        
        # Draw subtitle
        subtitle_text = "The Ultimate Battle"
        self.draw_text(subtitle_text, self.subtitle_font, (200, 200, 200),
                      self.width // 2 - self.subtitle_font.size(subtitle_text)[0] // 2, self.height // 4 + 70)
        
        # Update button focus in keyboard mode
        if self.is_keyboard_mode:
            for i, button in enumerate(self.buttons):
                button.is_focused = (i == self.current_button)
        
        # Update and draw buttons
        for button in self.buttons:
            button.update(mouse_pos, self.is_keyboard_mode)
            button.draw(self.screen)
        
        # Draw credits
        credit_text = "Use WASD/Arrows to move, F/K to attack, G/L to shoot"
        self.draw_text(credit_text, self.small_font, (200, 200, 200),
                      self.width // 2 - self.small_font.size(credit_text)[0] // 2, self.height - 30)

    def handle_event(self, event):
        if event.type == pygame.KEYDOWN:
            self.is_keyboard_mode = True
            if event.key in [pygame.K_w, pygame.K_UP] and self.current_button > 0:
                self.current_button -= 1
            elif event.key in [pygame.K_s, pygame.K_DOWN] and self.current_button < len(self.buttons) - 1:
                self.current_button += 1
            
            # Check for button activation
            if self.buttons[self.current_button].is_clicked(event):
                if self.current_button == 0:  # Start button
                    return "DIFFICULTY_SELECT"
                else:  # Exit button
                    return "EXIT"
        
        # Handle mouse clicks
        if event.type == pygame.MOUSEBUTTONDOWN:
            self.is_keyboard_mode = False
            if self.start_button.is_clicked(event):
                return "DIFFICULTY_SELECT"
            elif self.exit_button.is_clicked(event):
                return "EXIT"
        
        return None