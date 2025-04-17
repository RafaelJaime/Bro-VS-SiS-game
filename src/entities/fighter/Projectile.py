import pygame
import math
import random
from src.utils.Particle import Particle

# Projectile class for shooting balls
class Projectile:
    def __init__(self, x, y, direction, color):
        self.radius = 8
        self.x = x
        self.y = y
        self.speed = 10
        self.direction = direction  # 1 for right, -1 for left
        self.color = color
        self.active = True
        self.particles = []
        
        # Create secondary color for effects
        r, g, b = self.color
        self.secondary_color = (min(r + 50, 255), min(g + 50, 255), min(b + 50, 255))

    def move(self):
        self.x += self.speed * self.direction
        # Add trail particles with the projectile's color
        color = self.color if random.random() < 0.6 else self.secondary_color
        self.particles.append(Particle(
            self.x, 
            self.y,
            color,
            random.uniform(2, 4),
            (random.uniform(-1, 1), random.uniform(-1, 1)),
            False,
            10
        ))
        
        # Update existing particles
        i = 0
        while i < len(self.particles):
            if self.particles[i].update():
                self.particles.pop(i)
            else:
                i += 1

    def draw(self, surface, camera_offset=[0, 0]):
        if self.active:
            pygame.draw.circle(surface, self.color, 
                             (int(self.x + camera_offset[0]), 
                              int(self.y + camera_offset[1])), 
                             self.radius)
            
            # Draw particles
            i = 0
            while i < len(self.particles):
                if self.particles[i].update():
                    self.particles.pop(i)
                else:
                    self.particles[i].draw(surface)
                    i += 1

    def check_collision(self, opponent):
        distance = math.sqrt((self.x - opponent.rect.centerx)**2 + 
                           (self.y - opponent.rect.centery)**2)
        return distance < self.radius + opponent.rect.width/2