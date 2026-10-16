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

% =========================================================================
% === 0. IMPOSTAZIONI INIZIALI ED ETICHETTE ===
% =========================================================================
tipo_pulito = lower(strtrim(string(tipo_prova)));
tipo_pulito = regexprep(tipo_pulito, '^sensore[\s_]*', '');
if strcmp(tipo_pulito, 'lungo')
    definizione_grafico = 'Long Sensor';
elseif strcmp(tipo_pulito, 'corto')
    definizione_grafico = 'Short Sensor';
elseif strcmp(tipo_pulito, 'medio')
    definizione_grafico = 'Medium Sensor';
else
    definizione_grafico = 'Sensor';
end

if isempty(frequenza_campionamento) || frequenza_campionamento <= 0
    frequenza_campionamento = 100;
end

% =========================================================================
% === 1. IMPORTAZIONE ED ELABORAZIONE PRELIMINARE ===
% =========================================================================
% --- Instron (Dati Meccanici) ---
opts_m = delimitedTextImportOptions("NumVariables", 3);
opts_m.DataLines = [3, Inf];
opts_m.Delimiter = ";";
opts_m.VariableNames = ["Tempo", "Spostamento", "Forza"];
opts_m.VariableTypes = ["double", "double", "double"];
opts_m.ExtraColumnsRule = "ignore";
opts_m.EmptyLineRule = "skip";

opts_m = setvaropts(opts_m, ["Tempo", "Spostamento", "Forza"], "TrimNonNumeric", true);
opts_m = setvaropts(opts_m, ["Tempo", "Spostamento", "Forza"], "DecimalSeparator", ",");
opts_m = setvaropts(opts_m, ["Tempo", "Spostamento", "Forza"], "ThousandsSeparator", ".");

tbl_m = readtable(file_meccanico, opts_m);
m_tempo_raw = tbl_m.Tempo;
m_corsa_raw = tbl_m.Spostamento;
m_carico_raw = tbl_m.Forza;

% Bonifica da NaN e Inf
idx_valid = isfinite(m_tempo_raw) & isfinite(m_corsa_raw) & isfinite(m_carico_raw);
m_tempo_clean = m_tempo_raw(idx_valid);
m_corsa_clean = m_corsa_raw(idx_valid);
m_carico_clean = m_carico_raw(idx_valid);

% Rimozione duplicati temporali e ordinamento rigorosamente crescente
[m_tempo_unique, idx_unique] = unique(m_tempo_clean, 'sorted');
m_corsa_unique  = m_corsa_clean(idx_unique);
m_carico_unique = m_carico_clean(idx_unique);

% Ricampionamento uniforme a frequenza_campionamento
dt = 1 / frequenza_campionamento;
tempo_f = (m_tempo_unique(1):dt:m_tempo_unique(end))';
instron_corsa  = interp1(m_tempo_unique, m_corsa_unique,  tempo_f, 'linear', 'extrap');
instron_carico = interp1(m_tempo_unique, m_carico_unique, tempo_f, 'linear', 'extrap');
instron_tempo  = tempo_f;

% --- Sensore DAQ (Dati Elettrici) ---
opts_e = delimitedTextImportOptions("NumVariables", 3);
opts_e.DataLines = [24, Inf];
opts_e.Delimiter = "\t";
opts_e.VariableNames = ["LabVIEWMeasurement", "VarName2", "Var3"];
opts_e.SelectedVariableNames = ["LabVIEWMeasurement", "VarName2"];
opts_e.VariableTypes = ["double", "double", "string"];
opts_e.ExtraColumnsRule = "ignore";
opts_e.EmptyLineRule = "skip";
opts_e = setvaropts(opts_e, ["LabVIEWMeasurement", "VarName2"], "TrimNonNumeric", true);
opts_e = setvaropts(opts_e, ["LabVIEWMeasurement", "VarName2"], "DecimalSeparator", ",");
opts_e = setvaropts(opts_e, ["LabVIEWMeasurement", "VarName2"], "ThousandsSeparator", ".");

data_e = readtable(file_elettrico, opts_e);
data_arr = table2array(data_e);

sensore_tensione_raw = data_arr(:, 2);

% Filtraggio segnale di tensione
if isempty(finestre) || finestre <= 0
    span = 10;
else
    span = finestre;
end
sensore_tensione_filt = smooth(sensore_tensione_raw, span);

% =========================================================================
% === 2. SELEZIONE INTERATTIVA (GINPUT DINAMICO SUI MINIMI/MASSIMI) ===
% =========================================================================
% Finestra di ricerca dinamica: metà di un semiciclo (~25% del periodo totale)
% A 12 cpm -> ~125 campioni; a 60 cpm -> ~25 campioni.
durata_singolo_ciclo = 60 / cicli_al_minuto;
campioni_per_ciclo   = frequenza_campionamento * durata_singolo_ciclo;
w_dinamica           = max(25, round(campioni_per_ciclo * 0.25));

% --- 1. Corsa Instron: ricerca MINIMO locale a riposo ---
fig_c = figure('Name', 'Selezione Corsa Instron', 'NumberTitle', 'off');
plot(instron_corsa, 'b', 'LineWidth', 1.2); hold on;
title(sprintf('INSTRON CORSA (%d cpm): Clicca INIZIO e FINE sui MINIMI a riposo', cicli_al_minuto), ...
      'FontName', 'Times New Roman');
xlabel('Campioni'); ylabel('Corsa [mm]');
grid on;
disp('INSTRON CORSA: Clicca su due punti in corrispondenza del PRIMO e dell''ULTIMO MINIMO (riposo).');
drawnow;
[x_instron, ~] = ginput(2);

x_instron = sort(x_instron);
instron_start_raw = round(x_instron(1));
instron_end_raw   = round(x_instron(2));

% Raffinamento locale con finestra adattativa
idx_s_min = max(1, instron_start_raw - w_dinamica);
idx_s_max = min(length(instron_corsa), instron_start_raw + w_dinamica);
[~, c_s] = min(instron_corsa(idx_s_min:idx_s_max));
instron_start = idx_s_min + c_s - 1;

idx_e_min = max(1, instron_end_raw - w_dinamica);
idx_e_max = min(length(instron_corsa), instron_end_raw + w_dinamica);
[~, c_e] = min(instron_corsa(idx_e_min:idx_e_max));
instron_end = idx_e_min + c_e - 1;

% Feedback visivo dell'aggancio effettivo
plot(instron_start, instron_corsa(instron_start), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 8);
plot(instron_end,   instron_corsa(instron_end),   'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
drawnow; pause(0.5);
close(fig_c);

% --- 2. Tensione DAQ: ricerca MASSIMO locale a riposo ---
fig_s = figure('Name', 'Selezione Tensione Sensore', 'NumberTitle', 'off');
plot(sensore_tensione_filt, 'm', 'LineWidth', 1.2); hold on;
title(sprintf('DAQ SENSORE (%d cpm): Clicca INIZIO e FINE sui MASSIMI di tensione (riposo)', cicli_al_minuto), ...
      'FontName', 'Times New Roman');
xlabel('Campioni'); ylabel('Tensione [V]');
grid on;
disp('DAQ SENSORE: Clicca su due punti in corrispondenza del PRIMO e dell''ULTIMO MASSIMO (riposo).');
drawnow;
[x_sensore, ~] = ginput(2);

x_sensore = sort(x_sensore);
sensore_start_raw = round(x_sensore(1));
sensore_end_raw   = round(x_sensore(2));

% Raffinamento locale con finestra adattativa
idx_vs_min = max(1, sensore_start_raw - w_dinamica);
idx_vs_max = min(length(sensore_tensione_filt), sensore_start_raw + w_dinamica);
[~, c_vs] = max(sensore_tensione_filt(idx_vs_min:idx_vs_max));
sensore_start = idx_vs_min + c_vs - 1;

idx_ve_min = max(1, sensore_end_raw - w_dinamica);
idx_ve_max = min(length(sensore_tensione_filt), sensore_end_raw + w_dinamica);
[~, c_ve] = max(sensore_tensione_filt(idx_ve_min:idx_ve_max));
sensore_end = idx_ve_min + c_ve - 1;

% Feedback visivo dell'aggancio effettivo
plot(sensore_start, sensore_tensione_filt(sensore_start), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 8);
plot(sensore_end,   sensore_tensione_filt(sensore_end),   'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 8);
drawnow; pause(0.5);
close(fig_s);

% =========================================================================
% === 3. FINESTRATURA, SINCRONIZZAZIONE E PARTITORE ===
% =========================================================================
Tempo_f  = instron_tempo(instron_start:instron_end) - instron_tempo(instron_start);
Corsa_f  = instron_corsa(instron_start:instron_end);
Carico_f = instron_carico(instron_start:instron_end);
sensore_V_fin = sensore_tensione_filt(sensore_start:sensore_end);

% Allineamento lunghezze
L_min = min(length(Corsa_f), length(sensore_V_fin));
Tempo_f       = Tempo_f(1:L_min);
Corsa_f       = Corsa_f(1:L_min);
Carico_f      = Carico_f(1:L_min);
sensore_V_fin = sensore_V_fin(1:L_min);

% Formula partitore lato terra: R_sensore in Ohm (Rfissa = 300 kOhm, Vcc = 5V)
R_fissa = 300e3;
sensore_R_Ohm = (sensore_V_fin ./ (5 - sensore_V_fin)) * R_fissa;

Dati_Completi = table(Tempo_f, Corsa_f, Carico_f, sensore_V_fin, sensore_R_Ohm, ...
    'VariableNames', {'Tempo', 'Spostamento', 'Forza', 'Voltaggio', 'R_sensore'});

% Scarto cicli transitori (inizio e fine)
tempo_start_valido = Dati_Completi.Tempo(1) + (cicli_da_scartare_inizio * durata_singolo_ciclo);
tempo_end_valido   = Dati_Completi.Tempo(end) - (cicli_da_scartare_fine * durata_singolo_ciclo);

Dati_Filtro_Cicli = Dati_Completi(Dati_Completi.Tempo >= tempo_start_valido & ...
                                 Dati_Completi.Tempo <= tempo_end_valido, :);

if ~isempty(file_output)
    writetable(Dati_Filtro_Cicli, file_output);
    fprintf('Dati filtrati salvati con successo in: %s\n', file_output);
end

% =========================================================================
% === 4. IDENTIFICAZIONE DEI PICCHI E ALLINEAMENTO CICLI (ROBUSTA) ===
% =========================================================================
Corsa_sig = Dati_Filtro_Cicli.Spostamento;
V_sig     = Dati_Filtro_Cicli.Voltaggio;
R_sig     = Dati_Filtro_Cicli.R_sensore;
T_sig     = Dati_Filtro_Cicli.Tempo - Dati_Filtro_Cicli.Tempo(1);

n_pts_ciclo     = round(frequenza_campionamento * durata_singolo_ciclo);
distanza_minima = round(n_pts_ciclo * 0.55);
prominenza_X    = (max(Corsa_sig) - min(Corsa_sig)) * 0.25;
prominenza_V    = (max(V_sig) - min(V_sig)) * 0.25;

% Ricerca picchi meccanici
[~, Max_Idx_raw] = findpeaks(Corsa_sig,  'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_X);
[~, Min_Idx_raw] = findpeaks(-Corsa_sig, 'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_X);

% Ricerca picchi elettrici (Voltaggio)
[~, Max_V_raw]   = findpeaks(V_sig,  'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_V);
[~, Min_V_raw]   = findpeaks(-V_sig, 'MinPeakDistance', distanza_minima, 'MinPeakProminence', prominenza_V);

% Triplette rigorose: Min_Start -> Max_Peak -> Min_End
valid_cycles = [];
for k = 1:length(Min_Idx_raw)-1
    m_start = Min_Idx_raw(k);
    m_end   = Min_Idx_raw(k+1);
    
    p_max = Max_Idx_raw(Max_Idx_raw > m_start & Max_Idx_raw < m_end);
    if length(p_max) == 1
        valid_cycles = [valid_cycles; m_start, p_max, m_end]; %#ok<AGROW>
    end
end

if isempty(valid_cycles)
    error('Errore di sincronizzazione a %d cpm: impossibile accoppiare i picchi di corsa.', cicli_al_minuto);
end

MinPeaksCorsa_Idx  = valid_cycles(:, 1);
MaxPeaksCorsa_Idx  = valid_cycles(:, 2);
MinPeaksCorsa_Next = valid_cycles(:, 3);
N_cicli = size(valid_cycles, 1);

% =========================================================================
% === 4-BIS. PLOT DI VERIFICA SINCRONIZZAZIONE (DEFORMAZIONE VS VOLTAGGIO) ===
% =========================================================================
strain_totale = (Corsa_sig / L0) * 100;

fig_check = figure('Name', 'Verifica Sincronizzazione: Deformazione vs Voltaggio', ...
                   'NumberTitle', 'off', 'Color', 'w');

% --- Asse Sinistro: Deformazione Meccanica ---
yyaxis left
h_strain = plot(T_sig, strain_totale, 'Color', [0 0.4470 0.7410], 'LineWidth', 1.5, ...
                'DisplayName', '\epsilon [%]');
hold on;
h_strain_min = plot(T_sig(MinPeaksCorsa_Idx), strain_totale(MinPeaksCorsa_Idx), 'bs', ...
                    'MarkerFaceColor', [0 0.4470 0.7410], 'MarkerSize', 6, ...
                    'DisplayName', 'Min \epsilon (Inizio Ciclo)');
h_strain_max = plot(T_sig(MaxPeaksCorsa_Idx), strain_totale(MaxPeaksCorsa_Idx), 'r^', ...
                    'MarkerFaceColor', 'r', 'MarkerSize', 6, ...
                    'DisplayName', 'Max \epsilon (Trazione)');
ylabel('Deformazione \epsilon [%]', 'FontName', 'Times New Roman', 'FontSize', 14, 'FontWeight', 'bold');
ax = gca;
ax.YColor = [0 0.4470 0.7410];

% --- Asse Destro: Voltaggio Elettrico ---
yyaxis right
h_volt = plot(T_sig, V_sig, 'Color', [0.8500 0.3250 0.0980], 'LineWidth', 1.5, ...
              'DisplayName', 'Voltaggio [V]');
h_volt_max = plot(T_sig(Max_V_raw), V_sig(Max_V_raw), 'go', ...
                  'MarkerFaceColor', [0.4660 0.6740 0.1880], 'MarkerSize', 6, ...
                  'DisplayName', 'Max V (Riposo)');
h_volt_min = plot(T_sig(Min_V_raw), V_sig(Min_V_raw), 'mv', ...
                  'MarkerFaceColor', 'm', 'MarkerSize', 6, ...
                  'DisplayName', 'Min V (Max Trazione)');
ylabel('Tensione [V]', 'FontName', 'Times New Roman', 'FontSize', 14, 'FontWeight', 'bold');
ax.YColor = [0.8500 0.3250 0.0980];

xlabel('Tempo [s]', 'FontName', 'Times New Roman', 'FontSize', 14, 'FontWeight', 'bold');
title(sprintf('Verifica Allineamento Temporale e Picchi (%d cpm - %s)', cicli_al_minuto, tipo_pulito), ...
      'FontName', 'Times New Roman', 'FontSize', 15);
grid on;
legend([h_strain, h_strain_min, h_strain_max, h_volt, h_volt_max, h_volt_min], ...
       'Location', 'best', 'NumColumns', 2, 'FontName', 'Times New Roman', 'FontSize', 10);
set(gca, 'FontName', 'Times New Roman', 'FontSize', 12);
xlim([0, max(T_sig)]);

% =========================================================================
% === 5. CALCOLO DELL'ISTERESI E GENERAZIONE CURVE ===
% =========================================================================
if ~isempty(R0_imposto) && R0_imposto > 0
    R0_usato = R0_imposto;
else
    R0_usato = mean(R_sig(1:min(20, length(R_sig))));
end

Delta_R_max_Ohm   = zeros(N_cicli, 1);
Delta_R_max_kOhm  = zeros(N_cicli, 1);
R0_ciclo_vett     = zeros(N_cicli, 1);
H_max_R0_Perc     = zeros(N_cicli, 1);
Strain_at_Hmax    = zeros(N_cicli, 1);
Drift_Residuo_Ohm = zeros(N_cicli, 1);
R0_globale_vett   = repmat(R0_usato, N_cicli, 1);

fig_h = figure('Name', 'Cicli di Isteresi', 'NumberTitle', 'off', 'Color', 'w');
hold on; grid on;
h_salita = []; h_discesa = [];

for i = 1:N_cicli
    idx_min_1 = MinPeaksCorsa_Idx(i);
    idx_max   = MaxPeaksCorsa_Idx(i);
    idx_min_2 = MinPeaksCorsa_Next(i);
    
    salita_instron  = Corsa_sig(idx_min_1 : idx_max);
    discesa_instron = Corsa_sig(idx_max : idx_min_2);
    
    salita_sensore  = R_sig(idx_min_1 : idx_max);
    discesa_sensore = R_sig(idx_max : idx_min_2);
    
    r_zero = salita_sensore(1);
    R0_ciclo_vett(i)     = r_zero;
    Drift_Residuo_Ohm(i) = discesa_sensore(end) - r_zero;
    
    % Interpolazione sulla lunghezza della fase di salita
    len_s = length(salita_instron);
    discesa_instron_interp = interp1(1:length(discesa_instron), discesa_instron, 1:len_s, 'linear', 'extrap')';
    salita_sensore_interp  = interp1(1:length(salita_sensore),  salita_sensore,  1:len_s, 'linear', 'extrap')';
    discesa_sensore_interp = interp1(1:length(discesa_sensore), discesa_sensore, 1:len_s, 'linear', 'extrap')';
    
    % Calcolo Strain (%) e Delta R rispetto al riposo [kOhm]
    strain_salita  = (salita_instron / L0) * 100;
    strain_discesa = (flip(discesa_instron_interp) / L0) * 100;
    
    deltaR_salita_kOhm  = (salita_sensore_interp - r_zero) * 1e-3;
    deltaR_discesa_kOhm = (flip(discesa_sensore_interp) - r_zero) * 1e-3;
    
    h1 = plot(strain_salita,  deltaR_salita_kOhm,  'Color', [0.9, 0, 0], 'LineWidth', 1.2);
    if isempty(h_salita), h_salita = h1; end
    
    h2 = plot(strain_discesa, deltaR_discesa_kOhm, 'Color', [0, 0, 0.9], 'LineWidth', 1.2);
    if isempty(h_discesa), h_discesa = h2; end
    
    % Calcolo H_max su intervallo di strain normalizzato
    s_min = max(min(strain_salita), min(strain_discesa));
    s_max = min(max(strain_salita), max(strain_discesa));
    delta_s = s_max - s_min;
    
    s_inf = s_min + (taglio_inizio_perc * delta_s);
    s_sup = s_max - (taglio_fine_perc   * delta_s);
    
    if s_sup > s_inf
        s_grid = linspace(s_inf, s_sup, 250);
        r_sal_grid = interp1(strain_salita, salita_sensore_interp, s_grid, 'linear');
        r_dis_grid = interp1(strain_discesa, flip(discesa_sensore_interp), s_grid, 'linear');
        
        diff_isteresi = abs(r_sal_grid - r_dis_grid);
        [max_diff, idx_h_max] = max(diff_isteresi);
        
        Delta_R_max_Ohm(i)  = max_diff;
        Delta_R_max_kOhm(i) = max_diff * 1e-3;
        Strain_at_Hmax(i)   = s_grid(idx_h_max);
        H_max_R0_Perc(i)    = (max_diff / r_zero) * 100;
    end
end

xlabel('Strain \epsilon [%]', 'FontName', 'Times New Roman', 'FontSize', 15);
ylabel('\DeltaR [k\Omega]', 'FontName', 'Times New Roman', 'FontSize', 15);
title(sprintf('Hysteresis Cicles (%d cpm - %s)', cicli_al_minuto, definizione_grafico), ...
      'FontName', 'Times New Roman', 'FontSize', 16);
if ~isempty(h_salita) && ~isempty(h_discesa)
    legend([h_salita, h_discesa], {'Loading', 'Unloading'}, ...
           'FontName', 'Times New Roman', 'Location', 'northeast');
end
set(gca, 'FontName', 'Times New Roman', 'FontSize', 14);
hold off;

% Costruzione Tabella di Uscita
Tabella_Isteresi_R = table((1:N_cicli)', R0_globale_vett, R0_ciclo_vett, ...
    Delta_R_max_Ohm, Delta_R_max_kOhm, H_max_R0_Perc, Drift_Residuo_Ohm, Strain_at_Hmax, ...
    'VariableNames', {'Ciclo', 'R0_Globale', 'R0_Ciclo', ...
                      'Delta_R_max', 'Delta_R_max_kOhm', 'H_max_R0_Perc', 'Drift_Residuo_Ohm', 'Strain_at_Hmax'});

% =========================================================================
% === 6. PLOT ANDAMENTO E SALVATAGGIO DEI GRAFICI ===
% =========================================================================
fig_trend = figure('Name', 'Andamento Isteresi per Ciclo', 'NumberTitle', 'off', 'Color', 'w');
subplot(2, 1, 1);
plot(1:N_cicli, H_max_R0_Perc, '-o', 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410], 'MarkerFaceColor', [0 0.4470 0.7410]);
xlabel('Numero Ciclo', 'FontName', 'Times New Roman');
ylabel('H_{max} [% R_{0,ciclo}]', 'FontName', 'Times New Roman');
title(sprintf('Errore di Isteresi su R_{0,ciclo} - %d cpm (%s)', cicli_al_minuto, tipo_pulito), 'FontName', 'Times New Roman');
grid on;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 12);

subplot(2, 1, 2);
plot(1:N_cicli, Strain_at_Hmax, '-s', 'LineWidth', 1.5, 'Color', [0.6350 0.0780 0.1840], 'MarkerFaceColor', [0.6350 0.0780 0.1840]);
xlabel('Numero Ciclo', 'FontName', 'Times New Roman');
ylabel('Strain @ H_{max} [%]', 'FontName', 'Times New Roman');
title('Posizione di Massima Apertura dell''Isteresi', 'FontName', 'Times New Roman');
grid on;
set(gca, 'FontName', 'Times New Roman', 'FontSize', 12);

dir_grafici = fullfile('.', 'Grafici', sprintf('Isteresi_%s', tipo_pulito));
if ~exist(dir_grafici, 'dir')
    mkdir(dir_grafici);
end

% Salvataggio figura diagnostica sincronizzazione
nome_fig_check = sprintf('Alignment_Check_%s_%dcpm', tipo_pulito, cicli_al_minuto);
exportgraphics(fig_check, fullfile(dir_grafici, [nome_fig_check, '.pdf']), 'ContentType', 'vector');

% Salvataggio curva di isteresi
nome_fig_h = sprintf('Hysteresis_Curve_%s_%dcpm', tipo_pulito, cicli_al_minuto);
exportgraphics(fig_h, fullfile(dir_grafici, [nome_fig_h, '.pdf']), 'ContentType', 'vector');

% Salvataggio andamento metriche per ciclo
nome_fig_trend = sprintf('Hysteresis_Trend_%s_%dcpm', tipo_pulito, cicli_al_minuto);
exportgraphics(fig_trend, fullfile(dir_grafici, [nome_fig_trend, '.pdf']), 'ContentType', 'vector');

end