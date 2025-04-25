import pygame
import sys

from src.utils.GameState import GameState
from src.screens.MainMenu import MainMenu
from src.screens.DifficultySelect import DifficultySelect
from src.screens.CharacterSelect import CharacterSelect
from src.screens.GamePlay import GamePlay
from src.screens.PauseMenu import PauseMenu
from src.screens.GameOver import GameOver

# Initialize pygame
pygame.init()

# Screen dimensions
WIDTH, HEIGHT = 800, 600
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Pygame Fighter")

# Game modes
MODE_PVP = 0
MODE_PVC = 1
MODE_CVC = 2

def main():
    clock = pygame.time.Clock()
    
    # Initialize screens
    main_menu = MainMenu(screen, WIDTH, HEIGHT)
    difficulty_select = DifficultySelect(screen, WIDTH, HEIGHT)
    character_select = CharacterSelect(screen, WIDTH, HEIGHT)
    game_play = GamePlay(screen, WIDTH, HEIGHT)
    pause_menu = PauseMenu(screen, WIDTH, HEIGHT)
    game_over = GameOver(screen, WIDTH, HEIGHT)
    
    # Start with main menu
    current_state = GameState.MAIN_MENU
    game_mode = MODE_PVP
    previous_state = None
    
    # Game loop
    run = True
    while run:
        clock.tick(60)
        mouse_pos = pygame.mouse.get_pos()
        
        # Verificar si estamos entrando a la pantalla de selección de personajes desde otro estado
        if current_state == GameState.CHARACTER_SELECT and previous_state != GameState.CHARACTER_SELECT:
            character_select.reset()
        
        # Guardar estado actual para la próxima iteración
        previous_state = current_state
        
        # Event handling
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                run = False
                continue
            
            # Handle state-specific events
            match current_state:
                case GameState.MAIN_MENU:
                    next_state = main_menu.handle_event(event)
                    if next_state == GameState.EXIT:
                        run = False
                    elif next_state:
                        current_state = next_state if isinstance(next_state, GameState) else GameState(next_state)
                
                case GameState.DIFFICULTY_SELECT:
                    result = difficulty_select.handle_event(event)
                    if result:
                        next_state, mode = result
                        if next_state == GameState.CHARACTER_SELECT or next_state == "CHARACTER_SELECT":
                            game_mode = mode
                        current_state = next_state if isinstance(next_state, GameState) else GameState(next_state)
                
                case GameState.CHARACTER_SELECT:
                    next_state = character_select.handle_event(event)
                    if next_state == GameState.PLAYERS_SELECTED:
                        player_selection = character_select.get_player_selection()
                        if player_selection and all(player_selection[:2]):
                            game_play.reset_game()
                            player_config = (*player_selection, game_mode)
                            game_play.set_players(player_config)
                            current_state = GameState.PLAYING
                    elif next_state:
                        current_state = next_state if isinstance(next_state, GameState) else GameState(next_state)
                
                case GameState.PLAYING:
                    next_state = game_play.handle_event(event)
                    if next_state:
                        current_state = next_state if isinstance(next_state, GameState) else GameState(next_state)
                
                case GameState.PAUSE:
                    next_state = pause_menu.handle_event(event)
                    if next_state:
                        if next_state == GameState.MAIN_MENU or next_state == "MAIN_MENU":
                            game_play.reset_game()
                        current_state = next_state if isinstance(next_state, GameState) else GameState(next_state)
                
                case GameState.GAME_OVER:
                    next_state = game_over.handle_event(event)
                    if next_state:
                        if next_state == GameState.PLAYING or next_state == "PLAYING":
                            game_play.reset_game()
                        elif next_state == GameState.MAIN_MENU or next_state == "MAIN_MENU":
                            game_play.reset_game()
                        current_state = next_state if isinstance(next_state, GameState) else GameState(next_state)
        
        # Update and render current screen based on state
        match current_state:
            case GameState.MAIN_MENU:
                main_menu.update(mouse_pos)
            
            case GameState.DIFFICULTY_SELECT:
                difficulty_select.update(mouse_pos)
            
            case GameState.CHARACTER_SELECT:
                character_select.update(mouse_pos)
            
            case GameState.PLAYING:
                game_play.update(game_mode, is_paused=False)
                if game_play.check_game_over():
                    current_state = GameState.GAME_OVER
            
            case GameState.PAUSE:
                # Actualizar el juego con is_paused=True para detener los proyectiles
                game_play.update(game_mode, is_paused=True)
                # Then draw the pause menu overlay
                pause_menu.update(mouse_pos)
            
            case GameState.GAME_OVER:
                # First update the game screen in the background
                game_play.update(game_mode, is_paused=True)
                # Then draw the game over overlay
                game_over.update(mouse_pos, game_play.get_winner())
        
        pygame.display.update()
    
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()
