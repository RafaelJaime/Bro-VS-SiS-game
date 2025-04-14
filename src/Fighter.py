import pygame
import math
import random
from src.Colors import GREEN, YELLOW, ORANGE, RED, WHITE, BLUE
from src.Particle import Particle
from src.ScreenShake import screen_shake
from src.Projectile import Projectile

WIDTH, HEIGHT = 800, 600

# Player class
class Fighter:
    def __init__(self, x, y, width, height, color, controls, name):
        self.rect = pygame.Rect(x, y, width, height)
        self.color = color
        self.vel_y = 0
        self.jumping = False
        self.health = 100
        self.attacking = False
        self.attack_cooldown = 0
        self.hit_cooldown = 0
        self.controls = controls
        self.name = name
        self.score = 0
        self.particles = []
        self.hit_flash = 0
        self.hit_flash_max = 5
        self.is_defeated = False
        self.defeat_animation = 0
        self.projectiles = []
        self.shoot_cooldown = 0
        self.is_ai = False  # New flag for AI control
        self.ai_decision_timer = 0  # Timer for AI decision making
        self.ai_current_action = None  # Current AI action
        self.knockback_x = 0
        self.knockback_y = 0
        self.knockback_resistance = 0.8  # Resistencia al knockback (menor = más duración)
        
        # Create secondary colors for effects
        r, g, b = self.color
        self.secondary_color = (min(r + 50, 255), min(g + 50, 255), min(b + 50, 255))

    def ai_make_decision(self, opponent):
        """AI decision making logic"""
        dx = opponent.rect.centerx - self.rect.centerx
        dy = opponent.rect.centery - self.rect.centery
        distance = (dx**2 + dy**2)**0.5

        # Reset decision timer
        self.ai_decision_timer = random.randint(10, 30)  # Random delay between decisions

        # If opponent is close, decide between attack and jump
        if distance < 100:
            if random.random() < 0.7:  # 70% chance to attack when close
                return 'attack'
            else:
                return 'jump'
        
        # If opponent is at medium range, maybe shoot
        elif distance < 300:
            if random.random() < 0.4:  # 40% chance to shoot
                return 'shoot'
        
        # Move towards opponent with some randomness
        if dx > 0:
            return 'move_right'
        else:
            return 'move_left'

    def move(self, opponent):
        # Store opponent reference for shoot method
        self._current_opponent = opponent
        
        # Reset movement variables
        dx = 0
        dy = 0

        # Aplicar knockback si existe
        has_knockback = self.knockback_x != 0 or self.knockback_y != 0
        if has_knockback:
            dx += self.knockback_x
            dy += self.knockback_y
            # Reducir el knockback gradualmente
            self.knockback_x *= self.knockback_resistance
            self.knockback_y *= self.knockback_resistance
            # Resetear knockback cuando es muy pequeño
            if abs(self.knockback_x) < 0.1:
                self.knockback_x = 0
            if abs(self.knockback_y) < 0.1:
                self.knockback_y = 0

        # Solo permitir movimiento del jugador si no hay knockback significativo
        if not has_knockback or (abs(self.knockback_x) < 2 and abs(self.knockback_y) < 2):
            if self.is_ai:
                # AI decision making
                if self.ai_decision_timer <= 0:
                    self.ai_current_action = self.ai_make_decision(opponent)
                else:
                    self.ai_decision_timer -= 1

                # Execute AI action
                if self.ai_current_action == 'move_right':
                    dx = 5
                    if not self.jumping and random.random() < 0.2:
                        self.add_dust_particle(self.rect.right, self.rect.bottom)
                elif self.ai_current_action == 'move_left':
                    dx = -5
                    if not self.jumping and random.random() < 0.2:
                        self.add_dust_particle(self.rect.left, self.rect.bottom)
                elif self.ai_current_action == 'jump' and not self.jumping:
                    self.vel_y = -15
                    self.jumping = True
                    self.add_jump_effect()
                elif self.ai_current_action == 'attack' and self.attack_cooldown == 0:
                    self.attacking = True
                    self.attack_cooldown = 20
                    self.add_attack_windup_effect()
                    self.attack(opponent)
                elif self.ai_current_action == 'shoot' and self.shoot_cooldown == 0:
                    self.shoot()
                    self.shoot_cooldown = 30
            else:
                # Regular player controls
                key = pygame.key.get_pressed()

                # Shooting mechanic
                if self.shoot_cooldown > 0:
                    self.shoot_cooldown -= 1

                # Check for shoot button (G for player 1, L for player 2)
                if (self.name == "Player 1" and key[pygame.K_g] or 
                    self.name == "Player 2" and key[pygame.K_l]) and self.shoot_cooldown == 0:
                    self.shoot()
                    self.shoot_cooldown = 30

                # Can only perform actions if not attacking
                if not self.attacking:
                    # Movement controls
                    if key[self.controls['left']]:
                        dx = -5
                        if not self.jumping and random.random() < 0.2:
                            self.add_dust_particle(self.rect.left, self.rect.bottom)
                    if key[self.controls['right']]:
                        dx = 5
                        if not self.jumping and random.random() < 0.2:
                            self.add_dust_particle(self.rect.right, self.rect.bottom)
                    
                    # Jump
                    if key[self.controls['up']] and not self.jumping:
                        self.vel_y = -15
                        self.jumping = True
                        self.add_jump_effect()
                    
                    # Attack
                    if key[self.controls['attack']] and self.attack_cooldown == 0:
                        self.attacking = True
                        self.attack_cooldown = 20
                        self.add_attack_windup_effect()
                        self.attack(opponent)

        # Update projectiles
        self.update_projectiles(opponent)
        
        # Apply gravity
        self.vel_y += 1
        if self.vel_y > 10:
            self.vel_y = 10
        dy += self.vel_y
        
        # Ensure player stays on screen
        if self.rect.left + dx < 0:
            dx = -self.rect.left
        if self.rect.right + dx > WIDTH:
            dx = WIDTH - self.rect.right
        
        # Check for collision with opponent when moving horizontally
        future_rect_x = pygame.Rect(self.rect.x + dx, self.rect.y, self.rect.width, self.rect.height)
        if future_rect_x.colliderect(opponent.rect):
            # Create a collision effect if moving with sufficient speed
            if abs(dx) > 3:
                self.add_collision_effect(opponent)
                
            # Calculate collision resolution
            if dx > 0:  # Moving right
                dx = opponent.rect.left - self.rect.right
            elif dx < 0:  # Moving left
                dx = opponent.rect.right - self.rect.left
        
        # Check if player is on the ground
        if self.rect.bottom + dy > HEIGHT - 50:
            dy = HEIGHT - 50 - self.rect.bottom
            self.vel_y = 0
            
            # Landing effect
            if self.jumping:
                self.add_landing_effect()
            
            self.jumping = False
        
        # Check for collision with opponent when moving vertically
        future_rect_y = pygame.Rect(self.rect.x, self.rect.y + dy, self.rect.width, self.rect.height)
        if future_rect_y.colliderect(opponent.rect):
            # If landing on opponent from above
            if self.vel_y > 0 and self.rect.bottom <= opponent.rect.top + 10:
                dy = opponent.rect.top - self.rect.bottom
                self.vel_y = 0
                self.jumping = False
                
                # Create bounce effect when landing on opponent
                self.vel_y = -8
                self.jumping = True
                self.add_landing_effect()
                
                # Apply damage to opponent when landing on them
                if self.vel_y > 5:
                    if opponent.take_damage(5, self):
                        screen_shake.start(4)
            else:
                # For other vertical collisions
                if dy > 0:  # Moving down
                    dy = opponent.rect.top - self.rect.bottom
                elif dy < 0:  # Moving up
                    dy = opponent.rect.bottom - self.rect.top
                    self.vel_y = 1  # Stop upward movement
        
        # Update player position
        self.rect.x += dx
        self.rect.y += dy
        
        # Update cooldowns
        if self.attack_cooldown > 0:
            self.attack_cooldown -= 1
        if self.hit_cooldown > 0:
            self.hit_cooldown -= 1
        
        # Update hit flash
        if self.hit_flash > 0:
            self.hit_flash -= 1
        
        # Reset attack status
        if self.attacking and self.attack_cooldown <= 15:
            self.attacking = False
        
        # Update particles
        self.update_particles()
    
    def shoot(self):
        # Store opponent reference when move() is called
        opponent = getattr(self, '_current_opponent', None)
        
        # Determine direction based on opponent or default to facing direction
        direction = 1 if self.rect.centerx < WIDTH/2 else -1
        if opponent:
            direction = 1 if self.rect.centerx < opponent.rect.centerx else -1
        
        # Create new projectile
        projectile = Projectile(
            self.rect.centerx + (direction * self.rect.width/2),
            self.rect.centery,
            direction,
            self.color
        )
        self.projectiles.append(projectile)
        
        # Add shoot effect
        self.add_shoot_effect(direction)

    def update_projectiles(self, opponent):
        i = 0
        while i < len(self.projectiles):
            projectile = self.projectiles[i]
            projectile.move()
            
            # Check if projectile is off screen
            if projectile.x < 0 or projectile.x > WIDTH:
                self.projectiles.pop(i)
                continue
            
            # Check collision with opponent
            if projectile.check_collision(opponent):
                if opponent.take_damage(5, self, (projectile.x, projectile.y)):
                    opponent.hit_cooldown = 15
                    screen_shake.start(3)
                    self.projectiles.pop(i)
                    continue
            
            i += 1

    def add_shoot_effect(self, direction):
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

    def add_attack_windup_effect(self):
        # Direction of attack
        direction = 1 if self.rect.centerx < WIDTH / 2 else -1
        
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
                color, size, (vel_x, vel_y), False, lifetime
            ))

    def attack(self, opponent):
        # Create an attack hitbox
        attack_rect = pygame.Rect(0, 0, 0, 0)
        
        # Position the attack hitbox based on player orientation
        if self.rect.centerx < opponent.rect.centerx:  # Facing right
            attack_rect = pygame.Rect(self.rect.right, self.rect.y, 50, self.rect.height)
        else:  # Facing left
            attack_rect = pygame.Rect(self.rect.left - 50, self.rect.y, 50, self.rect.height)
        
        # Check for collision with opponent
        if attack_rect.colliderect(opponent.rect):
            if opponent.take_damage(10, self):
                opponent.hit_cooldown = 30
                screen_shake.start(8)
    
    def take_damage(self, amount, attacker, hit_pos=None):
        if self.hit_cooldown > 0:
            return False
            
        self.health -= amount
        if self.health <= 0:
            self.health = 0
            self.is_defeated = True
            attacker.score += 1
            pos = hit_pos if hit_pos else (self.rect.centerx, self.rect.centery)
            attacker.add_ko_effect(*pos)
        
        # Aplicar knockback
        knockback_force = amount * 2  # La fuerza del knockback depende del daño
        if hit_pos:
            # Calcular dirección del knockback desde el punto de impacto
            dx = self.rect.centerx - hit_pos[0]
            dy = self.rect.centery - hit_pos[1]
            # Normalizar el vector
            length = math.sqrt(dx * dx + dy * dy)
            if length > 0:
                self.knockback_x = (dx / length) * knockback_force
                self.knockback_y = (dy / length) * knockback_force * 0.5  # Menos knockback vertical
        else:
            # Si no hay punto de impacto, usar la posición relativa del atacante
            direction = 1 if attacker.rect.centerx < self.rect.centerx else -1
            self.knockback_x = direction * knockback_force
            self.knockback_y = -knockback_force * 0.3  # Pequeño impulso hacia arriba
        
        self.hit_flash = self.hit_flash_max
        
        if hit_pos:
            attacker.add_hit_effect(*hit_pos)
        
        return True

    def add_dust_particle(self, x, y):
        for _ in range(2):
            vel_x = random.uniform(-1, 1)
            vel_y = random.uniform(-2, -0.5)
            size = random.uniform(1, 3)
            lifetime = random.randint(20, 40)
            color = (200, 200, 200)
            self.particles.append(Particle(x, y, color, size, (vel_x, vel_y), True, lifetime))
    
    def add_jump_effect(self):
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
            
            self.particles.append(Particle(x, y, color, size, (vel_x, vel_y), False, lifetime))
    
    def add_ko_effect(self, x, y):
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
    
    def update_particles(self):
        i = 0
        while i < len(self.particles):
            if self.particles[i].update():
                self.particles.pop(i)
            else:
                i += 1
    
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