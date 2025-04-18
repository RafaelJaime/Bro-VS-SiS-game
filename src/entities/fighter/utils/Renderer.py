import pygame
import math
from src.utils.Colors import WHITE, YELLOW, GREEN, RED
from src.utils.ScreenShake import screen_shake

WIDTH, HEIGHT = 800, 600

class Renderer:
    def __init__(self):
        # Inicializar variables relacionadas con renderizado
        self.projectiles = []
        self.shoot_cooldown = 0
        self.screen_shake = screen_shake
        
    def draw(self, surface, camera_offset=[0, 0]):
        if self.is_defeated:
            # Draw defeated character (lying down)
            self.draw_defeated(surface, camera_offset)
        else:
            # Draw character with hit flash effect
            if self.hit_flash > 0 and self.hit_flash % 2 == 0:
                pygame.draw.rect(surface, WHITE, 
                                (self.rect.x + camera_offset[0], 
                                self.rect.y + camera_offset[1], 
                                self.rect.width, 
                                self.rect.height))
            else:
                pygame.draw.rect(surface, self.color, 
                                (self.rect.x + camera_offset[0], 
                                self.rect.y + camera_offset[1], 
                                self.rect.width, 
                                self.rect.height))
            
            # Dibujar el escudo si está protegido
            if hasattr(self, 'protecting') and self.protecting:
                # Crear un contorno brillante alrededor del jugador
                shield_color = (100, 200, 255, 128)  # Azul claro semitransparente
                shield_size = 4  # Grosor del escudo
                
                # Crear una superficie con transparencia para el escudo
                shield_surface = pygame.Surface(
                    (self.rect.width + shield_size * 2, self.rect.height + shield_size * 2), 
                    pygame.SRCALPHA
                )
                
                # Dibujar el contorno del escudo
                pygame.draw.rect(
                    shield_surface, 
                    shield_color, 
                    (0, 0, self.rect.width + shield_size * 2, self.rect.height + shield_size * 2),
                    shield_size
                )
                
                # Mostrar la superficie del escudo
                surface.blit(
                    shield_surface, 
                    (self.rect.x - shield_size + camera_offset[0], 
                    self.rect.y - shield_size + camera_offset[1])
                )
            
            # Draw attack hitbox if attacking
            if self.attacking:
                attack_rect = pygame.Rect(0, 0, 0, 0)
                if self.rect.centerx < WIDTH / 2:  # Facing right
                    attack_rect = pygame.Rect(self.rect.right, self.rect.y, 50, self.rect.height)
                else:  # Facing left
                    attack_rect = pygame.Rect(self.rect.left - 50, self.rect.y, 50, self.rect.height)
                
                # Create a surface with alpha for the attack zone
                s = pygame.Surface((attack_rect.width, attack_rect.height), pygame.SRCALPHA)
                #s.fill((0, 255, 0, 128))  # Semi-transparent green
                surface.blit(s, (attack_rect.x + camera_offset[0], attack_rect.y + camera_offset[1]))
        
        # Draw all particles
        for particle in self.particles:
            particle.draw(surface)
        
        # Draw projectiles
        for projectile in self.projectiles:
            projectile.draw(surface, camera_offset)
    
    def draw_defeated(self, surface, camera_offset=[0, 0]):
        # Animate the defeat sequence
        self.defeat_animation += 1
        max_animation = 60
        progress = min(self.defeat_animation / max_animation, 1)
        
        # Create a "lying down" rectangle
        height = self.rect.height // 3
        width = self.rect.width * 2
        
        # Position the defeated character lying on the ground
        x = self.rect.x - (width - self.rect.width) // 2
        y = HEIGHT - 50 - height
        
        # Draw the defeated character
        pygame.draw.rect(surface, self.color, 
                        (x + camera_offset[0], 
                        y + camera_offset[1], 
                        width, height))
        
        # Add some effects for the defeat state
        if self.defeat_animation < 30:
            # Draw little stars or birds around the head (cartoon style KO)
            for i in range(3):
                angle = (self.defeat_animation / 5 + i * (2*math.pi/3)) % (2*math.pi)
                star_x = x + width - 20 + math.cos(angle) * 15
                star_y = y - 10 + math.sin(angle) * 10
                
                pygame.draw.circle(surface, YELLOW, 
                                (int(star_x) + camera_offset[0], 
                                int(star_y) + camera_offset[1]), 3)
            
    def draw_health_bar(self, surface, x, y, width, height=15):
        # Draw background
        pygame.draw.rect(surface, (60, 60, 60), (x, y, width, height))
        pygame.draw.rect(surface, (40, 40, 40), (x, y, width, height), 1)
        
        # Calculate health bar width
        health_width = max(int(width * (self.health / 100)), 0)
        
        # Only draw health bar if there is health remaining
        if health_width > 0:
            # Draw health bar with gradient effect
            if self.health > 50:
                color = GREEN
            elif self.health > 25:
                color = YELLOW
            else:
                color = RED
                
            pygame.draw.rect(surface, color, (x, y, health_width, height))
            
            # Add highlight only if there is health
            highlight_height = height // 3
            if highlight_height > 0:  # Ensure highlight height is at least 1 pixel
                s = pygame.Surface((health_width, highlight_height), pygame.SRCALPHA)
                s.fill((255, 255, 255, 100))
                surface.blit(s, (x, y))