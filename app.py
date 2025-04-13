import pygame
import sys
import random
from src.Fighter import Fighter
from src.Button import Button
from src.Colors import BLACK, WHITE, RED, BLUE
from src.ScreenShake import screen_shake

# Initialize pygame
pygame.init()

# Screen dimensions
WIDTH, HEIGHT = 800, 600
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Pygame Fighter")



# Function to draw text
def draw_text(surface, text, font, text_col, x, y, shadow=True):
    if shadow:
        shadow_img = font.render(text, True, BLACK)
        surface.blit(shadow_img, (x + 2, y + 2))
    
    img = font.render(text, True, text_col)
    surface.blit(img, (x, y))

# Main function
def main():
    clock = pygame.time.Clock()
    font = pygame.font.SysFont('Arial', 30)
    
    # Create ground
    ground = pygame.Rect(0, HEIGHT - 50, WIDTH, 50)
    
    
    # Create fighters
    player1_controls = {
        'left': pygame.K_a,
        'right': pygame.K_d,
        'up': pygame.K_w,
        'attack': pygame.K_f
    }
    
    player2_controls = {
        'left': pygame.K_LEFT,
        'right': pygame.K_RIGHT,
        'up': pygame.K_UP,
        'attack': pygame.K_k
    }
    
    player1 = Fighter(100, HEIGHT - 150, 50, 100, BLUE, player1_controls, "Player 1")
    player2 = Fighter(700, HEIGHT - 150, 50, 100, RED, player2_controls, "Player 2")
    
    # Background stars
    stars = []
    for _ in range(80):  # Increased number of stars for larger screen
        x = random.randint(0, WIDTH)
        y = random.randint(0, HEIGHT - 50)
        size = random.uniform(0.5, 2)
        brightness = random.randint(100, 255)
        color = (brightness, brightness, brightness)
        stars.append([x, y, size, color])
    
    # Create buttons for the game over screen
    restart_button = Button(WIDTH // 2 - 160, HEIGHT // 2, 140, 50, "Restart", (70, 130, 180), (100, 160, 210))
    menu_button = Button(WIDTH // 2 + 20, HEIGHT // 2, 140, 50, "Main Menu", (180, 70, 70), (210, 100, 100))
    
    # Difficulty selection buttons
    pvp_button = Button(WIDTH // 2 - 200, HEIGHT // 2 - 50, 400, 50, "Player vs Player", (70, 130, 180), (100, 160, 210))
    pvc_button = Button(WIDTH // 2 - 200, HEIGHT // 2 + 20, 400, 50, "Player vs Computer", (70, 180, 130), (100, 210, 160))
    cvc_button = Button(WIDTH // 2 - 200, HEIGHT // 2 + 90, 400, 50, "Computer vs Computer", (130, 70, 180), (160, 100, 210))
    back_button = Button(WIDTH // 2 - 75, HEIGHT // 2 + 160, 150, 50, "Back", (180, 70, 70), (210, 100, 100))
    
    # Game states
    PLAYING = 0
    GAME_OVER = 1
    MAIN_MENU = 2
    DIFFICULTY_SELECT = 3

    # Game modes
    MODE_PVP = 0
    MODE_PVC = 1  # Player vs Computer
    MODE_CVC = 2  # Computer vs Computer

    game_state = MAIN_MENU
    game_mode = MODE_PVP  # Default mode
    
    # Main menu setup
    title_font = pygame.font.SysFont('Arial', 60, True)
    start_button = Button(WIDTH // 2 - 75, HEIGHT // 2, 150, 50, "Start Game", (70, 130, 180), (100, 160, 210))
    exit_button = Button(WIDTH // 2 - 75, HEIGHT // 2 + 70, 150, 50, "Exit", (180, 70, 70), (210, 100, 100))
    
    # Start with main menu
    game_state = MAIN_MENU
    
    # Game loop
    run = True
    while run:
        clock.tick(60)
        
        # Get mouse position
        mouse_pos = pygame.mouse.get_pos()
        
        # Event handler
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                run = False
            if event.type == pygame.KEYDOWN:
                if event.key == pygame.K_ESCAPE:
                    run = False
            
            # Handle button clicks
            if game_state == GAME_OVER:
                if restart_button.is_clicked(event):
                    # Reset the game
                    player1.health = 100
                    player2.health = 100
                    player1.is_defeated = False
                    player2.is_defeated = False
                    player1.defeat_animation = 0
                    player2.defeat_animation = 0
                    player1.rect.x = 100
                    player2.rect.x = 700
                    player1.rect.y = HEIGHT - 150
                    player2.rect.y = HEIGHT - 150
                    game_state = PLAYING
                elif menu_button.is_clicked(event):
                    game_state = MAIN_MENU
            
            elif game_state == MAIN_MENU:
                if start_button.is_clicked(event):
                    game_state = DIFFICULTY_SELECT  # Change to difficulty selection instead of starting game
                elif exit_button.is_clicked(event):
                    run = False
            
            elif game_state == DIFFICULTY_SELECT:
                if pvp_button.is_clicked(event):
                    game_mode = MODE_PVP
                    # Reset game and start
                    player1.health = 100
                    player2.health = 100
                    player1.is_defeated = False
                    player2.is_defeated = False
                    player1.score = 0
                    player2.score = 0
                    player1.defeat_animation = 0
                    player2.defeat_animation = 0
                    player1.rect.x = 100
                    player2.rect.x = 700
                    player1.rect.y = HEIGHT - 150
                    player2.rect.y = HEIGHT - 150
                    game_state = PLAYING
                elif pvc_button.is_clicked(event):
                    game_mode = MODE_PVC
                    # Similar reset but set player2 as AI
                    player1.health = 100
                    player2.health = 100
                    player1.is_defeated = False
                    player2.is_defeated = False
                    player1.score = 0
                    player2.score = 0
                    player1.defeat_animation = 0
                    player2.defeat_animation = 0
                    player1.rect.x = 100
                    player2.rect.x = 700
                    player1.rect.y = HEIGHT - 150
                    player2.rect.y = HEIGHT - 150
                    player2.is_ai = True
                    game_state = PLAYING
                elif cvc_button.is_clicked(event):
                    game_mode = MODE_CVC
                    # Similar reset but set both as AI
                    player1.health = 100
                    player2.health = 100
                    player1.is_defeated = False
                    player2.is_defeated = False
                    player1.score = 0
                    player2.score = 0
                    player1.defeat_animation = 0
                    player2.defeat_animation = 0
                    player1.rect.x = 100
                    player2.rect.x = 700
                    player1.rect.y = HEIGHT - 150
                    player2.rect.y = HEIGHT - 150
                    player1.is_ai = True
                    player2.is_ai = True
                    game_state = PLAYING
                elif back_button.is_clicked(event):
                    game_state = MAIN_MENU
        
        # Update screen shake
        camera_offset = screen_shake.update()
        
        # Draw background
        screen.fill(BLACK)
        
        # Draw stars
        for star in stars:
            pygame.draw.circle(screen, star[3], (star[0] + camera_offset[0], star[1] + camera_offset[1]), star[2])
        
        # Draw ground with offset
        pygame.draw.rect(screen, WHITE, (ground.x + camera_offset[0], ground.y + camera_offset[1], ground.width, ground.height))
        
        # Add ground texture
        for x in range(0, WIDTH, 20):
            height_var = random.randint(-2, 2)
            pygame.draw.line(screen, (200, 200, 200), 
                             (x + camera_offset[0], HEIGHT - 50 + camera_offset[1]), 
                             (x + camera_offset[0], HEIGHT - 15 + height_var + camera_offset[1]), 2)
        
        if game_state == PLAYING:
            # Check if game is over
            if player1.is_defeated or player2.is_defeated:
                # Wait for a short animation before showing game over screen
                if (player1.is_defeated and player1.defeat_animation > 60) or \
                   (player2.is_defeated and player2.defeat_animation > 60):
                    game_state = GAME_OVER
                    winner = player2 if player1.is_defeated else player1
            
            # Draw fighters
            player1.draw(screen, camera_offset)
            player2.draw(screen, camera_offset)
            
            # Only move fighters if neither is defeated
            if not player1.is_defeated and not player2.is_defeated:
                player1.move(player2)
                player2.move(player1)
            else:
                # Still update particles when a player is defeated
                player1.update_particles()
                player2.update_particles()
            
            # Draw UI panel at the top
            pygame.draw.rect(screen, (30, 30, 30), (0, 0, WIDTH, 60))
            pygame.draw.line(screen, (70, 70, 70), (0, 60), (WIDTH, 60), 2)
            
            # Draw player names and scores
            draw_text(screen, f"{player1.name}", font, BLUE, 20, 10)
            
            draw_text(screen, f"{player2.name}", font, RED, WIDTH - 150, 10)
            
            # Draw health bars in the top UI panel
            health_bar_width = 200
            player1.draw_health_bar(screen, 150, 18, health_bar_width)
            player2.draw_health_bar(screen, WIDTH - 350, 18, health_bar_width)
            
            # Draw controls info with shadow based on game mode
            if game_mode == MODE_PVP:
                draw_text(screen, "P1: WASD + F attack + G shoot", font, WHITE, 20, HEIGHT - 40)
                draw_text(screen, "P2: Arrows + K attack + L shoot", font, WHITE, WIDTH - 380, HEIGHT - 40)
            elif game_mode == MODE_PVC:
                draw_text(screen, "Controls: WASD + F attack + G shoot", font, WHITE, 20, HEIGHT - 40)
            elif game_mode == MODE_CVC:
                draw_text(screen, "AI Battle - Press ESC to exit", font, WHITE, WIDTH // 2 - 150, HEIGHT - 40)
        
        elif game_state == GAME_OVER:
            # Draw fighters in their current state (winner standing, loser defeated)
            player1.draw(screen, camera_offset)
            player2.draw(screen, camera_offset)
            
            # Update particles
            player1.update_particles()
            player2.update_particles()
            
            # Draw semi-transparent overlay
            overlay = pygame.Surface((WIDTH, HEIGHT), pygame.SRCALPHA)
            overlay.fill((0, 0, 0, 150))
            screen.blit(overlay, (0, 0))
            
            # Draw game over text
            victory_text = f"{winner.name} Wins!"
            draw_text(screen, victory_text, title_font, winner.color, WIDTH // 2 - title_font.size(victory_text)[0] // 2, HEIGHT // 2 - 100)
            
            # Update and draw buttons
            restart_button.update(mouse_pos)
            menu_button.update(mouse_pos)
            restart_button.draw(screen)
            menu_button.draw(screen)
        
        elif game_state == MAIN_MENU:
            # Draw title
            title_text = "PYGAME FIGHTER"
            draw_text(screen, title_text, title_font, WHITE, WIDTH // 2 - title_font.size(title_text)[0] // 2, HEIGHT // 4)
            
            # Draw subtitle
            subtitle_font = pygame.font.SysFont('Arial', 30)
            subtitle_text = "The Ultimate Battle"
            draw_text(screen, subtitle_text, subtitle_font, (200, 200, 200), 
                     WIDTH // 2 - subtitle_font.size(subtitle_text)[0] // 2, HEIGHT // 4 + 70)
            
            # Update and draw buttons
            start_button.update(mouse_pos)
            exit_button.update(mouse_pos)
            start_button.draw(screen)
            exit_button.draw(screen)
            
            # Draw credits
            credit_text = "Use WASD/Arrows to move, F/K to attack, G/L to shoot"
            small_font = pygame.font.SysFont('Arial', 20)
            draw_text(screen, credit_text, small_font, (200, 200, 200), 
                     WIDTH // 2 - small_font.size(credit_text)[0] // 2, HEIGHT - 30)
        
        elif game_state == DIFFICULTY_SELECT:
            # Draw title
            title_text = "SELECT GAME MODE"
            draw_text(screen, title_text, title_font, WHITE, WIDTH // 2 - title_font.size(title_text)[0] // 2, HEIGHT // 4)
            
            # Draw subtitle
            subtitle_font = pygame.font.SysFont('Arial', 24)
            subtitle_text = "Choose your battle mode"
            draw_text(screen, subtitle_text, subtitle_font, (200, 200, 200), 
                     WIDTH // 2 - subtitle_font.size(subtitle_text)[0] // 2, HEIGHT // 4 + 70)
            
            # Update and draw buttons
            pvp_button.update(mouse_pos)
            pvc_button.update(mouse_pos)
            cvc_button.update(mouse_pos)
            back_button.update(mouse_pos)
            
            pvp_button.draw(screen)
            pvc_button.draw(screen)
            cvc_button.draw(screen)
            back_button.draw(screen)
        
        pygame.display.update()
    
    pygame.quit()
    sys.exit()

if __name__ == "__main__":
    main()
