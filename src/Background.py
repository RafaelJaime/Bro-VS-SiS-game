import pygame
import random
from src.Colors import BLACK

class Background:
    def __init__(self, width, height):
        self.width = width
        self.height = height
        self.stars = []
        
        # Create stars
        for _ in range(80):
            x = random.randint(0, width)
            y = random.randint(0, height - 50)
            size = random.uniform(0.5, 2)
            brightness = random.randint(100, 255)
            color = (brightness, brightness, brightness)
            self.stars.append([x, y, size, color])
    
    def draw(self, screen):
        # Draw black background
        screen.fill(BLACK)
        
        # Draw stars
        for star in self.stars:
            pygame.draw.circle(screen, star[3], (star[0], star[1]), star[2])
            
    def update(self):
        # Aquí podríamos añadir animaciones para las estrellas si lo deseamos
        pass