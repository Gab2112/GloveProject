clear; 
close all;
clc;

% === 1. IMPOSTAZIONE DEI FILE ===
% Inserisci qui i percorsi di tutti i file delle prove che vuoi mediare.
% (Assicurati che siano i file finali con dentro la colonna Delta_R_su_R0)
elenco_file = [
    "dati_serpentina_statica1.csv";
    "dati_serpentina_statica2.csv";
    "dati_serpentina_statica3.csv";
    "dati_serpentina_statica4.csv";
    "dati_serpentina_statica5.csv"
];

num_prove = length(elenco_file);
dati_prove = cell(num_prove, 1);
t_max_assoluto = 0;

% === 2. LETTURA E RICERCA DEL TEMPO MASSIMO ===
for i = 1:num_prove
    % Leggiamo le tabelle
    dati_prove{i} = readtable(elenco_file(i));
    
    % Troviamo quale prova è durata di più per creare l'asse temporale
    t_max_prova = max(dati_prove{i}.Tempo);
    if t_max_prova > t_max_assoluto
        t_max_assoluto = t_max_prova;
    end
end

% Creiamo l'asse dei tempi comune (con campionamento a 100 Hz come i tuoi dati)
frequenza = 100;
dt = 1 / frequenza;
t_comune = (0 : dt : t_max_assoluto)';

% === 3. CREAZIONE DELLA MATRICE CONDIVISA ===
% Inizializziamo una matrice di NaN (Not a Number) per raccogliere i segnali.
% Righe: i punti nel tempo. Colonne: le diverse prove.
matrice_DR = NaN(length(t_comune), num_prove);

for i = 1:num_prove
    t_corrente = dati_prove{i}.Tempo;
    
    % Se vuoi plottare la resistenza pura (Ohm), cambia la riga sotto in:
    % dr_corrente = dati_prove{i}.Resistenza;
    dr_corrente = dati_prove{i}.Delta_R_su_R0; 
    
    % Interpoliamo i dati di questa prova sull'asse temporale comune.
    % Se la prova finisce prima del tempo massimo, MATLAB lascerà dei NaN.
    matrice_DR(:, i) = interp1(t_corrente, dr_corrente, t_comune, 'linear', NaN);
end

% === 4. CALCOLO MEDIA E DEVIAZIONE STANDARD ===
% Usiamo 'omitnan' per ignorare i vuoti. Così se una prova finisce a 10s 
% e un'altra a 12s, la media tra 10 e 12s verrà fatta solo su quella sopravvissuta.
media_DR = mean(matrice_DR, 2, 'omitnan');
std_DR = std(matrice_DR, 0, 2, 'omitnan');

% === 5. PLOT CON AREA OMBREGGIATA ===
figure('Name','LUNGO')
hold on;
grid on;

% Prepariamo i confini dell'area ombreggiata (Media + Std e Media - Std)
curva_su = media_DR + std_DR;
curva_giu = media_DR - std_DR;

% Per colorare l'area, la funzione fill non accetta i NaN. 
% Quindi filtriamo via i punti finali in cui non abbiamo dati.
indici_validi = ~isnan(curva_su) & ~isnan(curva_giu);
t_fill = t_comune(indici_validi);
y_su = curva_su(indici_validi);
y_giu = curva_giu(indici_validi);

% Creiamo il poligono da riempire (andata sulla curva superiore, ritorno su quella inferiore)
x_area = [t_fill; flipud(t_fill)];
y_area = [y_su; flipud(y_giu)];

% Disegniamo l'area azzurra semitrasparente ('FaceAlpha' regola la trasparenza)
fill(x_area, y_area, [0.2 0.6 1], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', '± Dev. Std.');

% Disegniamo sopra la linea blu intensa della Media
plot(t_comune, media_DR, 'b', 'LineWidth', 2, 'DisplayName', 'Media');

xlabel('Tempo (s)');
ylabel('\Delta R / R_0');
title('Andamento Medio e Deviazione Standard');
legend('Location', 'northwest');
hold off;

%%
L_tot = 100; % Lunghezza iniziale del sensore in mm
strain_max_assoluto = 0; % Sostituisce il t_max e l'x_max

% === 2. LETTURA E RICERCA DELLO STRAIN MASSIMO ===
for i = 1:num_prove
    dati_prove{i} = readtable(elenco_file(i));
    
    % ESTRAZIONE E CALCOLO STRAIN %: (Spostamento / L_tot) * 100
    strain_corrente = (dati_prove{i}.Spostamento / L_tot) * 100; 
    
    % Troviamo il valore massimo di deformazione per definire l'asse comune
    strain_max_prova = max(strain_corrente);
    if strain_max_prova > strain_max_assoluto
        strain_max_assoluto = strain_max_prova;
    end
end

% Creiamo l'asse strain comune (%) 
% Invece del dt, usiamo un numero fisso di punti (es. 2000) per avere una curva fluida
num_punti = 2000; 
strain_comune = linspace(0, strain_max_assoluto, num_punti)';

% === 3. CREAZIONE DELLA MATRICE CONDIVISA ===
matrice_DR = NaN(length(strain_comune), num_prove);
for i = 1:num_prove
    % Asse X della singola prova (Strain in %)
    strain_corrente = (dati_prove{i}.Spostamento / L_tot) * 100; 
    
    % Asse Y della singola prova (Delta R / R0 in %)
    dr_corrente = dati_prove{i}.Delta_R_su_R0 * 100; 
    
    % ATTENZIONE: Pulizia dei valori identici successivi (micro-vibrazioni)
    [strain_corrente_pulito, indici_unici] = unique(strain_corrente, 'stable');
    dr_corrente_pulito = dr_corrente(indici_unici);
    
    % Interpoliamo i dati di questa prova sull'asse dello strain comune.
    matrice_DR(:, i) = interp1(strain_corrente_pulito, dr_corrente_pulito, strain_comune, 'linear', NaN);
end

% === 4. CALCOLO MEDIA E DEVIAZIONE STANDARD ===
media_DR = mean(matrice_DR, 2, 'omitnan');
std_DR = std(matrice_DR, 0, 2, 'omitnan');

% === 5. PLOT CON AREA OMBREGGIATA ===
figure('Name','LUNGO - Sensore vs Strain')
hold on;
grid on;

% Prepariamo i confini dell'area ombreggiata (Media + Std e Media - Std)
curva_su = media_DR + std_DR;
curva_giu = media_DR - std_DR;

% Filtriamo via i punti finali in cui non abbiamo dati (i NaN)
indici_validi = ~isnan(curva_su) & ~isnan(curva_giu);
strain_fill = strain_comune(indici_validi);
y_su = curva_su(indici_validi);
y_giu = curva_giu(indici_validi);

% Creiamo il poligono da riempire
x_area = [strain_fill; flipud(strain_fill)];
y_area = [y_su; flipud(y_giu)];

% Disegniamo l'area azzurra semitrasparente
fill(x_area, y_area, [0.2 0.6 1], 'FaceAlpha', 0.3, 'EdgeColor', 'none', 'DisplayName', '± STD');

% Disegniamo sopra la linea blu intensa della Media
plot(strain_comune, media_DR, 'b', 'LineWidth', 2, 'DisplayName', 'Mean');

xlabel('Strain (%)'); % <--- Etichetta aggiornata
ylabel('\DeltaR/R_0 (%)'); % <--- Aggiunte le parentesi per estetica
title('Static response');
subtitle('Connection element')
legend('Location', 'northeast');
xlim([0,30.3])

% Attenzione: avendo convertito in percentuale, "5" ora significa 5% di deformazione.
% Se la tua prova arrivava a 5 mm (che su 50 mm è il 10%), potresti voler cambiare in xlim([0, 10]);
hold off;