import random

# Screen shake effect
class ScreenShake:
    def __init__(self):
        self.intensity = 0
        self.original_camera_pos = [0, 0]
    
    def start(self, intensity=5, decay=0.8):
        self.intensity = intensity
        self.decay = decay
    
    def update(self):
        if self.intensity > 0:
            dx = random.randint(-int(self.intensity), int(self.intensity))
            dy = random.randint(-int(self.intensity), int(self.intensity))
            self.intensity *= self.decay
            
            if self.intensity < 0.1:
                self.intensity = 0
            
            return [dx, dy]
        return [0, 0]

global screen_shake
screen_shake = ScreenShake()