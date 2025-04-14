import pygame
from src.Button import Button
from src.Colors import WHITE, BLACK, RED, BLUE, GREEN, YELLOW, ORANGE, PURPLE

def draw_text(surface, text, font, text_col, x, y, shadow=True):
    if shadow:
        text_surface = font.render(text, True, (50, 50, 50))
        surface.blit(text_surface, (x + 2, y + 2))
    text_surface = font.render(text, True, text_col)
    surface.blit(text_surface, (x, y))

def character_select_screen(screen, WIDTH, HEIGHT):
    # Font setup
    title_font = pygame.font.SysFont('Arial', 60, True)
    subtitle_font = pygame.font.SysFont('Arial', 24)

    # Character color options
    p1_colors = [BLUE, GREEN, YELLOW, PURPLE]
    p2_colors = [RED, ORANGE, WHITE, BLACK]
    p1_selected_color = 0
    p2_selected_color = 0

    # Create buttons for color selection
    p1_prev = Button(WIDTH // 4 - 100, HEIGHT // 2, 50, 50, "<", (70, 130, 180), (100, 160, 210))
    p1_next = Button(WIDTH // 4 + 50, HEIGHT // 2, 50, 50, ">", (70, 130, 180), (100, 160, 210))
    p2_prev = Button(3 * WIDTH // 4 - 100, HEIGHT // 2, 50, 50, "<", (180, 70, 70), (210, 100, 100))
    p2_next = Button(3 * WIDTH // 4 + 50, HEIGHT // 2, 50, 50, ">", (180, 70, 70), (210, 100, 100))
    
    confirm_button = Button(WIDTH // 2 - 100, HEIGHT * 3 // 4, 200, 50, "CONFIRM", (70, 180, 70), (100, 210, 100))
    back_button = Button(WIDTH // 2 - 75, HEIGHT * 3 // 4 + 70, 150, 50, "Back", (180, 70, 70), (210, 100, 100))

    running = True
    while running:
        mouse_pos = pygame.mouse.get_pos()

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                return None, None
            if event.type == pygame.MOUSEBUTTONDOWN:
                if p1_prev.is_clicked(event):
                    p1_selected_color = (p1_selected_color - 1) % len(p1_colors)
                elif p1_next.is_clicked(event):
                    p1_selected_color = (p1_selected_color + 1) % len(p1_colors)
                elif p2_prev.is_clicked(event):
                    p2_selected_color = (p2_selected_color - 1) % len(p2_colors)
                elif p2_next.is_clicked(event):
                    p2_selected_color = (p2_selected_color + 1) % len(p2_colors)
                elif confirm_button.is_clicked(event):
                    return p1_colors[p1_selected_color], p2_colors[p2_selected_color]
                elif back_button.is_clicked(event):
                    return None, None

        # Draw
        screen.fill(BLACK)
        
        # Draw title
        title_text = "SELECT YOUR CHARACTERS"
        draw_text(screen, title_text, title_font, WHITE, 
                 WIDTH // 2 - title_font.size(title_text)[0] // 2, HEIGHT // 4)

        # Draw player sections
        draw_text(screen, "Player 1", subtitle_font, WHITE, WIDTH // 4 - 50, HEIGHT // 3)
        draw_text(screen, "Player 2", subtitle_font, WHITE, 3 * WIDTH // 4 - 50, HEIGHT // 3)

        # Draw character previews
        pygame.draw.rect(screen, p1_colors[p1_selected_color], 
                        (WIDTH // 4 - 25, HEIGHT // 2, 75, 150))
        pygame.draw.rect(screen, p2_colors[p2_selected_color], 
                        (3 * WIDTH // 4 - 25, HEIGHT // 2, 75, 150))

        # Update and draw buttons
        for button in [p1_prev, p1_next, p2_prev, p2_next, confirm_button, back_button]:
            button.update(mouse_pos)
            button.draw(screen)

        pygame.display.update()

    return None, None