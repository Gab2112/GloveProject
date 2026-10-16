clear;
close all;
clc;

% =========================================================================
% === PARAMETRI COMUNI ===
% =========================================================================
tipo_prova  = 'lungo';   % Tipologia sensore: 'lungo', 'medio' o 'corto'
L0          = 70;        % Lunghezza iniziale sensore (mm)
finestre_in = 200;       % Finestra Savitzky-Golay base
fs          = 100;       % Frequenza campionamento (Hz)
taglio_in   = 0.05;      % Esclusione primi 5% (evita transitorio/deformazione residua)
taglio_fi   = 0.05;      % Esclusione ultimi 5%

% Percorsi di base
base_el  = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Voltaggio\Lungo\";
base_mec = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Forza_Deformazione\Lungoisteresi.is_tcyclic_Exports\";
base_out = ".\Dati\";
if ~exist(base_out, 'dir')
    mkdir(base_out);
end

% =========================================================================
% === CONFIGURAZIONE DELLE 5 PROVE ===
% =========================================================================
cpm_elenco = [6, 12, 24, 48, 60]; 
num_prove  = length(cpm_elenco);

% Strutture di salvataggio
Tabelle_Singole = cell(num_prove, 1);
Dati_Singoli    = cell(num_prove, 1);

% Vettori per la tabella riassuntiva finale
media_H_R0       = zeros(num_prove, 1);
std_H_R0         = zeros(num_prove, 1);
media_DeltaR_max = zeros(num_prove, 1);
R0_ciclo_medio   = zeros(num_prove, 1);   % <-- Aggiornato: R0 locale medio del ciclo
num_cicli_v      = zeros(num_prove, 1);
R0_globale_prove = zeros(num_prove, 1);

% =========================================================================
% === ESECUZIONE DELLE 5 PROVE ===
% =========================================================================
for p = 1:num_prove
    cpm_current = cpm_elenco(p);
    
    fprintf('\n==========================================\n');
    fprintf('   AVVIO PROVA %d/%d: %d CICLI/MIN (%s)\n', p, num_prove, cpm_current, upper(tipo_prova));
    fprintf('==========================================\n');
    
    file_el  = base_el  + sprintf("Lungoisteresi%d.txt", cpm_current);
    file_mec = base_mec + sprintf("Lungoisteresi_%d.csv", p);
    file_out = base_out + sprintf("dati_%s_isteresi_%dcpm.csv", tipo_prova, cpm_current);
    
    % Finestra SG proporzionata per velocità basse
    finestre_sg = round(0.15 * fs * 60 / cpm_current);   % 25% del ciclo
    
    drawnow; pause(0.3);
    
    % Chiamata alla funzione Isteresi:
    % Si passa [] all'ultimo argomento (R0_imposto) affinché ogni ciclo 
    % e ogni prova utilizzino i propri R0 calcolati
    [Tabella_p, Dati_p, R0_calcolato] = Isteresi(...
        file_el, file_mec, file_out, ...
        cpm_current, L0, finestre_sg, ...
        tipo_prova, ...
        fs, 0, 0, taglio_in, taglio_fi, ...
        []); 
    
    % Salvataggio in memoria
    Tabelle_Singole{p}  = Tabella_p;
    Dati_Singoli{p}     = Dati_p;
    R0_globale_prove(p) = R0_calcolato;
    
    % Calcolo statistiche su base locale (R0_Ciclo)
    media_H_R0(p)       = mean(Tabella_p.H_max_R0_Perc);
    std_H_R0(p)         = std(Tabella_p.H_max_R0_Perc);
    media_DeltaR_max(p) = mean(Tabella_p.Delta_R_max);
    R0_ciclo_medio(p)   = mean(Tabella_p.R0_Ciclo);       % <-- Accesso con nome colonna corretto
    num_cicli_v(p)      = height(Tabella_p);
    
    fprintf('Prova %d (%d cpm) completata! Cicli analizzati: %d | R0_ciclo medio: %.2f Ohm\n', ...
        p, cpm_current, num_cicli_v(p), R0_ciclo_medio(p));
    
    % Transizione tra le prove
    if p < num_prove
        disp('-------------------------------------------------------------------');
        disp('Premi INVIO nella Command Window per chiudere le figure e passare alla prova successiva...');
        pause;
        close all;
        drawnow;
        pause(0.5);
    end
end

% =========================================================================
% === TABELLA RIASSUNTIVA FINALE ===
% =========================================================================
Tabella_Riassuntiva = table(...
    (1:num_prove)', ...
    cpm_elenco', ...
    num_cicli_v, ...
    R0_globale_prove, ...
    R0_ciclo_medio, ...
    media_DeltaR_max, ...
    media_H_R0, ...
    std_H_R0, ...
    'VariableNames', { ...
        'Prova', ...
        'CPM', ...
        'CicliAnalizzati', ...
        'R0_Iniziale_Prova_Ohm', ...
        'R0_Ciclo_Medio_Ohm', ...
        'DeltaR_Max_Medio_Ohm', ...
        'Isteresi_Media_Perc_R0ciclo', ...
        'Isteresi_Std_Perc_R0ciclo' ...
    });

file_riassunto = base_out + sprintf("riassunto_isteresi_sensore_%s.csv", tipo_prova);
writetable(Tabella_Riassuntiva, file_riassunto);

fprintf('\n\n=======================================================================================\n');
fprintf('                           RIASSUNTO FINALE SENSORE %s                             \n', upper(tipo_prova));
fprintf('=======================================================================================\n');
disp(Tabella_Riassuntiva);
fprintf('Tabella salvata in: %s\n', file_riassunto);

% =========================================================================
% === GRAFICO FINALE: SOLO MEDIA E DEVIAZIONE STANDARD (PUBLICATION QUALITY) ===
% =========================================================================
dir_grafici = fullfile('.', 'Grafici', sprintf('Isteresi_%s', tipo_prova));
if ~exist(dir_grafici, 'dir')
    mkdir(dir_grafici);
end

% Figura ad alta risoluzione con larghezza leggermente aumentata
fig = figure('Name', sprintf('Hysteresis Mean and Std vs Frequency (%s)', capitalize(tipo_prova)), ...
             'Color', 'w', ...
             'Units', 'pixels', ...
             'Position', [80, 80, 1100, 620]);

% Layout a griglia 1x10: 7 colonne al grafico, 3 alla tabella
t = tiledlayout(1, 10, 'TileSpacing', 'compact', 'Padding', 'compact');

% -------------------------------------------------------------------------
% 1. ASSE PRINCIPALE: GRAFICO A BARRE ED ERRORBAR
% -------------------------------------------------------------------------
ax1 = nexttile(t, 1, [1, 7]);

c_bar  = [0.20, 0.45, 0.70];   % Blu tenue/elegante
c_err  = [0.15, 0.15, 0.15];   % Grigio antracite
c_mean = [0.85, 0.15, 0.15];   % Rosso per marker

x_pos = 1:num_prove;

% Barre della media
b = bar(ax1, x_pos, media_H_R0, 0.55, ...
        'FaceColor', c_bar, ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.65, ...
        'DisplayName', 'Mean (\mu)');
hold(ax1, 'on');

% Barre di errore (deviazione standard)
h_err = errorbar(ax1, x_pos, media_H_R0, std_H_R0, ...
                 'LineStyle', 'none', ...
                 'Color', c_err, ...
                 'LineWidth', 1.6, ...
                 'CapSize', 12, ...
                 'DisplayName', 'Std Deviation (\pm\sigma)');

% Marker puntuale sulla media
h_mean_marker = plot(ax1, x_pos, media_H_R0, 'o', ...
                     'MarkerSize', 7.5, ...
                     'MarkerFaceColor', c_mean, ...
                     'MarkerEdgeColor', 'k', ...
                     'LineWidth', 1.0, ...
                     'HandleVisibility', 'off');

% Forza gli elementi in primo piano rispetto alla griglia
uistack(h_err, 'top');
uistack(h_mean_marker, 'top');

grid(ax1, 'on');
set(ax1, 'GridLineStyle', ':', 'GridAlpha', 0.45, 'LineWidth', 1.1, ...
         'FontSize', 12, 'FontName', 'Helvetica', 'Layer', 'top');

set(ax1, 'XTick', x_pos, 'XTickLabel', string(cpm_elenco));
xlim(ax1, [0.4, num_prove + 0.6]);

% Margine dinamico su Y (+15%)
y_max = max(media_H_R0 + std_H_R0);
ylim(ax1, [0, max(1, y_max * 1.15)]);

xlabel(ax1, 'Test Frequency [CPM]', 'FontSize', 14, 'FontWeight', 'bold');
ylabel(ax1, 'Hysteresis Error (% R_{0cycle})', 'FontSize', 14, 'FontWeight', 'bold');
title(ax1, 'Mean Hysteresis and Standard Deviation - Long Sensor', ...
      'FontSize', 15, 'FontWeight', 'bold');

legend(ax1, [b, h_err], {'Mean (\mu)', 'Std Dev (\pm\sigma)'}, ...
       'Location', 'northwest', 'FontSize', 12);
% -------------------------------------------------------------------------
% 2. ASSE SECONDARIO: TABELLA RIASSUNTIVA CENTRATA IN VERTICALE
% -------------------------------------------------------------------------
ax2 = nexttile(t, 8, [1, 3]);
axis(ax2, 'off'); % Nasconde assi e griglia

stats_str = cell(num_prove + 2, 1);
stats_str{1} = '\bf{Summary (\mu \pm \sigma)}';
stats_str{2} = ''; % Spaziatura visiva pulita sotto l'intestazione
for p = 1:num_prove
    % Valori numerici calcolati direttamente, senza simboli '%'
    stats_str{p+2} = sprintf('%2d CPM:  %.2f \\pm %.2f', ...
        cpm_elenco(p), media_H_R0(p), std_H_R0(p));
end

% Tabella centrata sia in orizzontale (x = 0.50) che in verticale (y = 0.50)
text(ax2, 0.50, 0.50, stats_str, ...
     'Units', 'normalized', ...
     'VerticalAlignment', 'middle', ...
     'HorizontalAlignment', 'center', ...
     'FontSize', 13, ...
     'FontName', 'Helvetica', ...
     'BackgroundColor', [0.97, 0.97, 0.97, 0.95], ...
     'EdgeColor', [0.75, 0.75, 0.75], ...
     'LineWidth', 1.1, ...
     'Margin', 14);
% -------------------------------------------------------------------------
% SALVATAGGIO
% -------------------------------------------------------------------------
file_plot_pdf = fullfile(dir_grafici, sprintf('Isteresi_%s_Mean_Std.pdf', capitalize(tipo_prova)));
exportgraphics(fig, file_plot_pdf, 'ContentType', 'vector');
fprintf('\n>>> Grafico riassuntivo salvato in:\n - %s\n', file_plot_pdf);

% Funzione helper
function s = capitalize(str)
    s = char(str);
    if ~isempty(s)
        s(1) = upper(s(1));
    end

end