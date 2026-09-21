clear; 
close all;
clc;

% === PERCORSI DEI FILE ===
file_elettrico = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Voltaggio\Lungo\Lungocreep.txt"; 
file_meccanico = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Forza_Deformazione\Lungocreep.is_tcyclic_Exports\Lungocreep_2.csv"; 
file_output = 'dati_lungo_creep.csv'; 

frequenza = 100; % Hz
dt = 1 / frequenza; % Passo temporale (0.01 secondi)

% === LETTURA DEL FILE ELETTRICO (.txt) ===
dati2 = readmatrix(file_elettrico); 
voltaggio = dati2(:, 3);
voltaggio = voltaggio*(10^(-6));
t2 = ((0:length(voltaggio)-1)')/frequenza;


% === LETTURA DEL FILE MECCANICO (.csv) ===
opts = detectImportOptions(file_meccanico);
opts.DataLines = [3, Inf]; 

dati1 = readmatrix(file_meccanico, opts);
% Estrazione dei dati meccanici
t1 = dati1(:, 1);
spostamento = dati1(:, 2);
forza = dati1(:, 3);

% Traduzione in numeri delle stringhe
t1 = str2double(strrep(string(t1), ',', '.'));
spostamento = str2double(strrep(string(spostamento), ',', '.'));
forza = str2double(strrep(string(forza), ',', '.'));

% === PLOT DEI DATI ===
figure(1)
plot(t1, spostamento, 'b');
xlabel('Tempo (s)');
ylabel('Spostamento');
legend('Spostamento');
title('Spostamento nel Tempo (File Meccanico)');
grid on;

figure(3)
plot(t1, forza, 'k');
xlabel('Tempo (s)');
ylabel('Forza');
legend('Forza');
title('Spostamento nel Tempo (File Meccanico)');
grid on;

% === FILTRAGGIO DEL VOLTAGGIO ===
finestra = 800; 
voltaggio_filtrato = smoothdata(voltaggio, 'sgolay', finestra);

% === PLOT CON CONFRONTO ===
figure(2)
plot(t2, voltaggio, 'Color', [0.7 0.7 0.7], 'DisplayName', 'Originale (Rumoroso)');
hold on;
plot(t2, voltaggio_filtrato, 'r', 'LineWidth', 1.5, 'DisplayName', 'Filtrato');
hold off;
xlabel('Tempo (s)');
ylabel('Voltaggio');
legend('show');
title('Filtraggio del Voltaggio (Savitzky-Golay)');
grid on;

% === SINCRONIZZAZIONE E TAGLIO DEL VOLTAGGIO ===
tempo_inizio_voltaggio = 54; 
[~, indice_inizio] = min(abs(t2 - tempo_inizio_voltaggio));
N_campioni = length(t1);
indice_fine = indice_inizio + N_campioni - 1;

if indice_fine > length(voltaggio_filtrato)
    error('Errore: Il tempo_inizio_voltaggio è troppo avanzato. Il file del voltaggio termina prima che la prova meccanica sia finita!');
end

voltaggio_tagliato = voltaggio_filtrato(indice_inizio : indice_fine);

% === CREAZIONE DELL'OGGETTO UNICO ===
Dati_Completi = table(t1, spostamento, forza, voltaggio_tagliato, ...
    'VariableNames', {'Tempo', 'Spostamento', 'Forza', 'Voltaggio'});

% === PLOT DI VERIFICA DELLA SINCRONIZZAZIONE ===
figure(4)
yyaxis left
plot(Dati_Completi.Tempo, Dati_Completi.Spostamento, '-b', 'LineWidth', 1.5, 'DisplayName', 'Spostamento');
hold on;
plot(Dati_Completi.Tempo, Dati_Completi.Forza, '-g', 'LineWidth', 1.5, 'DisplayName', 'Forza');
ylabel('Spostamento (mm) / Forza (N)');

yyaxis right
plot(Dati_Completi.Tempo, Dati_Completi.Voltaggio, '-r', 'LineWidth', 1.5, 'DisplayName', 'Voltaggio');
ylabel('Voltaggio (V)');
xlabel('Tempo della Prova (s)');
title('Dati Sincronizzati e Tagliati sul Tempo Meccanico');
legend('Location', 'northwest');
grid on;

% === CALCOLO DELLA RESISTENZA E DELTA R ===
V0 = 5; 
R_fissa = 300000; 
V_out = Dati_Completi.Voltaggio;

R_sensore = R_fissa .* (V_out ./ (V0 - V_out));
R0 = mean(R_sensore(1:10));
Delta_R = R_sensore - R0;
Delta_R_su_R0 = Delta_R / R0; 

Dati_Completi.Delta_R_su_R0 = Delta_R_su_R0;

% === PLOT FINALE (Forza e Delta R) ===
figure(5)
yyaxis left
plot(Dati_Completi.Tempo, Dati_Completi.Forza, '-g', 'LineWidth', 1.5);
ylabel('Forza (N)');
yyaxis right
plot(Dati_Completi.Tempo, Dati_Completi.Delta_R_su_R0, '-k', 'LineWidth', 1.5);
ylabel('\Delta R / R_0');
xlabel('Tempo della Prova (s)');
title('Confronto tra Forza Applicata e Risposta del Sensore (\DeltaR/R_0)');
grid on;

%% Salvo il risultato
writetable(Dati_Completi, file_output);
disp(['Dati tagliati e salvati con successo in: ', file_output]);

% === 1. COPIA DELLA CURVA DI FORZA ===
tempo_inizio_copia = 124.852; 
tempo_fine_copia   = 184.55; 
[~, idx_in_copia] = min(abs(Dati_Completi.Tempo - tempo_inizio_copia));
[~, idx_fin_copia] = min(abs(Dati_Completi.Tempo - tempo_fine_copia));

forza_estesa = Dati_Completi.Forza(idx_in_copia : idx_fin_copia) + 1.331;
N_nuovi_punti = length(forza_estesa);

dt_meccanico = Dati_Completi.Tempo(2) - Dati_Completi.Tempo(1); 
tempo_esteso = Dati_Completi.Tempo(end) + dt_meccanico : dt_meccanico : ...
               Dati_Completi.Tempo(end) + dt_meccanico * N_nuovi_punti;
tempo_esteso = tempo_esteso'; 

% === 2. ESTRAZIONE DEI DATI REALI DEL VOLTAGGIO ===
indice_nuovo_inizio = indice_fine + 1;
indice_nuovo_fine   = indice_fine + N_nuovi_punti;

if indice_nuovo_fine > length(voltaggio_filtrato)
    warning('Il file elettrico termina prima! Prendo tutti i dati disponibili.');
    indice_nuovo_fine = length(voltaggio_filtrato);
    N_disp = indice_nuovo_fine - indice_nuovo_inizio + 1;
    forza_estesa = forza_estesa(1:N_disp);
    tempo_esteso = tempo_esteso(1:N_disp);
end

voltaggio_reale_esteso = voltaggio_filtrato(indice_nuovo_inizio : indice_nuovo_fine);
R_sensore_ex = R_fissa .* (voltaggio_reale_esteso ./ (V0 - voltaggio_reale_esteso));
Delta_R_ex = R_sensore_ex - R0;
Delta_R_su_R0_ex = Delta_R_ex / R0; 

% === 3. AGGIUNTA DEI 30 SECONDI A ZERO (BASELINE) ===
tempo_zeri = (Dati_Completi.Tempo(1) - 30 : dt_meccanico : Dati_Completi.Tempo(1) - dt_meccanico)';
forza_zeri = zeros(length(tempo_zeri), 1);
delta_r_zeri = zeros(length(tempo_zeri), 1);

tempo_totale = [tempo_zeri; Dati_Completi.Tempo; tempo_esteso];
forza_totale = [forza_zeri; Dati_Completi.Forza; forza_estesa];
delta_r_totale = [delta_r_zeri; Dati_Completi.Delta_R_su_R0; Delta_R_su_R0_ex];

% === 4. IDENTIFICAZIONE DEI 4 PICCHI (3 AUTOMATICI + 1 MANUALE) ===
% 1. Troviamo i primi 3 picchi presenti nei dati originali
[~, idx_picchi_originali] = findpeaks(Dati_Completi.Forza, 'MinPeakProminence', 0.5, 'NPeaks', 3);
tempi_primi_tre = Dati_Completi.Tempo(idx_picchi_originali);

% 2. INSERISCI QUI IL TEMPO DEL QUARTO PICCO (in secondi)
tempo_quarto_picco_manuale = 186.296; % <--- CAMBIA QUESTO VALORE CON IL TEMPO REALE

% Uniamo i tempi dei primi 3 con quello manuale
tempi_picchi = [tempi_primi_tre; tempo_quarto_picco_manuale];

% === PLOT GENERALE CON LINEE VERTICALI ===
figure(6)
% --- ASSE SINISTRO (FORZA) ---
yyaxis left
plot(tempo_totale, forza_totale, '-b', 'LineWidth', 1.5, 'DisplayName', 'Force');
ylabel('Force [N]');
hold on;

% Aggiunta delle linee verticali verdi con scritta orizzontale "+2.5%"
for i = 1:length(tempi_picchi)
    xline(tempi_picchi(i), '--g', '+2.5%', ...
          'LabelVerticalAlignment', 'top', ...
          'LabelHorizontalAlignment', 'center', ...
          'LabelOrientation', 'horizontal', ... % Scritta orizzontale
          'LineWidth', 1.2, ...
          'HandleVisibility', 'off'); 
end
hold off;

% --- ASSE DESTRO (VOLTAGGIO/SENSORE VERO) ---
yyaxis right
plot(tempo_totale, delta_r_totale*100, '-r', 'LineWidth', 1.5, 'DisplayName', '\DeltaR/R_0');
ylabel('\DeltaR/R_0 (%)');

% Formattazione del grafico
xlabel('Time [s]');
title('Mechanical and electrical response');
subtitle('High length sensor')
legend('show', 'Location', 'best');
grid on;
xlim([tempo_totale(1) tempo_totale(end)]);