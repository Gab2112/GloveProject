clear;
close all;
clc;

% =========================================================================
% === PARAMETRI COMUNI ===
% =========================================================================
tipo_prova  = 'corto';   % Tipologia sensore: 'lungo', 'medio' o 'corto'
L0          = 30;        % Lunghezza iniziale sensore (mm)
finestre_in = 200;       % Finestra Savitzky-Golay base
fs          = 100;       % Frequenza campionamento (Hz)
taglio_in   = 0.05;      % Esclusione primi 5% (evita transitorio/deformazione residua)
taglio_fi   = 0.05;      % Esclusione ultimi 5%

% Percorsi di base
base_el  = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Voltaggio\Corto\";
base_mec = "C:\Users\gdira\OneDrive\Documents\Magistrale\Laboratorio\Instron\Forza_Deformazione\Cortoisteresi.is_tcyclic_Exports\";
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
R_base_medio     = zeros(num_prove, 1);
num_cicli_v      = zeros(num_prove, 1);

% Riferimento globale estratto dalla prima prova
R0_riferimento   = [];

% =========================================================================
% === ESECUZIONE DELLE 5 PROVE ===
% =========================================================================
for p = 1:num_prove
    cpm_current = cpm_elenco(p);
    
    fprintf('\n==========================================\n');
    fprintf('   AVVIO PROVA %d/%d: %d CICLI/MIN (%s)\n', p, num_prove, cpm_current, upper(tipo_prova));
    if ~isempty(R0_riferimento)
        fprintf('   (R0 globale di riferimento: %.2f Ohm)\n', R0_riferimento);
    end
    fprintf('==========================================\n');
    
    file_el  = base_el  + sprintf("Cortoisteresi%d.txt", cpm_current);
    file_mec = base_mec + sprintf("Cortoisteresi_%d.csv", p);
    file_out = base_out + sprintf("dati_%s_isteresi_%dcpm.csv", tipo_prova, cpm_current);
    
    % Finestra SG proporzionata per velocità basse
    finestre_sg = round(finestre_in / p);
    
    drawnow; pause(0.3);
    
    % Chiamata con la firma allineata (tipo_prova in 7a posizione, R0_riferimento in 13a)
    [Tabella_p, Dati_p, R0_calcolato] = Isteresi(...
        file_el, file_mec, file_out, ...
        cpm_current, L0, finestre_sg, ...
        tipo_prova, ...
        fs, 0, 0, taglio_in, taglio_fi, ...
        R0_riferimento);
    
    % Fissa R0 dalla prima prova (6 cpm) per tutte le successive
    if p == 1
        R0_riferimento = R0_calcolato;
        fprintf('\n>>> R0 FISSATO DALLA PRIMA PROVA: %.2f Ohm <<<\n\n', R0_riferimento);
    end
    
    % Salvataggio in memoria
    Tabelle_Singole{p} = Tabella_p;
    Dati_Singoli{p}    = Dati_p;
    
    % Calcolo statistiche normalizzate su R0 fisso
    media_H_R0(p)       = mean(Tabella_p.H_max_R0_Perc);
    std_H_R0(p)         = std(Tabella_p.H_max_R0_Perc);
    media_DeltaR_max(p) = mean(Tabella_p.Delta_R_max);
    R_base_medio(p)     = mean(Tabella_p.R_base_ciclo);
    num_cicli_v(p)      = height(Tabella_p);
    
    fprintf('Prova %d (%d cpm) completata! Cicli validati: %d\n', ...
        p, cpm_current, num_cicli_v(p));
    
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
    repmat(R0_riferimento, num_prove, 1), ...
    R_base_medio, ...
    media_DeltaR_max, ...
    media_H_R0, ...
    std_H_R0, ...
    'VariableNames', { ...
        'Prova', ...
        'CPM', ...
        'CicliAnalizzati', ...
        'R0_Riferimento_Ohm', ...
        'R_base_Locale_Medio_Ohm', ...
        'DeltaR_Max_Medio_Ohm', ...
        'Isteresi_R0_Media_Perc', ...
        'Isteresi_R0_Std_Perc' ...
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
% 1. Cartella di destinazione: ./Grafici/Isteresi_<tipo_prova>/
dir_grafici = fullfile('.', 'Grafici', sprintf('Isteresi_%s', tipo_prova));
if ~exist(dir_grafici, 'dir')
    mkdir(dir_grafici);
end

% 2. Creazione figura
fig = figure('Name', sprintf('Hysteresis Mean and Std vs Frequency (%s)', capitalize(tipo_prova)), ...
             'Color', 'w', ...
             'Units', 'pixels', ...
             'Position', [100, 100, 950, 620]);

c_bar  = [0.20, 0.45, 0.70];   % Blu tenue
c_err  = [0.15, 0.15, 0.15];   % Grigio scuro
c_mean = [0.85, 0.15, 0.15];   % Rosso per marker

% 3. Plot a barre (Media) con barre di errore (± Std)
x_pos = 1:num_prove;
b = bar(x_pos, media_H_R0, 0.55, ...
        'FaceColor', c_bar, ...
        'EdgeColor', 'none', ...
        'FaceAlpha', 0.65, ...
        'DisplayName', 'Mean (\mu)');
hold on;

h_err = errorbar(x_pos, media_H_R0, std_H_R0, ...
                 'LineStyle', 'none', ...
                 'Color', c_err, ...
                 'LineWidth', 1.6, ...
                 'CapSize', 14, ...
                 'DisplayName', 'Std Deviation (\pm\sigma)');

h_mean_marker = plot(x_pos, media_H_R0, 'o', ...
                     'MarkerSize', 7, ...
                     'MarkerFaceColor', c_mean, ...
                     'MarkerEdgeColor', 'k', ...
                     'LineWidth', 1.0, ...
                     'HandleVisibility', 'off');

% 4. Impostazioni assi e label
grid on;
set(gca, 'GridLineStyle', ':', 'GridAlpha', 0.45, 'LineWidth', 1.1, ...
         'FontSize', 12, 'FontName', 'Helvetica', 'Layer', 'top');
set(gca, 'XTick', x_pos, 'XTickLabel', string(cpm_elenco));
xlabel('Test Frequency [CPM]', 'FontSize', 13, 'FontWeight', 'bold');
ylabel('Hysteresis H_{max} (%)', 'FontSize', 13, 'FontWeight', 'bold');
title(sprintf('Mean Hysteresis and Standard Deviation - Short Sensor '), ...
      'FontSize', 14, 'FontWeight', 'bold');

% Margine superiore per box riassuntivo
y_max = max(media_H_R0 + std_H_R0);
ylim([0, max(1, y_max * 1.35)]);

% 5. Annotazione descrittiva con riassunto Mean ± Std
stats_str = cell(num_prove + 1, 1);
stats_str{1} = '\bf{Summary (\mu \pm \sigma):}';
for p = 1:num_prove
    stats_str{p+1} = sprintf('%2d CPM: %.2f \\pm %.2f%%', ...
        cpm_elenco(p), media_H_R0(p), std_H_R0(p));
end

text(0.97, 0.95, stats_str, ...
     'Units', 'normalized', ...
     'VerticalAlignment', 'top', ...
     'HorizontalAlignment', 'right', ...
     'FontSize', 10, ...
     'FontName', 'Helvetica', ...
     'BackgroundColor', [0.97 0.97 0.97 0.90], ...
     'EdgeColor', [0.75 0.75 0.75], ...
     'Margin', 8);

legend([b, h_err], {'Mean (\mu)', 'Std Dev (\pm\sigma)'}, ...
       'Location', 'northwest', 'FontSize', 11);

% 6. Salvataggio in formato vettoriale PDF
file_plot_pdf = fullfile(dir_grafici, sprintf('Isteresi_%s_Mean_Std.pdf', capitalize(tipo_prova)));
exportgraphics(fig, file_plot_pdf, 'ContentType', 'vector');
fprintf('\n>>> Grafico riassuntivo salvato in:\n - %s\n', file_plot_pdf);

% Funzione helper locale per formattazione
function s = capitalize(str)
    s = char(str);
    if ~isempty(s)
        s(1) = upper(s(1));
    end
end