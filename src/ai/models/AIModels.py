from enum import Enum
import os
import pygame
import cv2
import glob
from datetime import datetime
import numpy as np
import os

from src.ai.Model import Linear_QNet
from src.screens.GamePlay import GamePlay
from src.utils.GameState import GameState
from src.entities.fighter.utils.FighterControls import FighterControls
from huggingface_hub import HfApi, upload_file, create_repo

class AIModels(str, Enum):
    """
    Enumerador para los modelos de IA con sus dificultades correspondientes.
    El valor asociado a cada enumerador es el nombre del archivo del modelo.
    """
    EASY = "model_final_40_games"
    MEDIUM = "model_final_12_games"
    HARD = "model_final_16_games"
    
    _models_folder = 'models'
    _videos_folder = 'videos'
    
    @staticmethod
    def record_model_videos(fps=30, duration=30, resolution=(800, 600), specific_model=None):
        """
        Crea videos de partidas usando todos los modelos de la carpeta especificada
        o un modelo específico si se indica
        
        Args:
            fps: Frames por segundo para el video
            duration: Duración máxima del video en segundos
            resolution: Resolución del video (ancho, alto)
            specific_model: Nombre específico del modelo a procesar (sin extensión .pth)
        
        Returns:
            Lista de rutas a los videos generados
        """
        
        # Importamos aquí para evitar importaciones cíclicas
        
        
        # Crear carpeta para videos si no existe
        os.makedirs(AIModels._videos_folder, exist_ok=True)
        
        # Buscar modelos en la carpeta
        if specific_model:
            # Buscar un modelo específico
            model_path = os.path.join(AIModels._models_folder, f"{specific_model}.pth")
            if not os.path.exists(model_path):
                print(f"No se encontró el modelo {model_path}")
                return []
            model_paths = [model_path]
        else:
            # Buscar todos los modelos
            model_paths = glob.glob(os.path.join(AIModels._models_folder, '*.pth'))
            
        if not model_paths:
            print(f"No se encontraron modelos en {AIModels._models_folder}")
            return []
        
        pygame.init()
        
        # Configurar pantalla
        width, height = resolution
        screen = pygame.display.set_mode((width, height))
        pygame.display.set_caption("Model Demo Recording")
        clock = pygame.time.Clock()
        
        video_paths = []
        
        for model_path in model_paths:
            model_name = os.path.basename(model_path).split('.')[0]
            video_path = os.path.join(AIModels._videos_folder, f"{model_name}.mp4")
            
            # Preparar el codificador de video
            fourcc = cv2.VideoWriter_fourcc(*'mp4v')
            video_writer = cv2.VideoWriter(video_path, fourcc, fps, resolution)
            
            # Configurar el juego y cargar el modelo
            game_play = GamePlay(screen, width, height)
            players = ((255, 0, 0), (255, 165, 0), 'Bot 1', 'Bot 2', 2)  # 2 = AI vs AI
            game_play.set_players(players)
            
            # Cargar modelo para ambos jugadores
            for fighter in [game_play.player1, game_play.player2]:
                if hasattr(fighter, 'agent') and fighter.agent:
                    fighter.agent.model = Linear_QNet.load(
                        input_size=14,
                        hidden_size=256,
                        output_size=len(FighterControls),
                        file_name=model_path
                    )
            
            # Ejecutar el juego y grabar frames
            state = GameState.PLAYING
            frame_count = 0
            max_frames = fps * duration  # 30fps * duración en segundos
            
            while state == GameState.PLAYING and frame_count < max_frames:
                clock.tick(fps)
                
                # Manejar eventos pero sin cerrar el juego
                for event in pygame.event.get():
                    if event.type == pygame.QUIT:
                        pygame.display.set_mode(resolution)  # Restore display
                    
                state = GameState.GAME_OVER if game_play.check_game_over() else GameState.PLAYING
                game_play.update(is_paused=False)
                
                # Capturar la pantalla para el video
                pygame_surface = pygame.display.get_surface()
                frame = pygame.surfarray.array3d(pygame_surface)
                frame = np.swapaxes(frame, 0, 1)
                frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
                video_writer.write(frame)
                
                pygame.display.update()
                frame_count += 1
                
            # Liberar recursos
            video_writer.release()
            video_paths.append(video_path)
            print(f"Video grabado: {video_path}")
            
            # Reiniciar el juego
            game_play.reset_game()
        
        pygame.quit()
        return video_paths

    @staticmethod
    def upload_to_huggingface(repo_name=None, token=None, specific_model=None):
        """
        Sube modelos y videos a HuggingFace
        
        Args:
            repo_name: Nombre del repositorio en HuggingFace (usuario/nombre-repo)
            token: Token de acceso a HuggingFace
            specific_model: Nombre específico del modelo a subir (sin extensión .pth)
        
        Returns:
            URL del repositorio en HuggingFace
        """
        
        if token is None:
            raise ValueError("Necesitas proporcionar un token de HuggingFace para subir archivos")
        
        if repo_name is None:
            # Usar un nombre por defecto basado en la fecha
            date_str = datetime.now().strftime("%Y%m%d-%H%M")
            repo_name = f"bro-vs-sis-models-{date_str}"
        
        # Comprobar si incluye el nombre de usuario
        if "/" not in repo_name:
            raise ValueError("El nombre del repositorio debe incluir tu nombre de usuario: 'usuario/nombre-repo'")
        
        # Inicializar API de HuggingFace
        api = HfApi()
        
        try:
            # Crear repositorio si no existe
            create_repo(repo_name, private=False, token=token)
            print(f"Repositorio creado: {repo_name}")
        except Exception as e:
            print(f"El repositorio ya existe o hubo un error: {e}")
        
        # Filtrar modelos según si se ha especificado uno concreto
        if specific_model:
            model_path = os.path.join(AIModels._models_folder, f"{specific_model}.pth")
            if not os.path.exists(model_path):
                raise ValueError(f"No se encontró el modelo {model_path}")
            model_files = [model_path]
        else:
            model_files = glob.glob(os.path.join(AIModels._models_folder, '*.pth'))
        
        # Subir modelos
        for model_file in model_files:
            try:
                upload_file(
                    path_or_fileobj=model_file,
                    path_in_repo=os.path.join("models", os.path.basename(model_file)),
                    repo_id=repo_name,
                    token=token
                )
                print(f"Modelo subido: {model_file}")
            except Exception as e:
                print(f"Error al subir {model_file}: {e}")
        
        # Filtrar videos correspondientes a los modelos seleccionados
        if specific_model:
            video_path = os.path.join(AIModels._videos_folder, f"{specific_model}.mp4")
            video_files = [video_path] if os.path.exists(video_path) else []
        else:
            video_files = glob.glob(os.path.join(AIModels._videos_folder, '*.mp4'))
        
        # Subir videos
        for video_file in video_files:
            try:
                upload_file(
                    path_or_fileobj=video_file,
                    path_in_repo=os.path.join("videos", os.path.basename(video_file)),
                    repo_id=repo_name,
                    token=token
                )
                print(f"Video subido: {video_file}")
            except Exception as e:
                print(f"Error al subir {video_file}: {e}")
        
        # Crear README.md
        readme_content = f"""# Bro VS Sis - Modelos entrenados

Este repositorio contiene modelos de IA entrenados para el juego Bro VS Sis.

## Modelos disponibles

{len(model_files)} modelos entrenados:
"""
        
        for model_file in model_files:
            model_name = os.path.basename(model_file)
            video_name = os.path.basename(model_file).replace('.pth', '.mp4')
            if os.path.exists(os.path.join(AIModels._videos_folder, video_name)):
                readme_content += f"- [{model_name}](models/{model_name}) - [Ver video](videos/{video_name})\n"
            else:
                readme_content += f"- [{model_name}](models/{model_name})\n"
        
        # Guardar README temporalmente y subirlo
        readme_path = "temp_readme.md"
        with open(readme_path, "w") as f:
            f.write(readme_content)
        
        try:
            upload_file(
                path_or_fileobj=readme_path,
                path_in_repo="README.md",
                repo_id=repo_name,
                token=token
            )
            print("README.md creado y subido")
        except Exception as e:
            print(f"Error al subir README.md: {e}")
        
        # Eliminar README temporal
        if os.path.exists(readme_path):
            os.remove(readme_path)
        
        return f"https://huggingface.co/{repo_name}"
