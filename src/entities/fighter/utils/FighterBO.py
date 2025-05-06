import pygame
import os
from src.utils.Colors import BLUE, RED, GRAY

class FighterBO:
    """
    Clase que representa los datos de negocio de un luchador, incluyendo su nombre, color,
    y las rutas a las imágenes para sus diferentes animaciones.
    """
    # Diccionario para almacenar animaciones precargadas
    _precached_fighters = {}
    
    def __init__(self, name, color, assets_folder=None):
        self.name = name
        self.color = color
        self.animations = {}
        self.frame_durations = {}  # Nuevo: diccionario para almacenar la duración de cada frame
        self.default_frame_duration = 5  # Nuevo: duración predeterminada para cada frame (en frames de juego)
        
        # Verificar si ya existe una versión precargada de este luchador
        fighter_key = f"{name}_{color[0]}_{color[1]}_{color[2]}"
        if fighter_key in FighterBO._precached_fighters:
            # Usar la versión precargada
            cached_fighter = FighterBO._precached_fighters[fighter_key]
            self.animations = cached_fighter.animations
            self.frame_durations = cached_fighter.frame_durations
        # Si no hay versión precargada y se proporciona una carpeta de assets, cargar las imágenes
        elif assets_folder and os.path.exists(assets_folder):
            self._load_animations(assets_folder)
        else:
            # Si no hay carpeta de assets, se usará el color para dibujar el luchador
            self.animations = None
    
    @staticmethod
    def get_characters():
        """
        Método estático que retorna la información de los personajes disponibles.
        
        Returns:
            list: Lista de diccionarios con la información de cada personaje:
                  color, nombre y carpeta de assets.
        """
        return [
            {
                "color": BLUE, 
                "name": "Rafaeh", 
                "assets_folder": os.path.join("assets", "images", "atlas", "originals", "rafael")
            },
            {
                "color": RED, 
                "name": "Matilde", 
                "assets_folder": os.path.join("assets", "images", "atlas", "originals", "matilde")
            },
            {
                "color": GRAY, 
                "name": "Robot", 
                "assets_folder": os.path.join("assets", "images", "atlas", "originals", "unknown")
            },
        ]
    
    @classmethod
    def get_fighter(cls, character_info):
        """
        Método de clase que crea un objeto FighterBO a partir de la información del personaje.
        
        Args:
            character_info (dict): Diccionario con la información del personaje:
                                  color, nombre y carpeta de assets.
        
        Returns:
            FighterBO: Objeto FighterBO con los datos del personaje.
        """
        return cls(
            character_info["name"],
            character_info["color"],
            character_info["assets_folder"]
        )
    
    def set_frame_duration(self, action, duration):
        """
        Establece la duración para todos los frames de una acción específica.
        
        Args:
            action (str): Nombre de la acción (idle, run, attack, etc.)
            duration (int): Duración en frames de juego (60 frames = 1 segundo a 60fps)
        """
        if action not in self.frame_durations:
            self.frame_durations[action] = {}
            
        # Si la acción tiene frames de animación
        if action in self.animations and self.animations[action]:
            for i in range(len(self.animations[action])):
                self.frame_durations[action][i] = duration
    
    def set_specific_frame_duration(self, action, frame_index, duration):
        """
        Establece la duración para un frame específico de una acción.
        
        Args:
            action (str): Nombre de la acción (idle, run, attack, etc.)
            frame_index (int): Índice del frame en la animación
            duration (int): Duración en frames de juego (60 frames = 1 segundo a 60fps)
        """
        if action not in self.frame_durations:
            self.frame_durations[action] = {}
            
        self.frame_durations[action][frame_index] = duration
    
    def get_frame_duration(self, action, frame_index):
        """
        Obtiene la duración de un frame específico.
        
        Args:
            action (str): Nombre de la acción
            frame_index (int): Índice del frame
            
        Returns:
            int: Duración del frame en frames de juego
        """
        if action in self.frame_durations and frame_index in self.frame_durations[action]:
            return self.frame_durations[action][frame_index]
        return self.default_frame_duration
    
    def _load_animations(self, assets_folder):
        """
        Carga las imágenes de animación desde la carpeta de assets.
        La estructura esperada es: 
        assets_folder/
            idle/
                frame1.png
                frame2.png
            run/
                frame1.png
                frame2.png
            attack/
                frame1.png
                frame2.png
            etc.
        """
        # Diccionario para almacenar las animaciones
        animations = {}
        
        # Verificar si la carpeta existe
        if not os.path.exists(assets_folder):
            print(f"¡Advertencia! La carpeta de assets no existe: {assets_folder}")
            # Intentar usar la ruta alternativa sin 'originals'
            alternative_path = assets_folder.replace(os.path.join("atlas", "originals"), "atlas")
            if os.path.exists(alternative_path):
                print(f"Usando ruta alternativa: {alternative_path}")
                assets_folder = alternative_path
            else:
                print(f"No se pudo encontrar la carpeta de assets: {alternative_path}")
                self._generate_simple_animations(animations)
                return
        
        # Listar todas las subcarpetas (cada una representa una acción)
        try:
            for action in os.listdir(assets_folder):
                action_path = os.path.join(assets_folder, action)
                
                # Verificar que sea un directorio
                if os.path.isdir(action_path):
                    # Listar todas las imágenes en la carpeta de la acción
                    frames = []
                    try:
                        # Ordenar los archivos numéricamente
                        frame_files = sorted(os.listdir(action_path), 
                                          key=lambda x: int(x.split('_')[-1].split('.')[0]) 
                                          if x.lower().endswith(('.png', '.jpg', '.bmp')) and '_' in x 
                                          else x)
                        
                        for frame_file in frame_files:
                            if frame_file.lower().endswith(('.png', '.jpg', '.bmp')):
                                frame_path = os.path.join(action_path, frame_file)
                                try:
                                    # Cargar la imagen y reducir su tamaño si es muy grande
                                    image = pygame.image.load(frame_path).convert_alpha()
                                    
                                    # Si la imagen es muy grande, reducirla
                                    if image.get_width() > 200 or image.get_height() > 200:
                                        scale = min(200 / image.get_width(), 200 / image.get_height())
                                        new_width = int(image.get_width() * scale)
                                        new_height = int(image.get_height() * scale)
                                        image = pygame.transform.scale(image, (new_width, new_height))
                                    
                                    frames.append(image)
                                except pygame.error as e:
                                    print(f"Error al cargar imagen {frame_path}: {e}")
                                    # Si hay error de memoria, intentar reducir la calidad o saltar esta imagen
                                    if "Out of memory" in str(e):
                                        print(f"Saltando imagen por falta de memoria: {frame_path}")
                                        continue
                        
                        # Si se encontraron frames, agregar la acción al diccionario
                        if frames:
                            animations[action] = frames
                            
                            # Establecer duraciones predeterminadas para cada acción
                            if action == "idle":
                                self.set_frame_duration(action, 10)  # Más lento para idle
                            elif action == "attack":
                                self.set_frame_duration(action, 8)  # Ataques un poco rápidos
                            else:
                                self.set_frame_duration(action, self.default_frame_duration)
                            
                    except Exception as e:
                        print(f"Error al procesar la carpeta de acción {action_path}: {e}")
        except Exception as e:
            print(f"Error al acceder a la carpeta {assets_folder}: {e}")
            
        if not animations:
            print(f"¡Advertencia! No se encontraron animaciones en {assets_folder}. Generando sprites simples.")
            self._generate_simple_animations(animations)
        
        self.animations = animations
    @classmethod
    def load_fighter_data(cls, name, color, lowResources=False):
        """
        Método de clase que carga los datos de un luchador según su nombre.
        
        Args:
            name (str): Nombre del luchador
            color (tuple): Color del luchador
            lowResources (bool): Indica si se deben cargar animaciones
            
        Returns:
            FighterBO: Objeto FighterBO con los datos del personaje
        """
        if lowResources:
            return cls(name, color)
        
        # Intentar diferentes rutas de assets
        base_paths = [
            os.path.join("assets", "images", "atlas"),
            os.path.join("assets", "images", "atlas", "originals")
        ]
        
        # Determinar la carpeta de assets según el nombre del luchador
        character_folder = ""
        name_lower = name.lower()
        if "rafael" in name_lower or "rafaeh" in name_lower:
            character_folder = "rafael"
        elif "matilde" in name_lower:
            character_folder = "matilde"
        else:
            character_folder = "unknown"
        
        # Intentar cada ruta base hasta encontrar una que funcione
        fighter_bo = None
        for base_path in base_paths:
            assets_folder = os.path.join(base_path, character_folder)
            print(f"Intentando cargar desde: {assets_folder}")
            
            if os.path.exists(assets_folder):
                fighter_bo = cls(name, color, assets_folder)
                if fighter_bo.has_animations():
                    print(f"Animaciones cargadas correctamente desde {assets_folder}")
                    break
            else:
                print(f"Ruta no encontrada: {assets_folder}")
        
        # Si no se pudo cargar ninguna animación, usar una representación simple
        if fighter_bo is None or not fighter_bo.has_animations():
            print(f"No se pudieron cargar animaciones para {name}. Usando representación simple.")
            fighter_bo = cls(name, color)
        
        return fighter_bo
    
    def _generate_simple_animations(self, animations):
        """
        Genera animaciones simples como respaldo cuando no se pueden cargar las imágenes
        """
        print("Generando sprites simples para el personaje")
        actions = ["idle", "run", "jump", "attack", "shoot", "protect", "defeated"]
        
        # Crear una superficie base para el personaje
        width, height = 60, 120
        
        for action in actions:
            frames = []
            # Generar 2-4 frames para cada acción
            num_frames = 2 if action == "idle" else 4
            
            for i in range(num_frames):
                # Crear una superficie con transparencia
                image = pygame.Surface((width, height), pygame.SRCALPHA)
                
                # Dibujar un personaje simple
                # Cuerpo
                pygame.draw.rect(image, self.color, (10, 30, 40, 70))
                
                # Cabeza
                pygame.draw.circle(image, self.color, (30, 20), 15)
                
                # Ojos
                eye_color = (255, 255, 255)
                pygame.draw.circle(image, eye_color, (25, 15), 4)
                pygame.draw.circle(image, eye_color, (35, 15), 4)
                
                # Pupila
                pupil_color = (0, 0, 0)
                pupil_offset = 1 if i % 2 == 0 else -1  # Mover pupilas para simular animación
                pygame.draw.circle(image, pupil_color, (25 + pupil_offset, 15), 2)
                pygame.draw.circle(image, pupil_color, (35 + pupil_offset, 15), 2)
                
                # Personalizar según la acción
                if action == "run":
                    # Piernas en posición de carrera
                    leg_pos = 10 if i % 2 == 0 else -10
                    pygame.draw.rect(image, self.color, (15, 100, 10, 20 + leg_pos))
                    pygame.draw.rect(image, self.color, (35, 100, 10, 20 - leg_pos))
                elif action == "jump":
                    # Posición de salto
                    pygame.draw.rect(image, self.color, (15, 100, 10, 15))
                    pygame.draw.rect(image, self.color, (35, 100, 10, 15))
                    # Efecto de salto
                    if i % 2 == 0:
                        image = pygame.transform.scale(image, (width, int(height * 0.9)))
                elif action == "attack":
                    # Brazo extendido para ataque
                    arm_extend = 20 if i % 2 == 0 else 30
                    pygame.draw.rect(image, self.color, (50, 40, arm_extend, 10))
                elif action == "shoot":
                    # Posición de disparo
                    pygame.draw.rect(image, self.color, (50, 50, 15, 5))
                    # Efecto de disparo
                    if i % 2 == 0:
                        pygame.draw.circle(image, (255, 100, 0), (70, 52), 5)
                elif action == "defeated":
                    # Personaje derrotado
                    # Rotar la imagen para que esté acostado
                    image = pygame.transform.rotate(image, 90)
                
                frames.append(image)
            
            # Añadir la acción al diccionario de animaciones
            animations[action] = frames
            
            # Establecer duraciones predeterminadas para los sprites generados
            if action == "idle":
                self.set_frame_duration(action, 15)  # Idle más lento
            elif action == "attack":
                self.set_frame_duration(action, 8)  # Ataques más rápidos
            elif action == "defeated":
                self.set_frame_duration(action, 12)  # Animación de derrota más lenta
            else:
                self.set_frame_duration(action, 10)  # Duración predeterminada
        
        return animations
    
    def get_animation_frames(self, action):
        """
        Obtiene los frames de una animación específica.
        
        Args:
            action (str): Nombre de la acción (idle, run, attack, etc.)
            
        Returns:
            list: Lista de imágenes para la animación o None si no existe
        """
        if self.animations and action in self.animations:
            return self.animations[action]
        return None
    
    def has_animations(self):
        """Devuelve True si el luchador tiene animaciones cargadas"""
        return self.animations is not None and len(self.animations) > 0

    @classmethod
    def preload_all_fighters(cls):
        """
        Precarga todas las animaciones de los personajes disponibles para evitar cargas repetitivas durante el juego.
        Debe llamarse una vez al inicio del juego.
        """
        print("Precargando animaciones de personajes...")
        characters = cls.get_characters()
        for character in characters:
            name = character["name"]
            color = character["color"]
            assets_folder = character["assets_folder"]
            
            # Crear clave única para este luchador
            fighter_key = f"{name}_{color[0]}_{color[1]}_{color[2]}"
            
            # Verificar si ya está precargado
            if fighter_key not in cls._precached_fighters:
                print(f"Precargando animaciones para {name}...")
                fighter_bo = cls(name, color, assets_folder)
                if fighter_bo.has_animations():
                    cls._precached_fighters[fighter_key] = fighter_bo
                    print(f"Animaciones de {name} precargadas correctamente.")
                else:
                    print(f"No se pudieron precargar animaciones para {name}.")
        
        print(f"Precarga completa. {len(cls._precached_fighters)} personajes cargados.")
        return len(cls._precached_fighters) > 0