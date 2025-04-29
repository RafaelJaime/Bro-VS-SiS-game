import os
import sys
import pygame
# To be from ./
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))
from src.screens.GamePlay import GamePlay
from src.utils.GameState import GameState
from src.ai.Agent import Agent

# Funciones para manejo de modelo y estadísticas
def save_model(agent, folder, games_count, is_final=False):
    """
    Guarda el modelo del agente con información sobre la época
    
    Args:
        agent: Instancia del agente a guardar
        folder: Carpeta donde guardar el modelo
        games_count: Número de juegos/épocas completadas
        is_final: Si es el modelo final (True) o uno periódico (False)
    """
    # Crear la carpeta si no existe
    os.makedirs(folder, exist_ok=True)
    
    # Determinar el nombre del archivo
    if is_final:
        file_name = f'model_final_{games_count}_games.pth'
    else:
        file_name = f'model_{games_count}.pth'
    
    model_path = os.path.join(folder, file_name)
    agent.model.save(model_path)
    
    print(f"Model saved to {model_path} after {games_count} games")
    return model_path

def draw_stats(surface, agent, wins, current_rewards, max_rewards, display_interval=60):
    """
    Dibuja estadísticas de entrenamiento en la pantalla periódicamente
    
    Args:
        surface: Superficie donde dibujar
        agent: Agente con datos de entrenamiento
        wins: Lista con victorias [p1_wins, p2_wins]
        current_rewards: Recompensas actuales de cada bot
        max_rewards: Recompensas máximas históricas
        display_interval: Intervalo de frames para actualizar la visualización
    """
    # Solo actualizar la visualización cada cierto número de frames
    if not hasattr(draw_stats, "frame_counter"):
        draw_stats.frame_counter = 0
    
    # Inicializar surface donde guardar la visualización
    if not hasattr(draw_stats, "stats_surface"):
        draw_stats.stats_surface = None
    
    # Incrementar contador
    draw_stats.frame_counter += 1
    
    # Actualizar visualización solo cuando sea necesario
    if draw_stats.frame_counter >= display_interval or draw_stats.stats_surface is None:
        font = pygame.font.SysFont('Arial', 24)
        
        # Crear superficie para las estadísticas
        stats_surface = pygame.Surface((350, 250), pygame.SRCALPHA)
        stats_surface.fill((0, 0, 0, 180))  # Fondo semitransparente
        
        stats = [
            f"Época: {agent.n_games}",
            f"Bot 1 wins: {wins[0]}",
            f"Bot 2 wins: {wins[1]}",
            f"Win rate (Bot 1): {wins[0]/(sum(wins) or 1):.2f}",
            f"Epsilon: {agent.epsilon}",
            f"Bot 1 reward: {current_rewards[0]:.2f} (max: {max_rewards[0]:.2f})",
            f"Bot 2 reward: {current_rewards[1]:.2f} (max: {max_rewards[1]:.2f})"
        ]
        
        y_pos = 10
        for stat in stats:
            text_surface = font.render(stat, True, (255, 255, 255))
            stats_surface.blit(text_surface, (10, y_pos))
            y_pos += 30
        
        # Guardar la superficie para reutilizar
        draw_stats.stats_surface = stats_surface
        draw_stats.frame_counter = 0
    
    # Dibujar la superficie guardada
    if draw_stats.stats_surface:
        surface.blit(draw_stats.stats_surface, (10, 70))

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
game_play = GamePlay(screen, WIDTH, HEIGHT)
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
    
    game_play.update(2, is_paused=False)
    
    # Dibujar estadísticas con actualización periódica
    draw_stats(screen, shared_agent, wins, current_rewards, max_rewards)
    
    pygame.display.update()
    
# Save final model before quitting
if shared_agent.n_games > 0:
    save_model(shared_agent, save_folder, shared_agent.n_games, is_final=True)
    
pygame.quit()
sys.exit()