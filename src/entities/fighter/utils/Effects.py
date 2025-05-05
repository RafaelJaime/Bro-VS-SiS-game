import random
import math
import pygame
from src.utils.Particle import Particle
from src.utils.Colors import YELLOW, ORANGE, RED, WHITE

class Effects:
    def __init__(self):
        # Inicializar variables relacionadas con efectos visuales
        self.particles = []
        self.hit_flash = 0
        self.hit_flash_max = 5
        
    def add_shoot_effect(self, direction):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        # Add particles for shoot effect
        for _ in range(10):
            angle = random.uniform(-0.5, 0.5) + (0 if direction > 0 else math.pi)
            speed = random.uniform(2, 6)
            vel_x = math.cos(angle) * speed
            vel_y = math.sin(angle) * speed
            
            color = self.color if random.random() < 0.6 else self.secondary_color
            
            self.particles.append(Particle(
                self.rect.centerx + (direction * self.rect.width/2),
                self.rect.centery,
                color,
                random.uniform(2, 4),
                (vel_x, vel_y),
                False,
                15
            ))

    def add_attack_windup_effect(self, opponent):
        # Direction of attack based on opponent position, same as attack method
        if self.rect.centerx < opponent.rect.centerx:  # Facing right
            direction = 1
        else:  # Facing left
            direction = -1

        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            # Create attack rectangle indicator
            attack_rect_width = 50
            attack_rect_height = self.rect.height
            
            # Position the attack rectangle based on player orientation
            if direction > 0:  # Facing right
                attack_rect_x = self.rect.right
                attack_rect_y = self.rect.y
            else:  # Facing left
                attack_rect_x = self.rect.left - attack_rect_width
                attack_rect_y = self.rect.y
            
            # Store the attack rectangle as an attribute so it can be rendered
            self.attack_windup_rect = pygame.Rect(attack_rect_x, attack_rect_y, attack_rect_width, attack_rect_height)
            
            # Set a timer for how long to display the rectangle (in frames)
            self.attack_windup_timer = 10  # Display for 10 frames
        
        
        # Create swipe effect particles
        for i in range(10):
            angle = math.pi * 0.25 * direction
            speed = random.uniform(3, 7)
            vel_x = math.cos(angle) * speed * direction
            vel_y = math.sin(angle) * speed
            
            size = random.uniform(2, 5)
            lifetime = random.randint(5, 15)
            color = self.color if random.random() < 0.6 else self.secondary_color
            
            offset_x = direction * self.rect.width / 2
            
            self.particles.append(Particle(
                self.rect.centerx + offset_x, 
                self.rect.centery - self.rect.height / 4, 
                self.color, size, (vel_x, vel_y), False, lifetime
            ))

    def add_dust_particle(self, x, y):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        for _ in range(2):
            vel_x = random.uniform(-1, 1)
            vel_y = random.uniform(-2, -0.5)
            size = random.uniform(1, 3)
            lifetime = random.randint(20, 40)
            color = (200, 200, 200)
            self.particles.append(Particle(x, y, color, size, (vel_x, vel_y), True, lifetime))
    
    def add_jump_effect(self):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        for _ in range(10):
            vel_x = random.uniform(-2, 2)
            vel_y = random.uniform(0, 4)
            size = random.uniform(1, 4)
            lifetime = random.randint(10, 30)
            color = (200, 200, 200)
            self.particles.append(Particle(
                self.rect.centerx, 
                self.rect.bottom, 
                color, size, (vel_x, vel_y), True, lifetime
            ))
    
    def add_landing_effect(self):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        for _ in range(15):
            vel_x = random.uniform(-3, 3)
            vel_y = random.uniform(-4, -1)
            size = random.uniform(2, 4)
            lifetime = random.randint(20, 40)
            color = (200, 200, 200)
            self.particles.append(Particle(
                self.rect.centerx, 
                self.rect.bottom, 
                color, size, (vel_x, vel_y), True, lifetime
            ))
    
    def add_hit_effect(self, x, y):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        # Circular hit effect
        for _ in range(20):
            angle = random.uniform(0, math.pi * 2)
            speed = random.uniform(2, 8)
            vel_x = math.cos(angle) * speed
            vel_y = math.sin(angle) * speed
            
            size = random.uniform(2, 5)
            lifetime = random.randint(10, 30)
            
            # Use attacker's color and some variations
            if random.random() < 0.7:
                color = self.color
            else:
                color = self.secondary_color
            
            self.particles.append(Particle(x, y, self.color, size, (vel_x, vel_y), False, lifetime))
    
    def add_ko_effect(self, x, y):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        # Explosion effect for KO
        for _ in range(40):
            angle = random.uniform(0, math.pi * 2)
            speed = random.uniform(3, 10)
            vel_x = math.cos(angle) * speed
            vel_y = math.sin(angle) * speed
            
            size = random.uniform(3, 8)
            lifetime = random.randint(30, 60)
            
            color = random.choice([YELLOW, ORANGE, RED, WHITE])
            
            self.particles.append(Particle(x, y, color, size, (vel_x, vel_y), True, lifetime))
            
    def add_collision_effect(self, opponent):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        # Calculate collision point
        collision_x = (self.rect.centerx + opponent.rect.centerx) // 2
        collision_y = (self.rect.centery + opponent.rect.centery) // 2
        
        # Create impact particles
        for _ in range(15):
            angle = random.uniform(0, math.pi * 2)
            speed = random.uniform(1, 4)
            vel_x = math.cos(angle) * speed
            vel_y = math.sin(angle) * speed
            
            size = random.uniform(1, 3)
            lifetime = random.randint(10, 25)
            
            # Mix colors of both players
            if random.random() < 0.5:
                color = self.color
            else:
                color = opponent.color
                
            self.particles.append(Particle(collision_x, collision_y, color, size, (vel_x, vel_y), False, lifetime))
    
    def add_protect_effect(self):
        # Si lowResources está activado, no generar partículas
        if hasattr(self, 'lowResources') and self.lowResources:
            return
            
        # Crear un efecto de escudo alrededor del jugador
        for _ in range(20):
            angle = random.uniform(0, math.pi * 2)
            # Posicionar partículas alrededor del personaje
            radius = self.rect.width * 0.8
            x = self.rect.centerx + math.cos(angle) * radius
            y = self.rect.centery + math.sin(angle) * radius
            
            # Velocidad circular alrededor del jugador
            vel_x = math.sin(angle) * 2
            vel_y = -math.cos(angle) * 2
            
            size = random.uniform(3, 6)
            lifetime = random.randint(15, 30)
            
            # Color azul claro para el escudo
            shield_color = (100, 200, 255)
            
            self.particles.append(Particle(
                x, y, shield_color, size, (vel_x, vel_y), False, lifetime
            ))
    
    def update_particles(self):
        # Si no hay partículas o lowResources está activado, no procesarlas
        if hasattr(self, 'lowResources') and self.lowResources:
            self.particles = []  # Limpiar las partículas existentes
            return
            
        i = 0
        while i < len(self.particles):
            if self.particles[i].update():
                self.particles.pop(i)
            else:
                i += 1