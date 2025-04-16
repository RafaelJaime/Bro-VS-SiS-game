import pygame
from src.Colors import WHITE

# Button class for menus
class Button:
    def __init__(self, x, y, width, height, text, color, hover_color, text_color=WHITE):
        self.rect = pygame.Rect(x, y, width, height)
        self.text = text
        self.color = color
        self.hover_color = hover_color
        self.text_color = text_color
        self.current_color = color
        self.is_hovered = False
        self.is_focused = False  # New keyboard focus state
        self.font = pygame.font.SysFont('Arial', 24)
    
    def update(self, mouse_pos, is_keyboard_mode=False):
        if not is_keyboard_mode:
            self.is_hovered = self.rect.collidepoint(mouse_pos)
        self.current_color = self.hover_color if (self.is_hovered or self.is_focused) else self.color
    
    def draw(self, surface):
        # Draw button background with rounded corners effect
        pygame.draw.rect(surface, self.current_color, self.rect, border_radius=5)
        pygame.draw.rect(surface, (50, 50, 50), self.rect, 2, border_radius=5)
        
        # Draw highlight on top edge when hovered or focused
        if self.is_hovered or self.is_focused:
            highlight_rect = pygame.Rect(self.rect.x + 2, self.rect.y + 2, self.rect.width - 4, 5)
            pygame.draw.rect(surface, (255, 255, 255, 120), highlight_rect, border_radius=2)
        
        # Draw text
        text_surface = self.font.render(self.text, True, self.text_color)
        text_rect = text_surface.get_rect(center=self.rect.center)
        surface.blit(text_surface, text_rect)
    
    def is_clicked(self, event):
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            return self.is_hovered
        elif event.type == pygame.KEYDOWN and (event.key in [pygame.K_RETURN, pygame.K_f, pygame.K_k]):
            return self.is_focused
        return False