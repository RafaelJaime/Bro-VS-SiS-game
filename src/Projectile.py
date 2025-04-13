import pygame
import math
import random
from src.Particle import Particle

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

    def move(self):
        self.x += self.speed * self.direction
        # Add trail particles
        self.particles.append(Particle(
            self.x, 
            self.y,
            self.color,
            random.uniform(2, 4),
            (random.uniform(-1, 1), random.uniform(-1, 1)),
            False,
            10
        ))

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