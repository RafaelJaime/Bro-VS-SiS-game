import os
import sys
import pygame
# To be from ./
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from src.screens.GamePlay import GamePlay
from src.utils.GameState import GameState
from src.ai.Agent import Agent
from src.ai.utils.TrainerHelper import save_model, draw_stats, parse_args
from src.ai.models.AIModels import AIModels

def main():
    args = parse_args()
    
    # Check if we're just recording videos
    if args.record:
        print("Grabando videos de los modelos existentes...")
        videos = AIModels.record_model_videos(
            models_folder='models',
            output_folder='videos',
            fps=args.fps,
            duration=args.duration
        )
        print(f"Videos grabados: {len(videos)}")
        
        # If also uploading to HuggingFace
        if args.upload:
            if not args.token:
                print("Error: Se necesita un token de HuggingFace para subir archivos")
                return
                
            print("Subiendo modelos y videos a HuggingFace...")
            repo_url = AIModels.upload_to_huggingface(
                model_folder='models',
                video_folder='videos',
                repo_name=args.repo_name,
                token=args.token
            )
            print(f"Subida completada: {repo_url}")
        
        return
    
    # Continue with normal training if not recording
    run_training()

def run_training():
    # Get the shared agent instance that will persist across game resets
    shared_agent = Agent.get_instance()

    # Init game
    pygame.init()
    pygame.event.set_allowed([pygame.QUIT, pygame.KEYDOWN])

    # Config game
    WIDTH, HEIGHT = 800, 600
    screen = pygame.display.set_mode((WIDTH, HEIGHT))
    pygame.display.set_caption("Pygame Fighter NN trainer")
    clock = pygame.time.Clock()

    # Config game play
    game_play = GamePlay(screen, WIDTH, HEIGHT, low_resources=True)
    players = ((255, 0, 0), (255, 165, 0), 'Bot 1', 'Bot 2', 2)
    game_play.set_players(players)
    state = GameState.PLAYING

    # Tracking variables for statistics
    total_rewards = 0
    wins = [0, 0]  # [player1 wins, player2 wins]
    save_folder = 'models'
    current_rewards = [0, 0]  # Current reward for each bot
    max_rewards = [-float('inf'), -float('inf')]  # Record rewards for each bot

    # Create models directory if it doesn't exist
    os.makedirs(save_folder, exist_ok=True)

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
        
        # Update current rewards if we have access to them
        if hasattr(game_play.player1, 'last_reward'):
            current_rewards[0] = game_play.player1.last_reward
            # Update max reward if current is higher
            max_rewards[0] = max(max_rewards[0], current_rewards[0])
        
        if hasattr(game_play.player2, 'last_reward'):
            current_rewards[1] = game_play.player2.last_reward
            # Update max reward if current is higher
            max_rewards[1] = max(max_rewards[1], current_rewards[1])
        
        state = GameState.GAME_OVER if game_play.check_game_over() else GameState.PLAYING
        
        if state == GameState.GAME_OVER:
            # Track who won
            if game_play.player1.is_defeated:
                wins[1] += 1
            elif game_play.player2.is_defeated:
                wins[0] += 1
                
            # Save model periodically
            if shared_agent.n_games % 100 == 0 and shared_agent.n_games > 0:
                save_model(shared_agent, save_folder, shared_agent.n_games)
            
            # Reset the game
            game_play.reset_game()
            game_play.set_players(players)
            state = GameState.PLAYING
        
        game_play.update(is_paused=False)
        
        # Dibujar estadísticas con actualización periódica
        draw_stats(screen, shared_agent, wins, current_rewards, max_rewards)
        
        pygame.display.update()
        
    # Save final model before quitting
    if shared_agent.n_games > 0:
        save_model(shared_agent, save_folder, shared_agent.n_games, is_final=True)
        
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()