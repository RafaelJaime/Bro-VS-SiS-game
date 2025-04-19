import pygame
import math
import random
from src.utils.ScreenShake import screen_shake
from src.entities.fighter.Projectile import Projectile
from src.utils.Particle import Particle

WIDTH, HEIGHT = 800, 600

class Combat:
    def __init__(self):
        # Inicializar variables relacionadas con el combate
        self.health = 100
        self.attacking = False
        self.attack_cooldown = 0
        self.hit_cooldown = 0
        self.knockback_x = 0
        self.knockback_y = 0
        self.knockback_resistance = 0.8
        self.sudden_death_mode = False
        self.is_defeated = False
        self.defeat_animation = 0
        self.score = 0
        
        # Variables para la mecánica de protección
        self.protecting = False
        self.protect_cooldown = 0
        self.protect_duration = 60  # 1 segundo (60 frames)
        self.protect_max_cooldown = 60  # 1 segundo de recarga
    
    def can_shoot(self):
        """Check if the fighter can shoot (not protecting and cooldown is ready)"""
        return self.shoot_cooldown == 0 and not self.protecting
        
    def protect(self):
        """Activate protection mode for the fighter"""
        # Only activate protection if cooldown has passed
        if self.protect_cooldown <= 0:
            self.protecting = True
            self.protect_duration = 60  # 1 second of protection (60 frames)
            self.protect_cooldown = self.protect_max_cooldown  # Start the cooldown
            # Add visual effect for protection activation
            self.add_protect_effect()
            
    def add_protect_effect(self):
        """Add visual effect for protection activation"""
        # Create particles in a circle around the fighter
        center_x = self.rect.centerx
        center_y = self.rect.centery
        for _ in range(8):  # Create 8 particles in a circle
            angle = random.uniform(0, 2 * math.pi)
            distance = self.rect.width * 0.75
            x = center_x + math.cos(angle) * distance
            y = center_y + math.sin(angle) * distance
            
            # Create particle with fighter's color - corrected parameter order
            size = random.randint(5, 10)
            velocity = (random.uniform(-0.5, 0.5), random.uniform(-0.5, 0.5))
            lifetime = random.randint(20, 30)
            
            particle = Particle(
                x, y,              # Position
                self.color,        # Color
                size,              # Size
                velocity,          # Velocity as a tuple
                True,              # Gravity
                lifetime           # Lifetime
            )
            self.particles.append(particle)
            
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
            
        # Si el jugador está protegido, no recibe daño
        if self.protecting:
            # Si es un proyectil (tiene hit_pos), lo devuelve
            if hit_pos:
                # Determinar la dirección del rebote hacia el atacante
                direction = 1 if attacker.rect.centerx > self.rect.centerx else -1
                
                # Asegurarse de que solo se crea un proyectil de rebote
                current_time = pygame.time.get_ticks()
                if not hasattr(self, 'last_bounce_time') or current_time - self.last_bounce_time > 100:  # 100ms cooldown
                    # Crear un nuevo proyectil que va hacia el atacante
                    projectile = Projectile(
                        self.rect.centerx + (direction * self.rect.width/2),
                        self.rect.centery,
                        direction,
                        self.color
                    )
                    self.projectiles.append(projectile)
                    # Efecto visual de rebote
                    self.add_shoot_effect(direction)
                    screen_shake.start(2)
                    # Guardar el tiempo del último rebote
                    self.last_bounce_time = current_time
                    
                    # Esto es lo importante: indicamos que se debe eliminar el proyectil original
                    # al devolver True, el código en update_projectiles eliminará el proyectil
                    return True
                
                return False
            else:
                # Si es un golpe normal, no recibe daño pero tampoco lo devuelve
                screen_shake.start(1)
                return False
            
        # En modo muerte súbita, cualquier golpe es fatal
        if hasattr(self, 'sudden_death_mode') and self.sudden_death_mode:
            self.health = 0
            self.is_defeated = True
            attacker.score += 1
            pos = hit_pos if hit_pos else (self.rect.centerx, self.rect.centery)
            attacker.add_ko_effect(*pos)
        else:
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

    def check_projectile_attack_collision(self, opponent):
        # Crear un rectángulo de ataque similar al del método attack()
        attack_rect = pygame.Rect(0, 0, 0, 0)
        
        # Posicionar el rectángulo de ataque según la orientación del jugador
        if self.rect.centerx < opponent.rect.centerx:  # Mirando a la derecha
            attack_rect = pygame.Rect(self.rect.right, self.rect.y, 50, self.rect.height)
        else:  # Mirando a la izquierda
            attack_rect = pygame.Rect(self.rect.left - 50, self.rect.y, 50, self.rect.height)
        
        # Comprobar colisión con proyectiles del oponente
        i = 0
        while i < len(opponent.projectiles):
            projectile = opponent.projectiles[i]
            
            # Crear un rectángulo para el proyectil
            projectile_rect = pygame.Rect(
                projectile.x - projectile.radius, 
                projectile.y - projectile.radius,
                projectile.radius * 2,
                projectile.radius * 2
            )
            
            # Si el rectángulo de ataque colisiona con un proyectil, hacerlo desaparecer
            if attack_rect.colliderect(projectile_rect):
                opponent.projectiles.pop(i)
                # Añadir efecto visual de desvío
                self.add_hit_effect(projectile.x, projectile.y)
                screen_shake.start(2)
                continue
                
            i += 1