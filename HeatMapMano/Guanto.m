%% 1. Caricamento e Mascheramento dell'Immagine
clear; clc; close all;

try
    img = imread('mano.jpeg');
catch
    error('Immagine "mano.jpeg" non trovata. Controlla il nome del file nella directory.');
end

% Conversione in scala di grigi
if size(img, 3) == 3
    img_gray = rgb2gray(img);
else
    img_gray = img;
end

% Creazione Maschera (Assumendo sfondo chiaro e mano scura)
mask = ~imbinarize(img_gray); 

% Pulizia della maschera (rimuove piccoli puntini o rumore)
mask = bwareaopen(mask, 500); 

%% 2. Visualizzazione (Silhouette Nera su Sfondo Bianco)
figure('Name', 'Mappa Spaziale 2D: Maschera Grip', 'NumberTitle', 'off', 'Color', 'w');

% Visualizziamo la maschera invertita.
% mask è True (1) sulla mano. Invertendo (~mask), la mano diventa 0 (nero) 
% e lo sfondo diventa 1 (bianco).
imshow(~mask); 

% Rimuove gli assi di riferimento (numeri e tacche)
axis off; 

title('Postura Grip: Maschera Area di Analisi');

%%
hold on
plot(0,0,'o')