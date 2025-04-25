import pygame
import random
import math
from src.utils.Colors import WHITE, RED, BLUE, GREEN, YELLOW, ORANGE, PURPLE
from src.utils.Particle import Particle
from src.utils.Background import Background
from src.screens.Screen import Screen
from src.utils.GameState import GameState

class CharacterSelect(Screen):
    def __init__(self, screen, width, height):
        super().__init__(screen, width, height)
        
        # Character options with names, colors and stats
        self.characters = [
            {"color": BLUE, "name": "RYU"},
            {"color": GREEN, "name": "BLANKA"},
            {"color": YELLOW, "name": "GUILE"},
            {"color": PURPLE, "name": "JURI"},
            {"color": RED, "name": "KEN"},
            {"color": ORANGE, "name": "DHALSIM"},
        ]
        
        # Grid layout settings
        self.grid_cols = 3
        self.grid_rows = 3
        self.portrait_width = 80
        self.portrait_height = 100
        self.portrait_gap = 20
        
        # Calculate grid position to center it
        self.grid_width = self.grid_cols * self.portrait_width + (self.grid_cols - 1) * self.portrait_gap
        self.grid_height = self.grid_rows * self.portrait_height + (self.grid_rows - 1) * self.portrait_gap
        self.grid_start_x = (self.width - self.grid_width) // 2
        self.grid_start_y = 150
        
        # Character selection variables
        self.p1_selected = 0
        self.p2_selected = len(self.characters) - 1
        self.p1_locked = False
        self.p2_locked = False
        
        # Create background
        self.background = Background(width, height)
        
        # Create particles list
        self.particles = []

        # Keyboard navigation state
        self.is_keyboard_mode = False
    
    def reset(self):
        """Reinicia el estado de selección de personajes"""
        self.p1_locked = False
        self.p2_locked = False
        self.p1_selected = 0
        self.p2_selected = len(self.characters) - 1
        self.is_keyboard_mode = False
        # Limpiar partículas
        self.particles = []
    
    def handle_event(self, event) -> GameState:
        # Check if mouse moved to switch to mouse mode
        if pygame.mouse.get_rel() != (0, 0):
            self.is_keyboard_mode = False
        
        if event.type == pygame.QUIT:
            return GameState.EXIT
            
        if event.type == pygame.KEYDOWN:
            self.is_keyboard_mode = True
            
            if event.key == pygame.K_ESCAPE:
                return GameState.DIFFICULTY_SELECT
            
            # Player 1 controls
            if not self.p1_locked:
                if event.key == pygame.K_a:
                    self.p1_selected = (self.p1_selected - 1) % len(self.characters)
                    while self.p1_selected == self.p2_selected:
                        self.p1_selected = (self.p1_selected - 1) % len(self.characters)
                elif event.key == pygame.K_d:
                    self.p1_selected = (self.p1_selected + 1) % len(self.characters)
                    while self.p1_selected == self.p2_selected:
                        self.p1_selected = (self.p1_selected + 1) % len(self.characters)
                elif event.key == pygame.K_w:
                    self.p1_selected = (self.p1_selected - self.grid_cols) % len(self.characters)
                    while self.p1_selected == self.p2_selected:
                        self.p1_selected = (self.p1_selected - self.grid_cols) % len(self.characters)
                elif event.key == pygame.K_s:
                    self.p1_selected = (self.p1_selected + self.grid_cols) % len(self.characters)
                    while self.p1_selected == self.p2_selected:
                        self.p1_selected = (self.p1_selected + self.grid_cols) % len(self.characters)
            
            # Player 2 controls
            if not self.p2_locked:
                if event.key == pygame.K_LEFT:
                    self.p2_selected = (self.p2_selected - 1) % len(self.characters)
                    while self.p2_selected == self.p1_selected:
                        self.p2_selected = (self.p2_selected - 1) % len(self.characters)
                elif event.key == pygame.K_RIGHT:
                    self.p2_selected = (self.p2_selected + 1) % len(self.characters)
                    while self.p2_selected == self.p1_selected:
                        self.p2_selected = (self.p2_selected + 1) % len(self.characters)
                elif event.key == pygame.K_UP:
                    self.p2_selected = (self.p2_selected - self.grid_cols) % len(self.characters)
                    while self.p2_selected == self.p1_selected:
                        self.p2_selected = (self.p2_selected - self.grid_cols) % len(self.characters)
                elif event.key == pygame.K_DOWN:
                    self.p2_selected = (self.p2_selected + self.grid_cols) % len(self.characters)
                    while self.p2_selected == self.p1_selected:
                        self.p2_selected = (self.p2_selected + self.grid_cols) % len(self.characters)
            
            # Lock selections
            if event.key == pygame.K_f:
                self.p1_locked = True
            if event.key == pygame.K_k:
                self.p2_locked = True
            
            # Start game when both players are locked
            if self.p1_locked and self.p2_locked:
                return GameState.PLAYERS_SELECTED
                
        return None
    
    def get_player_selection(self):
        """Return the selected players configuration"""
        if self.p1_locked and self.p2_locked:
            return (
                self.characters[self.p1_selected]["color"], 
                self.characters[self.p2_selected]["color"], 
                self.characters[self.p1_selected]["name"], 
                self.characters[self.p2_selected]["name"]
            )
        return None
    
    def update(self, mouse_pos):
        # Check if mouse moved to switch to mouse mode
        self.check_mouse_movement()

        # Draw background using Background class
        self.background.draw(self.screen)
        self.background.update()
        
        # Draw UI panel at the top
        pygame.draw.rect(self.screen, (30, 30, 40), (0, 0, self.width, 80))
        pygame.draw.line(self.screen, (70, 70, 80), (0, 80), (self.width, 80), 2)
        
        # Draw title
        title_text = "SELECT YOUR FIGHTER"
        self.draw_text(title_text, self.title_font, WHITE,
                 self.width // 2 - self.title_font.size(title_text)[0] // 2, 15)
        
        # Draw control instructions
        controls_text = "P1: WASD to move, F to lock  |  P2: ←↑↓→ to move, K to lock"
        self.draw_text(controls_text, self.info_font, WHITE, 
                 self.width // 2 - self.info_font.size(controls_text)[0] // 2, 85)
        
        # Draw character grid
        for i, character in enumerate(self.characters):
            row = i // self.grid_cols
            col = i % self.grid_cols
            portrait_x = self.grid_start_x + col * (self.portrait_width + self.portrait_gap)
            portrait_y = self.grid_start_y + row * (self.portrait_height + self.portrait_gap)
            
            # Draw portrait background
            pygame.draw.rect(self.screen, (50, 50, 60), 
                            (portrait_x, portrait_y, self.portrait_width, self.portrait_height))
            
            # Draw character silhouette
            pygame.draw.rect(self.screen, character["color"], 
                            (portrait_x + 10, portrait_y + 10, self.portrait_width - 20, self.portrait_height - 40))
            
            # Draw character name
            name_text = character["name"]
            name_surface = self.info_font.render(name_text, True, WHITE)
            name_rect = name_surface.get_rect(centerx=portrait_x + self.portrait_width // 2, y=portrait_y + self.portrait_height - 25)
            self.screen.blit(name_surface, name_rect)
            
            # Draw selection frames
            if i == self.p1_selected:
                frame_color = BLUE if not self.p1_locked else (0, 255, 0)
                pygame.draw.rect(self.screen, frame_color, 
                                (portrait_x - 4, portrait_y - 4, self.portrait_width + 8, self.portrait_height + 8), 3)
                self.draw_text("P1", self.info_font, frame_color, portrait_x + self.portrait_width // 2 - 10, portrait_y - 25)
            
            if i == self.p2_selected:
                frame_color = RED if not self.p2_locked else (0, 255, 0)
                pygame.draw.rect(self.screen, frame_color, 
                                (portrait_x - 4, portrait_y - 4, self.portrait_width + 8, self.portrait_height + 8), 3)
                self.draw_text("P2", self.info_font, frame_color, portrait_x + self.portrait_width // 2 - 10, portrait_y - 25)
        
        # Draw large character previews on left and right sides
        preview_width = 200
        preview_height = 400
        p1_preview_rect = pygame.Rect(0, self.height//2 - preview_height//2, preview_width, preview_height)
        self.draw_character_preview(p1_preview_rect, self.characters[self.p1_selected]["color"], 
                               self.characters[self.p1_selected]["name"], 
                               BLUE if not self.p1_locked else (0, 255, 0))
        
        p2_preview_rect = pygame.Rect(self.width - preview_width, self.height//2 - preview_height//2, preview_width, preview_height)
        self.draw_character_preview(p2_preview_rect, self.characters[self.p2_selected]["color"], 
                               self.characters[self.p2_selected]["name"], 
                               RED if not self.p2_locked else (0, 255, 0))
        
        # Draw particles
        for particle in self.particles:
            particle.draw(self.screen)
        self.update_particles()
        
        # Draw ESC instruction
        esc_text = "Press ESC to go back"
        self.draw_text(esc_text, self.info_font, (200, 200, 200),
                 self.width // 2 - self.info_font.size(esc_text)[0] // 2, self.height - 30)
    
    def draw_character_preview(self, rect, color, name, player_color):
        # Draw frame background with gradient effect
        gradient_rect = pygame.Surface((rect.width, rect.height), pygame.SRCALPHA)
        for y in range(rect.height):
            alpha = max(150 - y//3, 30)
            pygame.draw.line(gradient_rect, (*player_color[:3], alpha), (0, y), (rect.width, y))
        self.screen.blit(gradient_rect, (rect.x, rect.y))
        
        # Draw outer border
        pygame.draw.rect(self.screen, player_color, rect, 4, border_radius=5)
        
        # Draw character silhouette
        char_width = rect.width - 40
        char_height = rect.height - 100
        char_x = rect.x + (rect.width - char_width) // 2
        char_y = rect.y + 30
        
        # Draw the character with slightly different proportions
        # Head
        head_size = char_width // 2
        pygame.draw.rect(self.screen, color, 
                       (char_x + char_width//4, char_y, head_size, head_size))
        
        # Body
        body_width = char_width - 20
        body_height = char_height - head_size - 20
        pygame.draw.rect(self.screen, color, 
                       (char_x + 10, char_y + head_size + 10, body_width, body_height))
        
        # Add some shading/highlights
        highlight = (min(color[0] + 50, 255), min(color[1] + 50, 255), min(color[2] + 50, 255))
        pygame.draw.rect(self.screen, highlight, 
                       (char_x + char_width//4, char_y, head_size//2, 5))
        pygame.draw.rect(self.screen, highlight, 
                       (char_x + 10, char_y + head_size + 10, 5, body_height))
        
        # Draw character name plate at bottom
        name_plate_height = 40
        pygame.draw.rect(self.screen, (20, 20, 25), 
                        (rect.x, rect.y + rect.height - name_plate_height, rect.width, name_plate_height),
                        border_radius=5)
        pygame.draw.rect(self.screen, player_color, 
                        (rect.x, rect.y + rect.height - name_plate_height, rect.width, name_plate_height),
                        2, border_radius=5)
        
        # Draw name
        name_font = pygame.font.SysFont('Arial', 24, True)
        name_surface = name_font.render(name, True, WHITE)
        name_rect = name_surface.get_rect(center=(rect.x + rect.width // 2, rect.y + rect.height - name_plate_height // 2))
        self.screen.blit(name_surface, name_rect)

    def add_selection_particles(self, x, y, color):
        for _ in range(15):
            angle = random.uniform(0, 2 * 3.14159)
            speed = random.uniform(1, 5)
            vel_x = math.cos(angle) * speed
            vel_y = math.sin(angle) * speed
            size = random.uniform(2, 6)
            lifetime = random.randint(20, 40)
            
            # Create particles with color variation
            r, g, b = color
            r_var = max(0, min(255, r + random.randint(-30, 30)))
            g_var = max(0, min(255, g + random.randint(-30, 30)))
            b_var = max(0, min(255, b + random.randint(-30, 30)))
            
            self.particles.append(Particle(x, y, (r_var, g_var, b_var), size, (vel_x, vel_y), True, lifetime))

    def update_particles(self):
        i = 0
        while i < len(self.particles):
            if self.particles[i].update():
                self.particles.pop(i)
            else:
                i += 1
