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
            # Usar imágenes si lowResources es falso y hay animaciones disponibles
            if hasattr(self, 'lowResources') and not self.lowResources and hasattr(self, 'fighter_bo') and self.fighter_bo.has_animations():
                self._draw_animated(surface, camera_offset)
            else:
                # Draw character with hit flash effect (versión con rectángulos)
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
            
            # Draw attack windup rectangle if it exists and timer is active
            if hasattr(self, 'attack_windup_rect') and hasattr(self, 'attack_windup_timer') and self.attack_windup_timer > 0:
                # Create a surface with alpha for the attack windup zone
                windup_surface = pygame.Surface((self.attack_windup_rect.width, self.attack_windup_rect.height), pygame.SRCALPHA)
                
                # Use the fighter's color with transparency
                alpha = int(255 * (self.attack_windup_timer / 10))  # Fade out as timer decreases
                rgba_color = (*self.color, alpha)
                windup_surface.fill(rgba_color)
                
                # Draw the attack windup rectangle
                surface.blit(windup_surface, 
                           (self.attack_windup_rect.x + camera_offset[0], 
                            self.attack_windup_rect.y + camera_offset[1]))
                
                # Decrease the timer
                self.attack_windup_timer -= 1
            
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
        
        # Draw all particles only if lowResources está desactivado
        if not hasattr(self, 'lowResources') or not self.lowResources:
            for particle in self.particles:
                particle.draw(surface)
        
        # Draw projectiles
        for projectile in self.projectiles:
            projectile.draw(surface, camera_offset)
    
    def _draw_animated(self, surface, camera_offset=[0, 0]):
        """
        Dibuja al luchador usando las imágenes de animación
        """
        # Obtener el frame actual de la animación
        frames = self.fighter_bo.get_animation_frames(self.current_action)
        if not frames:
            # Si no hay frames para esta acción, intentar usar frames de 'idle'
            frames = self.fighter_bo.get_animation_frames('idle')
            # Si aún no hay frames, usar rectángulos simples
            if not frames:
                pygame.draw.rect(surface, self.color, 
                               (self.rect.x + camera_offset[0], 
                                self.rect.y + camera_offset[1], 
                                self.rect.width, 
                                self.rect.height))
                return
        
        # Obtener el frame actual como un entero
        frame_index = int(self.current_frame) % len(frames)
        current_frame = frames[frame_index]
        
        # Dar la vuelta a la imagen si es necesario
        if not self.facing_right:
            current_frame = pygame.transform.flip(current_frame, True, False)
        
        # Aplicar efecto de flasheo si ha sido golpeado
        if self.hit_flash > 0 and self.hit_flash % 2 == 0:
            # Crear una copia del frame y hacerlo blanco
            white_frame = current_frame.copy()
            white_frame.fill((255, 255, 255), None, pygame.BLEND_RGB_MAX)
            current_frame = white_frame
        
        # Calcular la posición para dibujar la imagen (centrada en el rectángulo del luchador)
        img_rect = current_frame.get_rect()
        img_rect.midbottom = (self.rect.centerx + camera_offset[0], 
                              self.rect.bottom + camera_offset[1])
        
        # Dibujar la imagen
        surface.blit(current_frame, img_rect)
    
    def draw_defeated(self, surface, camera_offset=[0, 0]):
        # Siempre incrementar la animación de derrota, independientemente del modo de recursos
        self.defeat_animation += 1
        max_animation = 60
        progress = min(self.defeat_animation / max_animation, 1)
        
        # Si hay animación de derrota disponible, usarla
        if hasattr(self, 'lowResources') and not self.lowResources and hasattr(self, 'fighter_bo'):
            frames = self.fighter_bo.get_animation_frames('defeated')
            if frames:
                # Usar la animación de derrota (ahora usando current_frame que es controlado por Fighter)
                frame_index = int(self.current_frame) % len(frames)
                current_frame = frames[frame_index]
                
                # Crear un rectángulo para la posición de la imagen
                img_rect = current_frame.get_rect()
                img_rect.bottomleft = (self.rect.x + camera_offset[0], HEIGHT - 50 + camera_offset[1])
                
                # Dibujar la imagen
                surface.blit(current_frame, img_rect)
                
                # Añadir efectos de estrellas si es necesario
                if self.defeat_animation < 30:
                    for i in range(3):
                        angle = (self.defeat_animation / 5 + i * (2*math.pi/3)) % (2*math.pi)
                        star_x = img_rect.right - 20 + math.cos(angle) * 15
                        star_y = img_rect.top - 10 + math.sin(angle) * 10
                        
                        pygame.draw.circle(surface, YELLOW, 
                                        (int(star_x), int(star_y)), 3)
                return
        
        # Usar la versión con rectángulos si no hay animación disponible
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