import pygame
import sys
from src.screens.main_menu import MainMenu
from src.screens.difficulty_select import DifficultySelect
from src.screens.character_select import character_select_screen
from src.screens.game_play import GamePlay
from src.screens.pause_menu import PauseMenu
from src.screens.game_over import GameOver

# Initialize pygame
pygame.init()

# Screen dimensions
WIDTH, HEIGHT = 800, 600
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Pygame Fighter")

# Game states
class GameState:
    PLAYING = "PLAYING"
    GAME_OVER = "GAME_OVER"
    MAIN_MENU = "MAIN_MENU"
    DIFFICULTY_SELECT = "DIFFICULTY_SELECT"
    CHARACTER_SELECT = "CHARACTER_SELECT"
    PAUSE = "PAUSE"
    EXIT = "EXIT"

# Game modes
MODE_PVP = 0
MODE_PVC = 1
MODE_CVC = 2

def main():
    clock = pygame.time.Clock()
    
    # Initialize screens
    main_menu = MainMenu(screen, WIDTH, HEIGHT)
    difficulty_select = DifficultySelect(screen, WIDTH, HEIGHT)
    game_play = GamePlay(screen, WIDTH, HEIGHT)
    pause_menu = PauseMenu(screen, WIDTH, HEIGHT)
    game_over = GameOver(screen, WIDTH, HEIGHT)
    
    # Start with main menu
    current_state = GameState.MAIN_MENU
    game_mode = MODE_PVP
    
    # Game loop
    run = True
    while run:
        clock.tick(60)
        mouse_pos = pygame.mouse.get_pos()
        
        # Event handling
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                run = False
                continue
            
            # Handle state-specific events
            if current_state == GameState.MAIN_MENU:
                next_state = main_menu.handle_event(event)
                if next_state == GameState.EXIT:
                    run = False
                elif next_state:
                    current_state = next_state
            
            elif current_state == GameState.DIFFICULTY_SELECT:
                result = difficulty_select.handle_event(event)
                if result:
                    next_state, mode = result
                    if next_state == GameState.CHARACTER_SELECT:
                        game_mode = mode
                    current_state = next_state
            
            elif current_state == GameState.CHARACTER_SELECT:
                p1_color, p2_color = character_select_screen(screen, WIDTH, HEIGHT)
                if p1_color is not None and p2_color is not None:
                    game_play.reset_game()
                    game_play.set_player_colors(p1_color, p2_color)
                    game_play.set_ai_mode(game_mode)
                    current_state = GameState.PLAYING
                elif p1_color is None and p2_color is None:
                    current_state = GameState.DIFFICULTY_SELECT
            
            elif current_state == GameState.PLAYING:
                next_state = game_play.handle_event(event)
                if next_state:
                    current_state = next_state
            
            elif current_state == GameState.PAUSE:
                next_state = pause_menu.handle_event(event)
                if next_state:
                    if next_state == GameState.MAIN_MENU:
                        game_play.reset_game()
                    current_state = next_state
            
            elif current_state == GameState.GAME_OVER:
                next_state = game_over.handle_event(event)
                if next_state:
                    if next_state == GameState.PLAYING:
                        game_play.reset_game()
                    elif next_state == GameState.MAIN_MENU:
                        game_play.reset_game()
                    current_state = next_state
        
        # Update and render current screen based on state
        if current_state == GameState.MAIN_MENU:
            main_menu.update(mouse_pos)
        
        elif current_state == GameState.DIFFICULTY_SELECT:
            difficulty_select.update(mouse_pos)
        
        elif current_state == GameState.PLAYING:
            game_play.update(game_mode)
            if game_play.check_game_over():
                current_state = GameState.GAME_OVER
        
        elif current_state == GameState.PAUSE:
            # First update the game screen in the background
            game_play.update(game_mode)
            # Then draw the pause menu overlay
            pause_menu.update(mouse_pos)
        
        elif current_state == GameState.GAME_OVER:
            # First update the game screen in the background
            game_play.update(game_mode)
            # Then draw the game over overlay
            game_over.update(mouse_pos, game_play.get_winner())
        
        pygame.display.update()
    
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()
