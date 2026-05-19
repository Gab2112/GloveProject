clear; 
close all;
clc;

% === PERCORSI DEI FILE ===
file_elettrico = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Voltaggio\Medio\Mediocreep.txt"; 
file_meccanico = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Forza_Deformazione\Mediocreep.is_tcyclic_Exports\Mediocreep_1.csv"; 
file_output = 'dati_medio_creep.csv'; 

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
tempo_inizio_voltaggio = 60; % <--- CAMBIA QUESTO VALORE (in secondi)

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


%% Salvo il risultato
writetable(Dati_Completi, file_output);
disp(['Dati tagliati e salvati con successo in: ', file_output]);


% === 1. COPIA DELLA CURVA DI FORZA ===
tempo_inizio_copia = 123.852; 
tempo_fine_copia   = 183.55; 

[~, idx_in_copia] = min(abs(Dati_Completi.Tempo - tempo_inizio_copia));
[~, idx_fin_copia] = min(abs(Dati_Completi.Tempo - tempo_fine_copia));

% Estraggo e traslo la forza (come avevi fatto tu)
forza_estesa = Dati_Completi.Forza(idx_in_copia : idx_fin_copia) + 1.331;
N_nuovi_punti = length(forza_estesa);

% Creo il nuovo vettore tempo che prosegue
dt_meccanico = Dati_Completi.Tempo(2) - Dati_Completi.Tempo(1); 
tempo_esteso = Dati_Completi.Tempo(end) + dt_meccanico : dt_meccanico : ...
               Dati_Completi.Tempo(end) + dt_meccanico * N_nuovi_punti;
tempo_esteso = tempo_esteso'; 

% === 2. ESTRAZIONE DEI DATI REALI DEL VOLTAGGIO ===
% Ripartiamo esattamente dal campione successivo all'ultimo salvato in Dati_Completi
indice_nuovo_inizio = indice_fine + 1;
indice_nuovo_fine   = indice_fine + N_nuovi_punti;

% Controllo di sicurezza: se il file elettrico finisce prima, accorciamo tutto
if indice_nuovo_fine > length(voltaggio_filtrato)
    warning('Il file elettrico termina prima! Prendo tutti i dati disponibili.');
    indice_nuovo_fine = length(voltaggio_filtrato);
    N_disp = indice_nuovo_fine - indice_nuovo_inizio + 1;
    forza_estesa = forza_estesa(1:N_disp);
    tempo_esteso = tempo_esteso(1:N_disp);
end

% Prendo il voltaggio reale dal vettore filtrato iniziale
voltaggio_reale_esteso = voltaggio_filtrato(indice_nuovo_inizio : indice_nuovo_fine);

% Trasformo il voltaggio in Delta R / R0 (usando la R0 calcolata all'inizio)
R_sensore_ex = R_fissa .* (voltaggio_reale_esteso ./ (V0 - voltaggio_reale_esteso));
Delta_R_ex = R_sensore_ex - R0;
Delta_R_su_R0_ex = Delta_R_ex / R0; 

% === 3. AGGIUNTA DEI 30 SECONDI A ZERO (BASELINE) ===
% Ricavo il dt e creo un vettore tempo che parte da -30s fino all'inizio dei dati
dt_meccanico = Dati_Completi.Tempo(2) - Dati_Completi.Tempo(1);
tempo_zeri = (Dati_Completi.Tempo(1) - 30 : dt_meccanico : Dati_Completi.Tempo(1) - dt_meccanico)';

% Creo i vettori di zeri (piatti) per la baseline
forza_zeri = zeros(length(tempo_zeri), 1);
delta_r_zeri = zeros(length(tempo_zeri), 1);

% Unisco tutti i pezzi (Baseline + Dati Originali + Coda Copiata) per avere linee continue
tempo_totale = [tempo_zeri; Dati_Completi.Tempo; tempo_esteso];
forza_totale = [forza_zeri; Dati_Completi.Forza; forza_estesa];
delta_r_totale = [delta_r_zeri; Dati_Completi.Delta_R_su_R0; Delta_R_su_R0_ex];

% === 4. IDENTIFICAZIONE DEI 4 PICCHI (3 AUTOMATICI + 1 MANUALE) ===
% 1. Troviamo i primi 3 picchi presenti nei dati originali
[~, idx_picchi_originali] = findpeaks(Dati_Completi.Forza, 'MinPeakProminence', 0.5, 'NPeaks', 3);
tempi_primi_tre = Dati_Completi.Tempo(idx_picchi_originali);

% 2. INSERISCI QUI IL TEMPO DEL QUARTO PICCO (in secondi)
tempo_quarto_picco_manuale = 185.13; % <--- CAMBIA QUESTO VALORE CON IL TEMPO REALE

% Uniamo i tempi dei primi 3 con quello manuale
tempi_picchi = [tempi_primi_tre; tempo_quarto_picco_manuale];

% === PLOT GENERALE CON LINEE VERTICALI ===
figure(6)
% --- ASSE SINISTRO (FORZA) ---
yyaxis left
plot(tempo_totale, forza_totale, '-b', 'LineWidth', 1.5, 'DisplayName', 'Force');
ylabel('Force [N]');
ylim([-1, 8])
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
subtitle('Medium length sensor')
legend('show', 'Location', 'best');
grid on;
xlim([tempo_totale(1) tempo_totale(end)]);