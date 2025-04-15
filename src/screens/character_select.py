import pygame
import random
import math
from src.Button import Button
from src.Colors import WHITE, BLACK, RED, BLUE, GREEN, YELLOW, ORANGE, PURPLE
from src.Particle import Particle
from src.Background import Background

def draw_text(surface, text, font, text_col, x, y, shadow=True):
    if shadow:
        text_surface = font.render(text, True, (50, 50, 50))
        surface.blit(text_surface, (x + 2, y + 2))
    text_surface = font.render(text, True, text_col)
    surface.blit(text_surface, (x, y))

def character_select_screen(screen, WIDTH, HEIGHT):
    clock = pygame.time.Clock()
    
    # Font setup
    title_font = pygame.font.SysFont('Arial', 60, True)
    info_font = pygame.font.SysFont('Arial', 20)

    # Create back button
    back_button = Button(WIDTH // 2 - 75, HEIGHT // 2 + 160, 150, 50, "Back", (180, 70, 70), (210, 100, 100))
    
    # Character options with names, colors and stats
    characters = [
        {"color": BLUE, "name": "RYU"},
        {"color": GREEN, "name": "BLANKA"},
        {"color": YELLOW, "name": "GUILE"},
        {"color": PURPLE, "name": "JURI"},
        {"color": RED, "name": "KEN"},
        {"color": ORANGE, "name": "DHALSIM"},
    ]
    
    # Grid layout settings
    grid_cols = 3
    grid_rows = 3
    portrait_width = 80
    portrait_height = 100
    portrait_gap = 20
    
    # Calculate grid position to center it
    grid_width = grid_cols * portrait_width + (grid_cols - 1) * portrait_gap
    grid_height = grid_rows * portrait_height + (grid_rows - 1) * portrait_gap
    grid_start_x = (WIDTH - grid_width) // 2
    grid_start_y = 150
    
    # Character selection variables
    p1_selected = 0
    p2_selected = len(characters) - 1
    p1_locked = False
    p2_locked = False
    
    # Create background
    background = Background(WIDTH, HEIGHT)
    
    # Create particles list
    particles = []
    
    running = True
    while running:
        clock.tick(60)
        
        # Get mouse position for button update
        mouse_pos = pygame.mouse.get_pos()
        
        # Handle events
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return None, None
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    return None, None
                
                # Player 1 controls
                if not p1_locked:
                    if event.key == pygame.K_a:
                        old_selection = p1_selected
                        p1_selected = (p1_selected - 1) % len(characters)
                        while p1_selected == p2_selected:  # Skip if color is selected by P2
                            p1_selected = (p1_selected - 1) % len(characters)
                    elif event.key == pygame.K_d:
                        old_selection = p1_selected
                        p1_selected = (p1_selected + 1) % len(characters)
                        while p1_selected == p2_selected:  # Skip if color is selected by P2
                            p1_selected = (p1_selected + 1) % len(characters)
                    elif event.key == pygame.K_w:
                        old_selection = p1_selected
                        p1_selected = (p1_selected - grid_cols) % len(characters)
                        while p1_selected == p2_selected:  # Skip if color is selected by P2
                            p1_selected = (p1_selected - grid_cols) % len(characters)
                    elif event.key == pygame.K_s:
                        old_selection = p1_selected
                        p1_selected = (p1_selected + grid_cols) % len(characters)
                        while p1_selected == p2_selected:  # Skip if color is selected by P2
                            p1_selected = (p1_selected + grid_cols) % len(characters)
                
                # Player 2 controls
                if not p2_locked:
                    if event.key == pygame.K_LEFT:
                        old_selection = p2_selected
                        p2_selected = (p2_selected - 1) % len(characters)
                        while p2_selected == p1_selected:  # Skip if color is selected by P1
                            p2_selected = (p2_selected - 1) % len(characters)
                    elif event.key == pygame.K_RIGHT:
                        old_selection = p2_selected
                        p2_selected = (p2_selected + 1) % len(characters)
                        while p2_selected == p1_selected:  # Skip if color is selected by P1
                            p2_selected = (p2_selected + 1) % len(characters)
                    elif event.key == pygame.K_UP:
                        old_selection = p2_selected
                        p2_selected = (p2_selected - grid_cols) % len(characters)
                        while p2_selected == p1_selected:  # Skip if color is selected by P1
                            p2_selected = (p2_selected - grid_cols) % len(characters)
                    elif event.key == pygame.K_DOWN:
                        old_selection = p2_selected
                        p2_selected = (p2_selected + grid_cols) % len(characters)
                        while p2_selected == p1_selected:  # Skip if color is selected by P1
                            p2_selected = (p2_selected + grid_cols) % len(characters)
                
                # Lock selections
                if event.key == pygame.K_f:
                    p1_locked = True
                if event.key == pygame.K_k:
                    p2_locked = True
                
                # Start game when both players are locked
                if p1_locked and p2_locked:
                    return characters[p1_selected]["color"], characters[p2_selected]["color"]
            
            # Update and handle back button
            back_button.update(mouse_pos)
            if back_button.is_clicked(event):
                return None, None

        # Draw background using Background class
        background.draw(screen)
        background.update()
        
        # Draw UI panel at the top
        pygame.draw.rect(screen, (30, 30, 40), (0, 0, WIDTH, 80))
        pygame.draw.line(screen, (70, 70, 80), (0, 80), (WIDTH, 80), 2)
        
        # Draw title
        title_text = "SELECT YOUR FIGHTER"
        draw_text(screen, title_text, title_font, WHITE,
                 WIDTH // 2 - title_font.size(title_text)[0] // 2, 15)
        
        # Draw control instructions
        controls_text = "P1: WASD to move, F to lock  |  P2: ←↑↓→ to move, K to lock"
        draw_text(screen, controls_text, info_font, WHITE, 
                 WIDTH // 2 - info_font.size(controls_text)[0] // 2, 85)
        
        # Draw character grid
        for i, character in enumerate(characters):
            row = i // grid_cols
            col = i % grid_cols
            portrait_x = grid_start_x + col * (portrait_width + portrait_gap)
            portrait_y = grid_start_y + row * (portrait_height + portrait_gap)
            
            # Draw portrait background
            pygame.draw.rect(screen, (50, 50, 60), 
                            (portrait_x, portrait_y, portrait_width, portrait_height))
            
            # Draw character silhouette (reduciendo la altura en -40 en lugar de -30 para dejar más espacio al nombre)
            pygame.draw.rect(screen, character["color"], 
                            (portrait_x + 10, portrait_y + 10, portrait_width - 20, portrait_height - 40))
            
            # Draw character name
            name_text = character["name"]
            name_surface = info_font.render(name_text, True, WHITE)
            name_rect = name_surface.get_rect(centerx=portrait_x + portrait_width // 2, y=portrait_y + portrait_height - 25)
            screen.blit(name_surface, name_rect)
            
            # Draw selection frames
            if i == p1_selected:
                frame_color = BLUE if not p1_locked else (0, 255, 0)
                pygame.draw.rect(screen, frame_color, 
                                (portrait_x - 4, portrait_y - 4, portrait_width + 8, portrait_height + 8), 3)
                draw_text(screen, "P1", info_font, frame_color, portrait_x + portrait_width // 2 - 10, portrait_y - 25)
            
            if i == p2_selected:
                frame_color = RED if not p2_locked else (0, 255, 0)
                pygame.draw.rect(screen, frame_color, 
                                (portrait_x - 4, portrait_y - 4, portrait_width + 8, portrait_height + 8), 3)
                draw_text(screen, "P2", info_font, frame_color, portrait_x + portrait_width // 2 - 10, portrait_y - 25)
        
        # Draw large character previews on left and right sides - adjusted positions
        preview_width = 200
        preview_height = 400
        p1_preview_rect = pygame.Rect(0, HEIGHT//2 - preview_height//2, preview_width, preview_height)
        draw_character_preview(screen, p1_preview_rect, characters[p1_selected]["color"], characters[p1_selected]["name"], BLUE if not p1_locked else (0, 255, 0))
        
        p2_preview_rect = pygame.Rect(WIDTH - preview_width, HEIGHT//2 - preview_height//2, preview_width, preview_height)
        draw_character_preview(screen, p2_preview_rect, characters[p2_selected]["color"], characters[p2_selected]["name"], RED if not p2_locked else (0, 255, 0))
        
        # Draw particles
        for particle in particles:
            particle.draw(screen)
        update_particles(particles)

        # Draw back button
        back_button.draw(screen)
        
        # Draw ESC instruction
        esc_text = "Press ESC to go back"
        draw_text(screen, esc_text, info_font, (200, 200, 200),
                 WIDTH // 2 - info_font.size(esc_text)[0] // 2, HEIGHT - 30)
        
        pygame.display.update()
    
    return None, None

def draw_character_preview(screen, rect, color, name, player_color):
    # Draw frame background with gradient effect
    gradient_rect = pygame.Surface((rect.width, rect.height), pygame.SRCALPHA)
    for y in range(rect.height):
        alpha = max(150 - y//3, 30)
        pygame.draw.line(gradient_rect, (*player_color[:3], alpha), (0, y), (rect.width, y))
    screen.blit(gradient_rect, (rect.x, rect.y))
    
    # Draw outer border
    pygame.draw.rect(screen, player_color, rect, 4, border_radius=5)
    
    # Draw character silhouette
    char_width = rect.width - 40
    char_height = rect.height - 100
    char_x = rect.x + (rect.width - char_width) // 2
    char_y = rect.y + 30
    
    # Draw the character with slightly different proportions
    # Head
    head_size = char_width // 2
    pygame.draw.rect(screen, color, 
                   (char_x + char_width//4, char_y, head_size, head_size))
    
    # Body
    body_width = char_width - 20
    body_height = char_height - head_size - 20
    pygame.draw.rect(screen, color, 
                   (char_x + 10, char_y + head_size + 10, body_width, body_height))
    
    # Add some shading/highlights
    highlight = (min(color[0] + 50, 255), min(color[1] + 50, 255), min(color[2] + 50, 255))
    pygame.draw.rect(screen, highlight, 
                   (char_x + char_width//4, char_y, head_size//2, 5))
    pygame.draw.rect(screen, highlight, 
                   (char_x + 10, char_y + head_size + 10, 5, body_height))
    
    # Draw character name plate at bottom
    name_plate_height = 40
    pygame.draw.rect(screen, (20, 20, 25), 
                    (rect.x, rect.y + rect.height - name_plate_height, rect.width, name_plate_height),
                    border_radius=5)
    pygame.draw.rect(screen, player_color, 
                    (rect.x, rect.y + rect.height - name_plate_height, rect.width, name_plate_height),
                    2, border_radius=5)
    
    # Draw name
    name_font = pygame.font.SysFont('Arial', 24, True)
    name_surface = name_font.render(name, True, WHITE)
    name_rect = name_surface.get_rect(center=(rect.x + rect.width // 2, rect.y + rect.height - name_plate_height // 2))
    screen.blit(name_surface, name_rect)

def add_selection_particles(particles, x, y, color):
    for _ in range(15):
        angle = random.uniform(0, 2 * 3.14159)
        speed = random.uniform(1, 5)
        vel_x = math.cos(angle) * speed
        vel_y = math.sin(angle) * speed
        size = random.uniform(2, 6)
        lifetime = random.randint(20, 40)
        
        # Create particles with color variation
        r, g, b = color
        r_var = max(0, min(255, r + random.randint(-30, 30)))
        g_var = max(0, min(255, g + random.randint(-30, 30)))
        b_var = max(0, min(255, b + random.randint(-30, 30)))
        
        particles.append(Particle(x, y, (r_var, g_var, b_var), size, (vel_x, vel_y), True, lifetime))

def update_particles(particles):
    i = 0
    while i < len(particles):
        if particles[i].update():
            particles.pop(i)
        else:
            i += 1