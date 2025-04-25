import os
import sys
import pygame
# To be from ./
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../../')))
from src.screens.GamePlay import GamePlay
from src.utils.GameState import GameState

# Init game
pygame.init()
pygame.event.set_allowed([pygame.QUIT, pygame.KEYDOWN])

# Config game
WIDTH, HEIGHT = 800, 600
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Pygame Fighter NN trainer")
clock = pygame.time.Clock()

# Config game play
game_play = GamePlay(screen, WIDTH, HEIGHT)
game_play.set_players(((255, 0, 0), (255, 165, 0), 'Bot 1', 'Bot 2', 2))
state = GameState.PLAYING

run = True
while run:
    clock.tick(60)
    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            run = False
        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                run = False
        else:
            state = game_play.handle_event(event)
    
    state = GameState.GAME_OVER if game_play.check_game_over() else GameState.PLAYING
    
    if state == GameState.GAME_OVER:
        game_play.reset_game()
        game_play.set_players(((255, 0, 0), (255, 165, 0), 'Bot 1', 'Bot 2', 2))
        state = GameState.PLAYING
    
    game_play.update(1, is_paused=False)
    
    pygame.display.update()
    
pygame.quit()
sys.exit()