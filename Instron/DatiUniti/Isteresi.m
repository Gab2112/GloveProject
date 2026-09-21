function [Tabella_Isteresi_R, Dati_Filtro_Cicli, R0_usato] = Isteresi(...
    file_elettrico, ...
    file_meccanico, ...
    file_output, ...
    cicli_al_minuto, ...
    L0, ...
    finestre, ...
    tipo_prova, ...
    frequenza_campionamento, ...
    cicli_da_scartare_inizio, ...
    cicli_da_scartare_fine, ...
    taglio_inizio_perc, ...
    taglio_fine_perc, ...
    R0_imposto)

% Normalizzazione etichetta tipo prova (es. "Sensore Lungo" -> "lungo")
tipo_pulito = lower(strtrim(string(tipo_prova)));
tipo_pulito = regexprep(tipo_pulito, '^sensore[\s_]*', '');

if tipo_pulito=='lungo'
    definizione_grafico = 'Long Sensor';
elseif tipo_pulito=='corto'
    definizione_grafico = 'Short Sensor';
elseif tipo_pulito=='medio'
    definizione_grafico = 'Medium Sensor';
end

% =========================================================================
% === 1. IMPORTAZIONE ED ELABORAZIONE PRELIMINARE ===
% =========================================================================
dati2 = readmatrix(file_elettrico); 
voltaggio = dati2(:, 3) * (10^(-6));
t2 = ((0:length(voltaggio)-1)') / frequenza_campionamento;

opts = detectImportOptions(file_meccanico);
opts.DataLines = [3, Inf];
dati1 = readmatrix(file_meccanico, opts);

t1 = str2double(strrep(string(dati1(:, 1)), ',', '.'));
spostamento = str2double(strrep(string(dati1(:, 2)), ',', '.'));
forza = str2double(strrep(string(dati1(:, 3)), ',', '.'));

voltaggio_filtrato = smoothdata(voltaggio, 'sgolay', finestre);

% =========================================================================
% === 2. SELEZIONE INTERATTIVA VOLTAGGIO (GINPUT) ===
% =========================================================================
t2_plot = t2 - t2(1);
v_plot  = voltaggio_filtrato;

figure('Name', 'Selezione Voltaggio', 'NumberTitle', 'off');
plot(t2_plot, voltaggio, 'Color', [0.75 0.75 0.75], 'LineWidth', 1, 'DisplayName', 'Raw Voltage');
hold on;
plot(t2_plot, v_plot, 'r', 'LineWidth', 1.5, 'DisplayName', 'Filtered Voltage');
xlabel('Time (s)'); ylabel('Voltage (V)');
title(sprintf('VOLTAGE (%d cpm - %s): Clicca INIZIO e FINE (Max Locali a Riposo)', cicli_al_minuto, tipo_pulito));
legend('Location', 'best');
grid on;

disp('--- 1. VOLTAGGIO ---');
disp('Clicca DUE VOLTE sulla figura del Voltaggio: Inizio e Fine...');
drawnow;
[x_click_V, ~] = ginput(2); 
x_click_V = sort(x_click_V); 

punti_intorno = round(frequenza_campionamento * (30 / cicli_al_minuto) * 0.5); 

[~, idx_V1] = min(abs(t2_plot - x_click_V(1)));
idx_start_W_V1 = max(1, idx_V1 - punti_intorno);
idx_end_W_V1   = min(length(voltaggio_filtrato), idx_V1 + punti_intorno);
[~, max_loc_V1] = max(voltaggio_filtrato(idx_start_W_V1 : idx_end_W_V1));
indice_inizio_V = idx_start_W_V1 + max_loc_V1 - 1;

[~, idx_V2] = min(abs(t2_plot - x_click_V(2)));
idx_start_W_V2 = max(1, idx_V2 - punti_intorno);
idx_end_W_V2   = min(length(voltaggio_filtrato), idx_V2 + punti_intorno);
[~, max_loc_V2] = max(voltaggio_filtrato(idx_start_W_V2 : idx_end_W_V2));
indice_fine_V = idx_start_W_V2 + max_loc_V2 - 1;

hold on;
plot(t2_plot(indice_inizio_V), v_plot(indice_inizio_V), 'ko', 'MarkerFaceColor', 'g', 'HandleVisibility', 'off');
plot(t2_plot(indice_fine_V), v_plot(indice_fine_V), 'ko', 'MarkerFaceColor', 'r', 'HandleVisibility', 'off');
hold off;

% =========================================================================
% === 3. SELEZIONE INTERATTIVA SPOSTAMENTO (GINPUT) ===
% =========================================================================
t1_plot = t1 - t1(1);
disp_plot = spostamento - spostamento(1);

figure('Name', 'Selezione Spostamento', 'NumberTitle', 'off');
plot(t1_plot, disp_plot, 'b', 'LineWidth', 1.5);
xlabel('Time (s)'); ylabel('Displacement (mm)');
title(sprintf('DISPLACEMENT (%d cpm - %s): Clicca INIZIO e FINE (Min Locali)', cicli_al_minuto, tipo_pulito));
grid on;

disp('--- 2. SPOSTAMENTO MECCANICO ---');
disp('Clicca DUE VOLTE sulla figura dello Spostamento: Inizio e Fine...');
drawnow;
[x_click_F, ~] = ginput(2); 
x_click_F = sort(x_click_F); 

[~, idx_F1] = min(abs(t1_plot - x_click_F(1)));
idx_start_W_F1 = max(1, idx_F1 - punti_intorno);
idx_end_W_F1   = min(length(spostamento), idx_F1 + punti_intorno);
[~, min_loc_F1] = min(spostamento(idx_start_W_F1 : idx_end_W_F1));
indice_inizio_F = idx_start_W_F1 + min_loc_F1 - 1;

[~, idx_F2] = min(abs(t1_plot - x_click_F(2)));
idx_start_W_F2 = max(1, idx_F2 - punti_intorno);
idx_end_W_F2   = min(length(spostamento), idx_F2 + punti_intorno);
[~, min_loc_F2] = min(spostamento(idx_start_W_F2 : idx_end_W_F2));
indice_fine_F = idx_start_W_F2 + min_loc_F2 - 1;

hold on;
plot(t1_plot(indice_inizio_F), disp_plot(indice_inizio_F), 'ko', 'MarkerFaceColor', 'g');
plot(t1_plot(indice_fine_F), disp_plot(indice_fine_F), 'ko', 'MarkerFaceColor', 'r');
hold off;

% =========================================================================
% === 4. SINCRONIZZAZIONE E CALCOLO RESISTENZA ===
% =========================================================================
voltaggio_tagliato   = voltaggio_filtrato(indice_inizio_V : indice_fine_V);
t1_tagliato          = t1(indice_inizio_F : indice_fine_F);
forza_tagliata       = forza(indice_inizio_F : indice_fine_F);
spostamento_tagliato = spostamento(indice_inizio_F : indice_fine_F);

L_min = min(length(voltaggio_tagliato), length(forza_tagliata));
voltaggio_tagliato   = voltaggio_tagliato(1:L_min);
t1_tagliato          = t1_tagliato(1:L_min);
forza_tagliata       = forza_tagliata(1:L_min);
spostamento_tagliato = spostamento_tagliato(1:L_min);

Dati_Completi = table(t1_tagliato, spostamento_tagliato, forza_tagliata, voltaggio_tagliato, ...
    'VariableNames', {'Tempo', 'Spostamento', 'Forza', 'Voltaggio'});

V0 = 5; 
R_fissa = 300000; 
V_out = Dati_Completi.Voltaggio; 
Dati_Completi.R_sensore = R_fissa .* (V_out ./ (V0 - V_out));

durata_singolo_ciclo = 60 / cicli_al_minuto; 
tempo_start_valido   = Dati_Completi.Tempo(1) + (cicli_da_scartare_inizio * durata_singolo_ciclo);
tempo_end_valido     = Dati_Completi.Tempo(end) - (cicli_da_scartare_fine * durata_singolo_ciclo);

Dati_Filtro_Cicli    = Dati_Completi(Dati_Completi.Tempo >= tempo_start_valido & ...
                                     Dati_Completi.Tempo <= tempo_end_valido, :);

if ~isempty(file_output)
    writetable(Dati_Filtro_Cicli, file_output);
    fprintf('Dati salvati con successo in: %s\n', file_output);
end

% =========================================================================
% === 5. IDENTIFICAZIONE PICCHI / VALLI & VERIFICA COERENZA (YYAXIS) ===
% =========================================================================
X_raw = Dati_Filtro_Cicli.Spostamento; 
V_raw = Dati_Filtro_Cicli.Voltaggio; 
R_raw = Dati_Filtro_Cicli.R_sensore; 
T_raw = Dati_Filtro_Cicli.Tempo - Dati_Filtro_Cicli.Tempo(1);

n_campionamento_ciclo = frequenza_campionamento * (60 / cicli_al_minuto);
distanza_minima       = round(n_campionamento_ciclo * 0.50);

% --- A. Picchi Meccanici (Spostamento) ---
X_smooth        = smoothdata(X_raw, 'movmean', round(frequenza_campionamento * 0.15));
prominenza_min_X = (max(X_smooth) - min(X_smooth)) * 0.25;
[~, locs_min_X] = findpeaks(-X_smooth, 'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_min_X);
[~, locs_max_X] = findpeaks(X_smooth,  'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_min_X);

% --- B. Picchi Voltaggio/Resistenza ---
V_smooth        = smoothdata(V_raw, 'movmean', round(frequenza_campionamento * 0.15));
prominenza_min_V = (max(V_smooth) - min(V_smooth)) * 0.25;
[~, locs_max_V] = findpeaks(V_smooth,  'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_min_V);
[~, locs_min_V] = findpeaks(-V_smooth, 'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_min_V);

figure('Name', 'Verifica Coerenza: Spostamento vs Voltaggio', 'NumberTitle', 'off');
yyaxis left
plot(T_raw, X_raw, 'b-', 'LineWidth', 1.2); hold on;
plot(T_raw(locs_max_X), X_raw(locs_max_X), 'r^', 'MarkerFaceColor', 'r', 'MarkerSize', 7);
plot(T_raw(locs_min_X), X_raw(locs_min_X), 'bv', 'MarkerFaceColor', 'b', 'MarkerSize', 7);
ylabel('Spostamento (mm)', 'FontWeight', 'bold');
ax = gca;
ax.YColor = [0 0.2 0.8];

yyaxis right
plot(T_raw, V_raw, 'm-', 'LineWidth', 1.2);
plot(T_raw(locs_max_V), V_raw(locs_max_V), 'ko', 'MarkerFaceColor', 'g', 'MarkerSize', 6);
plot(T_raw(locs_min_V), V_raw(locs_min_V), 'rv', 'MarkerFaceColor', 'm', 'MarkerSize', 6);
ylabel('Voltaggio (V)', 'FontWeight', 'bold');
ax.YColor = [0.8 0 0.5];

xlabel('Tempo Relativo (s)', 'FontWeight', 'bold');
title(sprintf('Verifica Allineamento: Spostamento vs Voltaggio (%d cpm - %s)', cicli_al_minuto, tipo_pulito));
grid on;
legend({'Spostamento', 'Max Spostamento', 'Min Spostamento', ...
        'Voltaggio', 'Max Voltaggio (Riposo)', 'Min Voltaggio (Max Trazione)'}, ...
        'Location', 'best', 'NumColumns', 2);

% =========================================================================
% === 6 & 7. ALLINEAMENTO MAX DEFORMAZIONE -> MIN VOLTAGGIO / R & ISTERESI ===
% =========================================================================
N_cicli = min(length(locs_min_X) - 1, length(locs_max_V) - 1);

if ~isempty(R0_imposto) && R0_imposto > 0
    R0_usato = R0_imposto;
else
    R0_usato = mean(R_raw(1:min(20, length(R_raw))));
end

Delta_R_max       = zeros(N_cicli, 1);
R_base_ciclo      = zeros(N_cicli, 1);
H_max_R0_Perc     = zeros(N_cicli, 1);
Strain_at_Hmax    = zeros(N_cicli, 1);
Drift_Residuo_Ohm = zeros(N_cicli, 1);
R0_vett           = repmat(R0_usato, N_cicli, 1);

fig_h = figure('Name', 'Curva Isteresi (Max Deformazione -> Min Voltaggio/Resistenza)', 'NumberTitle', 'off', 'Color', 'w');
hold on; grid on;
h_salita = []; h_discesa = [];

for i = 1:N_cicli
    % --- Estremi Meccanici ---
    idx_m_start = locs_min_X(i);
    idx_m_end   = locs_min_X(i+1);
    p_m = locs_max_X(locs_max_X > idx_m_start & locs_max_X < idx_m_end);
    if isempty(p_m), continue; end
    idx_m_peak  = p_m(1);
    
    % --- Estremi Elettrici ---
    idx_e_start = locs_max_V(i);
    idx_e_end   = locs_max_V(i+1);
    p_e = locs_min_V(locs_min_V > idx_e_start & locs_min_V < idx_e_end);
    if isempty(p_e), continue; end
    idx_e_min   = p_e(1);
    
    x_zero = X_raw(idx_m_start);
    r_zero = R_raw(idx_e_start);
    R_base_ciclo(i)      = r_zero;
    Drift_Residuo_Ohm(i) = R_raw(idx_e_end) - r_zero;
    
    % Salita
    s_load_raw = ((X_raw(idx_m_start : idx_m_peak) - x_zero) / L0) * 100;
    r_load_raw = R_raw(idx_e_start : idx_e_min) - r_zero;
    
    % Discesa
    s_unload_raw = ((X_raw(idx_m_peak : idx_m_end) - x_zero) / L0) * 100;
    r_unload_raw = R_raw(idx_e_min : idx_e_end) - r_zero;
    
    N_pts_load   = length(s_load_raw);
    N_pts_unload = length(s_unload_raw);
    
    r_load_aligned   = interp1(linspace(0, 1, length(r_load_raw)),   r_load_raw,   linspace(0, 1, N_pts_load)',   'linear');
    r_unload_aligned = interp1(linspace(0, 1, length(r_unload_raw)), r_unload_raw, linspace(0, 1, N_pts_unload)', 'linear');
    
    h1 = plot(s_load_raw,   r_load_aligned,   'r-', 'LineWidth', 1.2);
    if isempty(h_salita), h_salita = h1; end
    
    h2 = plot(s_unload_raw, r_unload_aligned, 'b-', 'LineWidth', 1.2);
    if isempty(h_discesa), h_discesa = h2; end
    
    % H_max
    [s_l_u, idx_lu]   = unique(s_load_raw);
    r_l_u             = r_load_aligned(idx_lu);
    [s_un_u, idx_unu] = unique(s_unload_raw);
    r_un_u            = r_unload_aligned(idx_unu);
    
    s_min = max(min(s_l_u), min(s_un_u));
    s_max = min(max(s_l_u), max(s_un_u));
    delta_s = s_max - s_min;
    
    s_lim_inf = s_min + (taglio_inizio_perc * delta_s);
    s_lim_sup = s_max - (taglio_fine_perc   * delta_s);
    
    if s_lim_sup > s_lim_inf
        s_grid = linspace(s_lim_inf, s_lim_sup, 250);
        r_load_interp   = interp1(s_l_u,  r_l_u,  s_grid, 'linear');
        r_unload_interp = interp1(s_un_u, r_un_u, s_grid, 'linear');
        
        diff_isteresi = abs(r_load_interp - r_unload_interp);
        [Delta_R_max(i), idx_h] = max(diff_isteresi);
        Strain_at_Hmax(i)       = s_grid(idx_h);
        H_max_R0_Perc(i)        = (Delta_R_max(i) / R0_usato) * 100;
    end
end

xlabel('Strain (%)', 'FontWeight', 'bold'); 
ylabel('\DeltaR (\Omega)', 'FontWeight', 'bold');
title(sprintf('Hysteresis Curve (%d cpm - %s )', cicli_al_minuto, definizione_grafico));
if ~isempty(h_salita) && ~isempty(h_discesa)
    legend([h_salita, h_discesa], {'Loading', 'Unloading'}, ...
           'Location', 'northeast', 'FontSize', 10);
end
hold off;

Tabella_Isteresi_R = table((1:N_cicli)', R0_vett, R_base_ciclo, Delta_R_max, H_max_R0_Perc, Drift_Residuo_Ohm, Strain_at_Hmax, ...
    'VariableNames', {'Ciclo', 'R0_Globale', 'R_base_ciclo', 'Delta_R_max', 'H_max_R0_Perc', 'Drift_Residuo_Ohm', 'Strain_at_Hmax'});
disp(Tabella_Isteresi_R);

% =========================================================================
% === 8. PLOT ANDAMENTO ISTERESI CICLO PER CICLO ===
% =========================================================================
fig_trend = figure('Name', 'Andamento Isteresi per Ciclo', 'NumberTitle', 'off', 'Color', 'w');
subplot(2, 1, 1);
plot(1:N_cicli, H_max_R0_Perc, '-o', 'LineWidth', 1.5, 'Color', 'b', 'MarkerFaceColor', 'b');
xlabel('Numero Ciclo'); ylabel('H_{max} (% R_0)');
title(sprintf('Errore Massimo di Isteresi su R_0 Globale (%.1f \\Omega) - %d cpm (%s)', R0_usato, cicli_al_minuto, tipo_pulito));
grid on;

subplot(2, 1, 2);
plot(1:N_cicli, Strain_at_Hmax, '-s', 'LineWidth', 1.5, 'Color', 'm', 'MarkerFaceColor', 'm');
xlabel('Numero Ciclo'); ylabel('Strain @ H_{max} (%)');
title('Posizione di Massima Apertura dell''Isteresi');
grid on;

% =========================================================================
% === 9. SALVATAGGIO AUTOMATICO DEI GRAFICI ===
% =========================================================================
% Cartella di destinazione dinamica: ./Grafici/isteresi_<tipo_prova>/
dir_grafici = fullfile('.', 'Grafici', sprintf('Isteresi_%s', tipo_pulito));
if ~exist(dir_grafici, 'dir')
    mkdir(dir_grafici);
end

% Salvataggio Curva di Isteresi
nome_fig_h = sprintf('Hysteresis_Curve_%s_%dcpm', tipo_pulito, cicli_al_minuto);
exportgraphics(fig_h, fullfile(dir_grafici, [nome_fig_h, '.pdf']), 'ContentType', 'vector');

% Salvataggio Andamento per Ciclo
nome_fig_trend = sprintf('Hysteresis_Trend_%s_%dcpm', tipo_pulito, cicli_al_minuto);
exportgraphics(fig_trend, fullfile(dir_grafici, [nome_fig_trend, '.pdf']), 'ContentType', 'vector');

end