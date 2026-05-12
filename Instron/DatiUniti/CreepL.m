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
t2 = dati2(:, 1);
voltaggio = dati2(:, 3);
voltaggio = voltaggio*(10^(-6));


% === LETTURA DEL FILE MECCANICO (.csv) ===
% Usiamo detectImportOptions per dire a MATLAB come è fatto il file Instron
opts = detectImportOptions(file_meccanico);

% I file Instron hanno i numeri che partono dalla riga 3 (Riga 1: Nomi, Riga 2: Unità di misura).
% Diciamo a MATLAB di ignorare le prime due righe di testo:
opts.DataLines = [3, Inf]; 

% [ATTENZIONE]: Se il file continua a darti NaN, significa che il tuo CSV usa la virgola 
% per i decimali (es. 2,54) invece del punto (2.54). In tal caso, togli il simbolo "%" 
% dalle due righe qui sotto per far capire a MATLAB il formato italiano:
% opts.Delimiter = ';';
% setvaropts(opts, 'DecimalSeparator', ',');

dati1 = readmatrix(file_meccanico, opts);

% Estrazione dei dati meccanici
t1 = dati1(:, 1);
spostamento = dati1(:, 2);
forza = dati1(:, 3);

% Traduezione in numeri delle stringhe
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
% La "finestra" indica quanti punti vicini usare per filtrare.
% Avendo un campionamento a 100 Hz, 15 punti equivalgono a 0.15 secondi.
% Se il segnale è ancora troppo rumoroso, alza questo valore (es. 25 o 35).
% Se il segnale risulta troppo alterato, abbassalo (es. 5 o 10).
finestra = 800; 

% Applica il filtro Savitzky-Golay
voltaggio_filtrato = smoothdata(voltaggio, 'sgolay', finestra);


% === PLOT CON CONFRONTO (Sostituisci la tua figure 2 con questa) ===
figure(2)
% Disegno il segnale originale in grigio chiaro in sottofondo
plot(t2, voltaggio, 'Color', [0.7 0.7 0.7], 'DisplayName', 'Originale (Rumoroso)');
hold on;
% Disegno il segnale filtrato in rosso e un po' più spesso
plot(t2, voltaggio_filtrato, 'r', 'LineWidth', 1.5, 'DisplayName', 'Filtrato');
hold off;

xlabel('Tempo (s)');
ylabel('Voltaggio');
legend('show');
title('Filtraggio del Voltaggio (Savitzky-Golay)');
grid on;

% === SINCRONIZZAZIONE E TAGLIO DEL VOLTAGGIO ===

% 1. Trovo il valore minimo del voltaggio filtrato e il suo indice (posizione)
% (Puoi guardare la Figure 2 per scegliere il valore che ti interessa)
tempo_inizio_voltaggio = 58; % <--- CAMBIA QUESTO VALORE (in secondi)

% 1. Troviamo l'indice del vettore tempo (t2) più vicino al valore scelto
[~, indice_inizio] = min(abs(t2 - tempo_inizio_voltaggio));

% 2. Quanti campioni (righe) ha la prova meccanica?
N_campioni = length(t1);

% 3. Calcolo l'indice finale aggiungendo la lunghezza della meccanica all'indice di inizio
indice_fine = indice_inizio + N_campioni - 1;

% 4. Controllo di sicurezza: verifica che il voltaggio non finisca prima del dovuto
if indice_fine > length(voltaggio_filtrato)
    error('Errore: Il tempo_inizio_voltaggio è troppo avanzato. Il file del voltaggio termina prima che la prova meccanica sia finita!');
end

% 5. Estraggo solo la fetta di voltaggio che mi interessa (scartando prima e dopo)
voltaggio_tagliato = voltaggio_filtrato(indice_inizio : indice_fine);
% === CREAZIONE DELL'OGGETTO UNICO ===
% Ora t1, spostamento, forza e voltaggio_tagliato hanno esattamente 
% lo stesso numero di elementi. Li uniamo in una tabella.
Dati_Completi = table(t1, spostamento, forza, voltaggio_tagliato, ...
    'VariableNames', {'Tempo', 'Spostamento', 'Forza', 'Voltaggio'});


% === PLOT DI VERIFICA DELLA SINCRONIZZAZIONE ===
figure(4)
% Asse sinistro (Spostamento e Forza)
yyaxis left
plot(Dati_Completi.Tempo, Dati_Completi.Spostamento, '-b', 'LineWidth', 1.5, 'DisplayName', 'Spostamento');
hold on;
plot(Dati_Completi.Tempo, Dati_Completi.Forza, '-g', 'LineWidth', 1.5, 'DisplayName', 'Forza');
ylabel('Spostamento (mm) / Forza (N)');

% Asse destro (Voltaggio)
yyaxis right
plot(Dati_Completi.Tempo, Dati_Completi.Voltaggio, '-r', 'LineWidth', 1.5, 'DisplayName', 'Voltaggio');
ylabel('Voltaggio (V)');

xlabel('Tempo della Prova (s)');
title('Dati Sincronizzati e Tagliati sul Tempo Meccanico');
legend('Location', 'northwest');
grid on;

% === CALCOLO DELLA RESISTENZA E DELTA R ===

V0 = 5; % Voltaggio di alimentazione (V)
R_fissa = 300000; % Resistenza fissa (300 kOhm)

% Estraiamo il voltaggio appena sincronizzato
V_out = Dati_Completi.Voltaggio;

% 1. Calcolo della Resistenza del sensore (Ohm)
% ATTENZIONE: Questa formula assume che misuriate V_out ai capi del sensore.
% Se lo misurate ai capi della resistenza fissa, la formula diventa:
% R_sensore = R_fissa .* (V0 ./ V_out - 1);
R_sensore = R_fissa .* (V_out ./ (V0 - V_out));

% 2. Calcolo della resistenza iniziale (R0)
% Invece di prendere solo il primissimo punto (che potrebbe avere un micro-rumore),
% facciamo una media dei primi 10 campioni prima che inizi la trazione vera e propria.
R0 = mean(R_sensore(1:10));

% 3. Calcolo del Delta R e della variazione relativa
Delta_R = R_sensore - R0;
Delta_R_su_R0 = Delta_R / R0; % Spesso in letteratura si usa (Delta R / R0)

% === AGGIORNAMENTO DELL'OGGETTO E SALVATAGGIO ===
% Aggiungiamo le nuove colonne alla tabella esistente
Dati_Completi.Delta_R_su_R0 = Delta_R_su_R0;


% === PLOT FINALE (Forza e Delta R) ===
figure()
yyaxis left
plot(Dati_Completi.Tempo, Dati_Completi.Forza, '-g', 'LineWidth', 1.5);
ylabel('Forza (N)');

yyaxis right
% Plottiamo Delta_R_su_R0 perché è il parametro standard per i sensori
plot(Dati_Completi.Tempo, Dati_Completi.Delta_R_su_R0, '-k', 'LineWidth', 1.5);
ylabel('\Delta R / R_0');

xlabel('Tempo della Prova (s)');
title('Confronto tra Forza Applicata e Risposta del Sensore (\DeltaR/R_0)');
grid on;
%% Salvo il risultato
writetable(Dati_Completi, file_output);
disp(['Dati tagliati e salvati con successo in: ', file_output]);