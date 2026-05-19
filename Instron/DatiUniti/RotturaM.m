clear; 
close all;
clc;

% === PERCORSI DEI FILE ===
file_elettrico = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Voltaggio\Medio\MedioRottura.txt"; 
file_meccanico = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Forza_Deformazione\Mediorottura.is_tens_Exports\Mediorottura_1.csv"; 
file_output = 'dati_medio_rottura.csv'; 

frequenza = 100; % Hz
dt = 1 / frequenza; % Passo temporale (0.01 secondi)

% === LETTURA DEL FILE ELETTRICO (.txt) ===
dati2 = readmatrix(file_elettrico); 
t2 = dati2(:, 1);
voltaggio = dati2(:, 3);
voltaggio = voltaggio * (10^(-6));

% === LETTURA DEL FILE MECCANICO (.csv) ===
opts = detectImportOptions(file_meccanico);
opts.DataLines = [3, Inf]; 

% Se il file continua a darti NaN, togli il "%" dalle due righe qui sotto:
% opts.Delimiter = ';';
% setvaropts(opts, 'DecimalSeparator', ',');

dati1 = readmatrix(file_meccanico, opts);

% Estrazione dei dati meccanici
t1 = dati1(:, 1);
spostamento = dati1(:, 2);
forza = dati1(:, 3);

% Traduzione in numeri delle stringhe
t1 = str2double(strrep(string(t1), ',', '.'));
spostamento = str2double(strrep(string(spostamento), ',', '.'));
forza = str2double(strrep(string(forza), ',', '.'));

% === TAGLIO DELLA FORZA: DALL'INIZIO A 84 SECONDI ===
% (Se vuoi usare la forza intera fino a rottura, commenta o cancella queste 4 righe)
[~, indice_84s] = min(abs(t1 - 84));
t1 = t1(1:indice_84s);
spostamento = spostamento(1:indice_84s);
forza = forza(1:indice_84s);

% === PLOT DEI DATI MECCANICI ===
figure(1)
plot(t1, spostamento, 'b');
xlabel('Tempo (s)');
ylabel('Spostamento');
legend('Spostamento');
title('Spostamento nel Tempo');
grid on;

figure(3)
plot(t1, forza, 'k');
xlabel('Tempo (s)');
ylabel('Forza');
legend('Forza');
title('Forza nel Tempo');
grid on;

% === FILTRAGGIO DEL VOLTAGGIO ===
finestra = 800; 
voltaggio_filtrato = smoothdata(voltaggio, 'sgolay', finestra);

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
% 1. Trovo l'indice del tempo t2 che è più vicino a 4 secondi (NUOVA MODIFICA)
[~, indice_inizio_volt] = min(abs(t2 - 1.5));

% 2. Quanti campioni ha la prova meccanica? (Così il voltaggio avrà la stessa lunghezza)
N_campioni = length(t1);

% 3. Calcolo l'indice finale in cui tagliare il voltaggio
indice_fine_volt = indice_inizio_volt + N_campioni - 1;

% Controllo di sicurezza
if indice_fine_volt > length(voltaggio_filtrato)
    error('Attenzione: il file del voltaggio è troppo corto per coprire i dati meccanici partendo dal secondo 4!');
end

% 4. Estraggo la fetta di voltaggio sincronizzata
voltaggio_tagliato = voltaggio_filtrato(indice_inizio_volt : indice_fine_volt);

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
title('Dati Sincronizzati (Voltaggio allineato partendo da t = 4s)');
legend('Location', 'northwest');
grid on;

% === CALCOLO DELLA RESISTENZA E DELTA R ===
V0 = 5; 
R_fissa = 300000; 
V_out = Dati_Completi.Voltaggio;

R_sensore = R_fissa .* (V_out ./ (V0 - V_out));

% Calcolo della resistenza iniziale (R0) usando i primi 10 campioni sincronizzati
R0 = mean(R_sensore(1:10));

Delta_R = R_sensore - R0;
Delta_R_su_R0 = Delta_R / R0; 

% === AGGIORNAMENTO DELL'OGGETTO E SALVATAGGIO ===
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
title('Confronto tra Forza Applicata e Risposta del Sensore');
grid on;

% === CALCOLO DELLO STRAIN % E DELTA R/R0 % ===
L0 = 50; % <--- ATTENZIONE: SOSTITUISCI QUESTO VALORE CON QUELLO REALE DEL TUO PROVINO

strain_percentuale = (Dati_Completi.Spostamento / L0) * 100;
delta_r_percentuale = Dati_Completi.Delta_R_su_R0 * 100;

Dati_Completi.Strain_Percentuale = strain_percentuale;
Dati_Completi.DeltaR_Percentuale = delta_r_percentuale;

% === PLOT: DELTA R/R0 % vs STRAIN % ===
figure(6)
plot(strain_percentuale, delta_r_percentuale, '-r', 'LineWidth', 2);
xlabel('Strain (%)');
ylabel('\Delta R / R_0 (%)');
title('Risposta del sensore in funzione della deformazione');
grid on;

%% Salvo il risultato
writetable(Dati_Completi, file_output);
disp(['Dati tagliati e salvati con successo in: ', file_output]);