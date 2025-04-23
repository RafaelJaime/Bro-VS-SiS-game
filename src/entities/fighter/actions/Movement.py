import pygame
import random
from src.entities.fighter.FighterControls import FighterControls

WIDTH, HEIGHT = 800, 600

class Movement:
    def __init__(self):
        # Inicializar variables relacionadas con el movimiento
        self.vel_y = 0
        self.jumping = False
        self.is_ai = False
        self.ai_decision_timer = 0
        self.ai_current_action = None
    
    def move(self, opponent):
        # Store opponent reference for shoot method
        self._current_opponent = opponent
        
        # Reset movement variables
        dx = 0
        dy = 0

        # Actualizar temporizador de protección
        if self.protect_cooldown > 0:
            self.protect_cooldown -= 1
        
        # Desactivar protección si el tiempo termina
        if self.protecting and self.protect_duration <= 0:
            self.protecting = False
            self.protect_cooldown = self.protect_max_cooldown
        elif self.protecting:
            self.protect_duration -= 1

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
                    self.add_attack_windup_effect(opponent)
                    self.attack(opponent)
                elif self.ai_current_action == 'shoot' and self.can_shoot():
                    self.shoot()
                    self.shoot_cooldown = 30
            else:
                # Regular player controls
                key = pygame.key.get_pressed()

                # Shooting mechanic
                if self.shoot_cooldown > 0:
                    self.shoot_cooldown -= 1

                # Verificar disparo usando los controles - usar can_shoot para comprobar condiciones
                if key[self.controls[FighterControls.SHOOT]] and self.can_shoot():
                    self.shoot()
                    self.shoot_cooldown = 30

                # Activación de protección con una sola tecla
                if not self.protecting and self.protect_cooldown == 0:
                    if key[self.controls[FighterControls.PROTECT]]:
                        self.protect()  # Call the protect method instead of inline implementation

                # Can only perform actions if not attacking and not protecting
                if not self.attacking and not self.protecting:
                    # Movement controls
                    if key[self.controls[FighterControls.LEFT]]:
                        dx = -5
                        if not self.jumping and random.random() < 0.2:
                            self.add_dust_particle(self.rect.left, self.rect.bottom)
                    if key[self.controls[FighterControls.RIGHT]]:
                        dx = 5
                        if not self.jumping and random.random() < 0.2:
                            self.add_dust_particle(self.rect.right, self.rect.bottom)
                    
                    # Jump
                    if key[self.controls[FighterControls.UP]] and not self.jumping:
                        self.vel_y = -15
                        self.jumping = True
                        self.add_jump_effect()
                    
                    # Attack
                    if key[self.controls[FighterControls.ATTACK]] and self.attack_cooldown == 0:
                        self.attacking = True
                        self.attack_cooldown = 20
                        self.add_attack_windup_effect(opponent)
                        self.attack(opponent)

        # Update projectiles
        self.update_projectiles(opponent)
        
        # Comprobar colisión de proyectil con ataque mientras está protegido
        if self.attacking and self.protecting:
            self.check_projectile_attack_collision(opponent)

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
                        self.screen_shake.start(4)
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