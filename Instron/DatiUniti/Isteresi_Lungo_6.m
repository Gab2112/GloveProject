clear; 
close all;
clc;
% =========================================================================
% === PERCORSI DEI FILE ===
% =========================================================================
% File LabVIEW/Arduino (Voltaggio)
file_elettrico = "C:\Users\Daniele\Desktop\Progetto_Guanto\GloveProject\Instron\Voltaggio\Lungo\Lungoisteresi6.txt"; 
% File Instron (Meccanico - Forza/Spostamento)
file_meccanico = "C:\Users\Daniele\Desktop\Progetto_Guanto\GloveProject\Instron\Forza_Deformazione\Lungoisteresi.is_tcyclic_Exports\Lungoisteresi_1.csv"; 
file_output = 'dati_lungo_isteresi_6_tagliati.csv'; 

% Parametri della prova corrente
cicli_al_minuto = 6; % <--- CAMBIA QUESTO VALORE (es. 12, 24, 48, 60) in base alla prova
frequenza_campionamento = 100; % Hz

% =========================================================================
% === LETTURA E PREPARAZIONE DATI ===
% =========================================================================
% Dati Elettrici
dati2 = readmatrix(file_elettrico); 
t2 = dati2(:, 1);
voltaggio = dati2(:, 3) * (10^(-6));

% Dati Meccanici
opts = detectImportOptions(file_meccanico);
opts.DataLines = [3, Inf];
dati1 = readmatrix(file_meccanico, opts);
t1 = str2double(strrep(string(dati1(:, 1)), ',', '.'));
spostamento = str2double(strrep(string(dati1(:, 2)), ',', '.'));
forza = str2double(strrep(string(dati1(:, 3)), ',', '.'));

% Filtraggio preliminare Voltaggio
finestra = 800; 
voltaggio_filtrato = smoothdata(voltaggio, 'sgolay', finestra);

% =========================================================================
% === PLOT PRELIMINARI DEI DATI MECCANICI ===
% =========================================================================
figure(1)
plot(t1, spostamento, 'b');
xlabel('Tempo (s)'); ylabel('Spostamento (mm)');
title('Spostamento nel Tempo (File Meccanico - Isteresi)');
grid on;

figure(2)
plot(t1, forza, 'k');
xlabel('Tempo (s)'); ylabel('Forza (N)');
title('Forza nel Tempo (File Meccanico - Isteresi)');
grid on;

% =========================================================================
% === 1. SELEZIONE SUL VOLTAGGIO (Ricerca dei MASSIMI) ===
% =========================================================================
figure(3)
plot(t2, voltaggio_filtrato, 'r', 'LineWidth', 1.5);
xlabel('Tempo (s)'); ylabel('Voltaggio (V)');
title('VOLTAGGIO: Clicca Inizio e Fine (Verranno cercati i MASSIMI)');
grid on;

disp('--- 1. VOLTAGGIO ---');
disp('Clicca DUE PUNTI (Inizio e Fine) sul grafico del VOLTAGGIO (Figure 3)...');
[x_click_V, ~] = ginput(2); 
x_click_V = sort(x_click_V); 
punti_intorno = 200; % +- 2 secondi

% INIZIO VOLTAGGIO
[~, idx_V1] = min(abs(t2 - x_click_V(1)));
idx_start_W_V1 = max(1, idx_V1 - punti_intorno);
idx_end_W_V1   = min(length(voltaggio_filtrato), idx_V1 + punti_intorno);
[~, max_loc_V1] = max(voltaggio_filtrato(idx_start_W_V1 : idx_end_W_V1));
indice_inizio_V = idx_start_W_V1 + max_loc_V1 - 1;

% FINE VOLTAGGIO
[~, idx_V2] = min(abs(t2 - x_click_V(2)));
idx_start_W_V2 = max(1, idx_V2 - punti_intorno);
idx_end_W_V2   = min(length(voltaggio_filtrato), idx_V2 + punti_intorno);
[~, max_loc_V2] = max(voltaggio_filtrato(idx_start_W_V2 : idx_end_W_V2));
indice_fine_V = idx_start_W_V2 + max_loc_V2 - 1;

hold on;
plot(t2(indice_inizio_V), voltaggio_filtrato(indice_inizio_V), 'ko', 'MarkerFaceColor', 'g');
plot(t2(indice_fine_V), voltaggio_filtrato(indice_fine_V), 'ko', 'MarkerFaceColor', 'r');
hold off;

% =========================================================================
% === 2. SELEZIONE SULLO SPOSTAMENTO (Ricerca dei MINIMI) ===
% =========================================================================
figure(4)
plot(t1, spostamento, 'b', 'LineWidth', 1.5);
xlabel('Tempo (s)'); ylabel('Spostamento (mm)');
title('SPOSTAMENTO: Clicca Inizio e Fine (Verranno cercati i MINIMI)');
grid on;

disp('--- 2. SPOSTAMENTO MECCANICO ---');
disp('Clicca DUE PUNTI (Inizio e Fine) sul grafico dello SPOSTAMENTO (Figure 4)...');
[x_click_F, ~] = ginput(2); 
x_click_F = sort(x_click_F); 

% INIZIO SPOSTAMENTO
[~, idx_F1] = min(abs(t1 - x_click_F(1)));
idx_start_W_F1 = max(1, idx_F1 - punti_intorno);
idx_end_W_F1   = min(length(spostamento), idx_F1 + punti_intorno);
[~, min_loc_F1] = min(spostamento(idx_start_W_F1 : idx_end_W_F1)); % RICERCA SULLO SPOSTAMENTO
indice_inizio_F = idx_start_W_F1 + min_loc_F1 - 1;

% FINE SPOSTAMENTO
[~, idx_F2] = min(abs(t1 - x_click_F(2)));
idx_start_W_F2 = max(1, idx_F2 - punti_intorno);
idx_end_W_F2   = min(length(spostamento), idx_F2 + punti_intorno);
[~, min_loc_F2] = min(spostamento(idx_start_W_F2 : idx_end_W_F2)); % RICERCA SULLO SPOSTAMENTO
indice_fine_F = idx_start_W_F2 + min_loc_F2 - 1;

hold on;
plot(t1(indice_inizio_F), spostamento(indice_inizio_F), 'ko', 'MarkerFaceColor', 'g');
plot(t1(indice_fine_F), spostamento(indice_fine_F), 'ko', 'MarkerFaceColor', 'r');
hold off;

% =========================================================================
% === 3. SINCRONIZZAZIONE E CREAZIONE TABELLA ===
% =========================================================================
% Estraggo le due fette di dati
voltaggio_tagliato = voltaggio_filtrato(indice_inizio_V : indice_fine_V);
t1_tagliato = t1(indice_inizio_F : indice_fine_F);
forza_tagliata = forza(indice_inizio_F : indice_fine_F);
spostamento_tagliato = spostamento(indice_inizio_F : indice_fine_F);

% Per unire tutto in una tabella, i vettori devono avere la STESSA lunghezza.
L_min = min(length(voltaggio_tagliato), length(forza_tagliata));
voltaggio_tagliato   = voltaggio_tagliato(1:L_min);
t1_tagliato          = t1_tagliato(1:L_min);
forza_tagliata       = forza_tagliata(1:L_min);
spostamento_tagliato = spostamento_tagliato(1:L_min);

% Creazione Tabella completa e perfettamente allineata
Dati_Completi = table(t1_tagliato, spostamento_tagliato, forza_tagliata, voltaggio_tagliato, ...
    'VariableNames', {'Tempo', 'Spostamento', 'Forza', 'Voltaggio'});
disp('Sincronizzazione completata con successo!');

% =========================================================================
% === 4. CALCOLO RESISTENZA (Sui dati sincronizzati) ===
% =========================================================================
V0 = 5; 
R_fissa = 300000; 
V_out = Dati_Completi.Voltaggio; 
R_sensore = R_fissa .* (V_out ./ (V0 - V_out));

% R0 calcolato sui primissimi istanti 
R0 = mean(R_sensore(1:10)); 
Dati_Completi.Delta_R_su_R0 = (R_sensore - R0) / R0; 

% =========================================================================
% === 5. RIMOZIONE PRIMI 2 E ULTIMI 2 CICLI ===
% =========================================================================
durata_singolo_ciclo = 60 / cicli_al_minuto; 
tempo_da_rimuovere = 2 * durata_singolo_ciclo; 

tempo_start_valido = Dati_Completi.Tempo(1) + tempo_da_rimuovere;
tempo_end_valido   = Dati_Completi.Tempo(end) - tempo_da_rimuovere;

Dati_Filtro_Cicli = Dati_Completi(Dati_Completi.Tempo >= tempo_start_valido & ...
                                  Dati_Completi.Tempo <= tempo_end_valido, :);

% =========================================================================
% === PLOT FINALE SUI DATI PULITI ===
% =========================================================================
figure(5)
yyaxis left
plot(Dati_Filtro_Cicli.Tempo, Dati_Filtro_Cicli.Spostamento, '-b', 'LineWidth', 1.5);
ylabel('Spostamento (mm)'); 
yyaxis right
plot(Dati_Filtro_Cicli.Tempo, Dati_Filtro_Cicli.Delta_R_su_R0, '-r', 'LineWidth', 1.5);
ylabel('\Delta R / R_0');
xlabel('Tempo (s)');
title(sprintf('Dati Puliti (%d cicli/min) - Sincronizzati e 2 cicli rimossi', cicli_al_minuto));
grid on;

% =========================================================================
% === SALVATAGGIO ===
% =========================================================================
writetable(Dati_Filtro_Cicli, file_output);
disp(['Dati puliti dai transitori salvati in: ', file_output]);

% =========================================================================
% === 6. PLOT CURVA DI ISTERESI (Salita vs Discesa) - METODO ROBUSTO ===
% =========================================================================
disp('--- Generazione Curva di Isteresi ---');

X_ist = Dati_Filtro_Cicli.Spostamento; 
Y_ist = Dati_Filtro_Cicli.Delta_R_su_R0;

% Calcoliamo la derivata dello spostamento (filtrato) per capire la direzione
% Se dX > 0 stiamo tirando (salita), se dX < 0 stiamo rilasciando (discesa)
dX = diff(smoothdata(X_ist, 'sgolay', 50)); 
dX = [dX(1); dX]; % Pareggia la lunghezza dei vettori

% Trovo gli indici esatti in cui la direzione del movimento cambia
cambi_direzione = find(diff(sign(dX)) ~= 0);
punti_inversione = unique([1; cambi_direzione; length(X_ist)]);

figure(6)
hold on;
grid on;

h_salita = [];
h_discesa = [];

for i = 1:(length(punti_inversione) - 1)
    idx_start = punti_inversione(i);
    idx_end   = punti_inversione(i+1);
    
    segmento_X = X_ist(idx_start:idx_end);
    segmento_Y = Y_ist(idx_start:idx_end);
    
    % Capisco la direzione media di questo specifico segmento
    direzione_media = mean(dX(idx_start:idx_end));
    
    if direzione_media > 0
        % FASE DI CARICO (Allungamento) -> Rosso
        h1 = plot(segmento_X, segmento_Y, 'r-', 'LineWidth', 1.5);
        if isempty(h_salita), h_salita = h1; end % Salvo per la legenda
    else
        % FASE DI SCARICO (Rilascio) -> Blu
        h2 = plot(segmento_X, segmento_Y, 'b-', 'LineWidth', 1.5);
        if isempty(h_discesa), h_discesa = h2; end % Salvo per la legenda
    end
end

xlabel('Spostamento (mm)', 'FontWeight', 'bold'); 
ylabel('\Delta R / R_0', 'FontWeight', 'bold');
title(sprintf('Curva di Isteresi Elettro-Meccanica (%d cicli/min)', cicli_al_minuto));

if ~isempty(h_salita) && ~isempty(h_discesa)
    legend([h_salita, h_discesa], {'Carico (Salita)', 'Scarico (Discesa)'}, ...
           'Location', 'northwest', 'FontSize', 11);
end
hold off;