import os
import pygame
import cv2
import glob
from datetime import datetime
import numpy as np
import argparse
from huggingface_hub import HfApi, upload_file, create_repo
import os
from src.ai.Model import Linear_QNet
from src.screens.GamePlay import GamePlay
from src.utils.GameState import GameState
from src.entities.fighter.utils.FighterControls import FighterControls

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
        
def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(description="Pygame Fighter AI Training/Demo Environment")
    parser.add_argument("--record", action="store_true", help="Record videos of all models")
    parser.add_argument("--upload", action="store_true", help="Upload models and videos to HuggingFace")
    parser.add_argument("--repo-name", type=str, help="HuggingFace repo name (format: username/repo-name)")
    parser.add_argument("--token", type=str, help="HuggingFace token")
    parser.add_argument("--fps", type=int, default=30, help="FPS for recording videos")
    parser.add_argument("--duration", type=int, default=60, help="Max duration of recorded videos in seconds")
    parser.add_argument("--model-name", type=str, help="Name of specific model to record/upload (without .pth extension)")
    return parser.parse_args()
