import pygame

# Particle class for visual effects
class Particle:
    def __init__(self, x, y, color, size, velocity, gravity=True, lifetime=None):
        self.x = x
        self.y = y
        self.color = color
        self.size = size
        self.original_size = size
        self.vel_x = velocity[0]
        self.vel_y = velocity[1]
        self.gravity = gravity
        self.alpha = 255  # For transparency
        self.lifetime = lifetime
        self.age = 0
    
    def update(self):
        self.x += self.vel_x
        self.y += self.vel_y
        
        if self.gravity:
            self.vel_y += 0.2
        
        # Shrink the particle over time
        if self.lifetime:
            self.age += 1
            progress = self.age / self.lifetime
            self.size = self.original_size * (1 - progress)
            self.alpha = 255 * (1 - progress)
        
        return self.alpha <= 0 or (self.lifetime and self.age >= self.lifetime)
    
    def draw(self, surface):
        if self.alpha < 255:
            s = pygame.Surface((self.size * 2, self.size * 2), pygame.SRCALPHA)
            pygame.draw.circle(s, (*self.color, self.alpha), (self.size, self.size), self.size)
            surface.blit(s, (int(self.x - self.size), int(self.y - self.size)))
        else:
            pygame.draw.circle(surface, self.color, (int(self.x), int(self.y)), int(self.size))