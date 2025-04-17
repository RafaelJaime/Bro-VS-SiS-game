import pygame
import random
from src.entities.fighter.Fighter import Fighter
from src.utils.Colors import BLACK, WHITE, RED, BLUE
from src.utils.ScreenShake import screen_shake

class GamePlay:
    def __init__(self, screen, width, height):
        self.screen = screen
        self.width = width
        self.height = height
        self.font = pygame.font.SysFont('Arial', 30)
        
        # Create ground
        self.ground = pygame.Rect(0, height - 50, width, 50)
        
        # Create fighters
        self.player1_controls = {
            'left': pygame.K_a,
            'right': pygame.K_d,
            'up': pygame.K_w,
            'attack': pygame.K_f
        }
        
        self.player2_controls = {
            'left': pygame.K_LEFT,
            'right': pygame.K_RIGHT,
            'up': pygame.K_UP,
            'attack': pygame.K_k
        }
        
        self.player1 = Fighter(100, height - 150, 50, 100, BLUE, self.player1_controls, "Player 1")
        self.player2 = Fighter(700, height - 150, 50, 100, RED, self.player2_controls, "Player 2")
        
        # Timer variables
        self.match_timer = 60 * 60  # 60 seconds at 60fps
        self.sudden_death = False
        self.timer_font = pygame.font.SysFont('Arial', 40)
        
        # Create background stars
        self.stars = []
        for _ in range(80):
            x = random.randint(0, width)
            y = random.randint(0, height - 50)
            size = random.uniform(0.5, 2)
            brightness = random.randint(100, 255)
            color = (brightness, brightness, brightness)
            self.stars.append([x, y, size, color])

    def draw_text(self, text, font, text_col, x, y, shadow=True):
        if shadow:
            shadow_img = font.render(text, True, BLACK)
            self.screen.blit(shadow_img, (x + 2, y + 2))
        
        img = font.render(text, True, text_col)
        self.screen.blit(img, (x, y))

    def update(self, game_mode):
        # Update screen shake
        camera_offset = screen_shake.update()
        
        # Draw background
        self.screen.fill(BLACK)
        
        # Draw stars
        for star in self.stars:
            pygame.draw.circle(self.screen, star[3], (star[0] + camera_offset[0], star[1] + camera_offset[1]), star[2])
        
        # Draw ground with offset
        pygame.draw.rect(self.screen, WHITE, (self.ground.x + camera_offset[0], 
                                            self.ground.y + camera_offset[1], 
                                            self.ground.width, 
                                            self.ground.height))
        
        # Add ground texture
        for x in range(0, self.width, 20):
            height_var = random.randint(-2, 2)
            pygame.draw.line(self.screen, (200, 200, 200), 
                           (x + camera_offset[0], self.height - 50 + camera_offset[1]), 
                           (x + camera_offset[0], self.height - 15 + height_var + camera_offset[1]), 2)
        
        # Draw fighters
        self.player1.draw(self.screen, camera_offset)
        self.player2.draw(self.screen, camera_offset)
        
        # Only move fighters if neither is defeated
        if not self.player1.is_defeated and not self.player2.is_defeated:
            self.player1.move(self.player2)
            self.player2.move(self.player1)
        else:
            # Still update particles when a player is defeated
            self.player1.update_particles()
            self.player2.update_particles()
        
        # Draw UI panel at the top
        pygame.draw.rect(self.screen, (30, 30, 30), (0, 0, self.width, 60))
        pygame.draw.line(self.screen, (70, 70, 70), (0, 60), (self.width, 60), 2)
        
        # Draw player names and scores
        self.draw_text(f"{self.player1.name}", self.font, self.player1.color, 20, 10)
        self.draw_text(f"{self.player2.name}", self.font, self.player2.color, self.width - 150, 10)
        
        # Draw health bars
        health_bar_width = 200
        self.player1.draw_health_bar(self.screen, 150, 18, health_bar_width)
        self.player2.draw_health_bar(self.screen, self.width - 350, 18, health_bar_width)
        
        # Draw controls info based on game mode
        if game_mode == 0:  # PVP
            self.draw_text("P1: WASD + F attack + G shoot", self.font, WHITE, 20, self.height - 40)
            self.draw_text("P2: Arrows + K attack + L shoot", self.font, WHITE, self.width - 380, self.height - 40)
        elif game_mode == 1:  # PVC
            self.draw_text("Controls: WASD + F attack + G shoot", self.font, WHITE, 20, self.height - 40)
        elif game_mode == 2:  # CVC
            self.draw_text("AI Battle - Press ESC to exit", self.font, WHITE, self.width // 2 - 150, self.height - 40)
        
        # Update and draw timer
        if not self.player1.is_defeated and not self.player2.is_defeated:
            self.match_timer -= 1
            
        if self.match_timer <= 0 and not self.sudden_death:
            self.sudden_death = True
            self.player1.health = 1
            self.player2.health = 1
            self.player1.sudden_death_mode = True
            self.player2.sudden_death_mode = True
            screen_shake.start(10)  # Añadir un efecto para indicar el inicio de muerte súbita
            self.match_timer = 0  # Evitar que el contador se vuelva negativo
            
        # Mostrar timer
        timer_text = f"{max(self.match_timer // 60, 0):02}"  # Usar max para evitar números negativos
        timer_color = RED if self.sudden_death or self.match_timer < 600 else WHITE
        self.draw_text(timer_text, self.timer_font, timer_color, self.width // 2 - 20, 10)
        
        # Mostrar mensaje de muerte súbita centrado
        if self.sudden_death:
            sudden_death_text = "¡MUERTE SÚBITA!"
            text_width = self.timer_font.size(sudden_death_text)[0]
            center_x = (self.width - text_width) // 2
            self.draw_text(sudden_death_text, self.timer_font, RED, center_x, 80)

    def handle_event(self, event):
        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            return "PAUSE"
        
        # Check if game is over
        if self.player1.is_defeated or self.player2.is_defeated:
            if ((self.player1.is_defeated and self.player1.defeat_animation > 60) or 
                (self.player2.is_defeated and self.player2.defeat_animation > 60)):
                return "GAME_OVER"
        
        return None

    def get_winner(self):
        return self.player2 if self.player1.is_defeated else self.player1

    def reset_game(self):
        self.player1.health = 100
        self.player2.health = 100
        self.player1.is_defeated = False
        self.player2.is_defeated = False
        self.player1.defeat_animation = 0
        self.player2.defeat_animation = 0
        self.player1.rect.x = 100
        self.player2.rect.x = 700
        self.player1.rect.y = self.height - 150
        self.player2.rect.y = self.height - 150
        self.match_timer = 60 * 60  # Reset timer
        self.sudden_death = False

    def set_player_colors(self, p1_color, p2_color):
        """Update the colors of both players"""
        self.player1.color = p1_color
        self.player2.color = p2_color

    def set_ai_mode(self, game_mode):
        """Set AI mode based on game mode (0=PVP, 1=PVC, 2=CVC)"""
        if game_mode == 1:  # PVC
            self.player2.is_ai = True
            self.player1.is_ai = False
        elif game_mode == 2:  # CVC
            self.player1.is_ai = True
            self.player2.is_ai = True
        else:  # PVP
            self.player1.is_ai = False
            self.player2.is_ai = False

    def check_game_over(self):
        """Check if the game is over and one player has been defeated"""
        if self.player1.is_defeated or self.player2.is_defeated:
            if ((self.player1.is_defeated and self.player1.defeat_animation > 60) or 
                (self.player2.is_defeated and self.player2.defeat_animation > 60)):
                return True
        return False