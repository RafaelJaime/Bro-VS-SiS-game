import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
import os
import numpy as np

class Linear_QNet(nn.Module):
    def __init__(self, input_size, hidden_size, output_size):
        super().__init__()
        self.linear1 = nn.Linear(input_size, hidden_size)
        self.linear2 = nn.Linear(hidden_size, output_size)

    def forward(self, x):
        x = F.relu(self.linear1(x))
        x = self.linear2(x)
        return x

    def save(self, file_name='model.pth'):
        # Extract directory path from file_name if it includes a path
        model_folder_path = os.path.dirname(file_name)
        if not model_folder_path:
            # If no directory specified, use default './model' directory
            model_folder_path = './model'
            file_name = os.path.join(model_folder_path, os.path.basename(file_name))
            
        if not os.path.exists(model_folder_path):
            os.makedirs(model_folder_path)

        torch.save(self.state_dict(), file_name)
        
    @classmethod
    def load(cls, input_size, hidden_size, output_size, file_name='model.pth'):
        """
        Carga un modelo guardado desde un archivo
        
        Args:
            input_size: Tamaño de la capa de entrada
            hidden_size: Tamaño de la capa oculta
            output_size: Tamaño de la capa de salida
            file_name: Ruta al archivo del modelo guardado
            
        Returns:
            Instancia de Linear_QNet con los pesos cargados
        """
        model = cls(input_size, hidden_size, output_size)
        
        # Si el archivo incluye una ruta completa, úsala directamente
        if not os.path.exists(file_name):
            # Intenta buscar en la carpeta ./model por defecto
            model_folder_path = './model'
            alternative_path = os.path.join(model_folder_path, os.path.basename(file_name))
            if os.path.exists(alternative_path):
                file_name = alternative_path
        
        if os.path.exists(file_name):
            model.load_state_dict(torch.load(file_name))
            model.eval()  # Establece el modelo en modo evaluación
            print(f"Modelo cargado desde {file_name}")
        else:
            print(f"No se pudo encontrar el archivo del modelo: {file_name}")
            
        return model

class QTrainer:
    def __init__(self, model, lr, gamma):
        self.lr = lr
        self.gamma = gamma
        self.model = model
        self.optimizer = optim.Adam(model.parameters(), lr=self.lr)
        self.criterion = nn.MSELoss()

    def train_step(self, state, action, reward, next_state, done):
        # Convert lists of numpy arrays to a single numpy array first if needed
        if isinstance(state, list):
            state = np.array(state)
        if isinstance(next_state, list):
            next_state = np.array(next_state)
        if isinstance(action, list):
            action = np.array(action)
        if isinstance(reward, list):
            reward = np.array(reward)
            
        # Convert numpy arrays to tensors
        state = torch.tensor(state, dtype=torch.float)
        next_state = torch.tensor(next_state, dtype=torch.float)
        action = torch.tensor(action, dtype=torch.long)
        reward = torch.tensor(reward, dtype=torch.float)
        # (n, x)

        if len(state.shape) == 1:
            # (1, x)
            state = torch.unsqueeze(state, 0)
            next_state = torch.unsqueeze(next_state, 0)
            action = torch.unsqueeze(action, 0)
            reward = torch.unsqueeze(reward, 0)
            done = (done, )

        # 1: predicted Q values with current state
        pred = self.model(state)

        target = pred.clone()
        for idx in range(len(done)):
            Q_new = reward[idx]
            if not done[idx]:
                Q_new = reward[idx] + self.gamma * torch.max(self.model(next_state[idx]))

            target[idx][torch.argmax(action[idx]).item()] = Q_new
    
        # 2: Q_new = r + y * max(next_predicted Q value) -> only do this if not done
        self.optimizer.zero_grad()
        loss = self.criterion(target, pred)
        loss.backward()

        self.optimizer.step()
