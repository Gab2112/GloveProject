clear; close all; clc;

%% Parametri di acquisizione
porta_seriale = "COM3";
baudrate = 115200;

finestra = 15;           % durata finestra visualizzata (s)
threshold = 0.5;         % soglia per i picchi (V)
incertezza = 0.2;        % soglia per cammino bilanciato
min_peak_distance_sec = 0.3; % distanza min tra passi (secondi)

%% Connessione seriale
s = serialport(porta_seriale, baudrate);
configureTerminator(s, "LF");
flush(s);

%% Setup GUI
hFig = figure('Name','On-line observation','NumberTitle','off', 'WindowState','maximized');

% Pannello segnali
ax = subplot(1,2,1, 'Parent', hFig);
hold(ax, 'on');
h1 = animatedline(ax, 'Color', 'b', 'LineWidth', 2); % 5° metatarso
h2 = animatedline(ax, 'Color', 'r', 'LineWidth', 2); % 1° metatarso
xlabel(ax, 'Tempo [s]');
ylabel(ax, 'Tensione [V]');
title(ax, 'Variazione di pressione');
legend(ax, 'Quinto metatarso', 'Primo metatarso', 'Location', 'best');
grid(ax, 'on');
xlim(ax, [0 finestra]);
ylim(ax, [-3 3]);

stopBtn = uicontrol('Style', 'pushbutton', 'String', 'Stop', ...
    'Position', [20 20 70 30], ...
    'Callback', @(src,event) setappdata(hFig,'stop',true));
setappdata(hFig, 'stop', false);

%% Sagoma impronta e maschera
foot_ax = subplot(1,2,2, 'Parent', hFig);
load('sagoma_impronta_con_dita.mat'); % footX, footY, ditaX, ditaY, ditaR

nx = 300; ny = 150;
[Xg, Yg] = meshgrid(linspace(min(footX), max(footX), nx), linspace(min(footY), max(footY), ny));
in_foot = inpolygon(Xg, Yg, footX, footY);
for i=1:5
    in_foot = in_foot | ((Xg-ditaX(i)).^2 + (Yg-ditaY(i)).^2 <= ditaR(i)^2);
end

% Stima regioni: asse X crescente da interno a esterno
normX = (Xg - min(footX)) / (max(footX) - min(footX));
area_interna = normX <= 0.4;   % Primo metatarso (interno)
area_esterna = normX >= 0.6;   % Quinto metatarso (esterno)
area_centrale = ~(area_interna | area_esterna);

pressure_map = zeros(size(Xg));
colormap(foot_ax, jet);
pressure_img = imagesc(linspace(min(footX), max(footX), nx), ...
                       linspace(min(footY), max(footY), ny), ...
                       pressure_map, 'Parent', foot_ax, [0 1]);
set(pressure_img, 'AlphaData', in_foot*0.95);
hold(foot_ax, 'on');
plot(foot_ax, footX, footY, 'k-', 'LineWidth', 2);
theta = linspace(0,2*pi,80);
for i=1:5
    plot(foot_ax, ditaX(i) + ditaR(i)*cos(theta), ditaY(i) + ditaR(i)*sin(theta), 'k-', 'LineWidth', 2);
end
hold(foot_ax, 'off');
axis(foot_ax, 'image'); axis(foot_ax, 'off');
title(foot_ax, 'Mappa pressione plantare');
foot_text = text(mean(footX), min(footY)-0.05*range(footY), '', 'Parent', foot_ax, ...
    'HorizontalAlignment','center', 'FontWeight','bold','FontSize',12,'Color','k');

%% Acquisizione dati
data_ch1 = []; % Quinto metatarso
data_ch2 = []; % Primo metatarso
first_reading = true;

disp('Inizio esercizio');
while ishghandle(hFig)
    if getappdata(hFig,'stop')
        break
    end
    read = readline(s);
    parts = strsplit(read, {' ', ';'});
    if numel(parts) >= 3
        ch1_val = str2double(parts{3}); % Quinto metatarso
        ch2_val = str2double(parts{2}); % Primo metatarso
        if ~isnan(ch1_val) && ~isnan(ch2_val)
            if first_reading
                t0 = datetime('now');
                first_reading = false;
            end
            t = seconds(datetime('now') - t0);
            addpoints(h1, t, ch1_val);
            addpoints(h2, t, ch2_val);
            data_ch1(end+1,:) = [t, ch1_val];
            data_ch2(end+1,:) = [t, ch2_val];
            x_start = max(0, t - finestra);
            xlim(ax, [x_start x_start+finestra]);
            drawnow limitrate;

            % --- Aggiorna la mappa pressione colora solo le zone corrispondenti ---
            toll = incertezza;
            % Normalizza valori tra 0 e 1 per la colormap
            val1 = max(0,min(1,(ch2_val+3)/6)); % Primo metatarso, colora interno (rosso)
            val2 = max(0,min(1,(ch1_val+3)/6)); % Quinto metatarso, colora esterno (blu)
            % Crea mappa
            new_map = nan(size(pressure_map));
            new_map(area_interna & in_foot) = val1;      % interno
            new_map(area_esterna & in_foot) = val2;      % esterno
            new_map(area_centrale & in_foot) = (val1+val2)/2; % centrale interpolata
            set(pressure_img, 'CData', new_map);

            % Aggiorna testo
            if ch1_val > ch2_val + toll
                footMsg = 'Carico su esterno (quinto metatarso)';
                textColor = [0 0 1];
            elseif ch2_val > ch1_val + toll
                footMsg = 'Carico su interno (primo metatarso)';
                textColor = [1 0 0];
            else
                footMsg = 'Carico bilanciato';
                textColor = [0 0.7 0];
            end
            set(foot_text, 'String', footMsg, 'Color', textColor);
        end
    end
end

delete(s);
disp('Termine esercizio');

%% Analisi post-acquisizione (opzionale)
time_ch1 = data_ch1(:,1);
ch1 = data_ch1(:,2);
time_ch2 = data_ch2(:,1);
ch2 = data_ch2(:,2);
Fs_est = 1/median(diff(time_ch1)); % Stima frequenza di campionamento

% Calcola segnale medio e energie
mean_signal = (ch1 + ch2) / 2;
energy_signal1 = mean(ch1.^2);
energy_signal2 = mean(ch2.^2);
energy_mean_signal = mean(mean_signal.^2);

% Analisi pressione
if energy_signal1 > energy_signal2
    msg = 'Maggiore pressione sotto il quinto metatarso (cammino in extrarotazione).';
elseif energy_signal2 > energy_signal1
    msg = 'Maggiore pressione sotto il primo metatarso (cammino in intrarotazione).';
elseif abs(energy_signal1-energy_signal2) < incertezza
    msg = 'Cammino bilanciato.';
else
    msg = 'Analisi pressione non determinata.';
end

% --- Analisi cadenza (conta passi) ---
MinPeakDistance = round(min_peak_distance_sec * Fs_est);

[pks1, locs1] = findpeaks(ch1, 'MinPeakHeight', threshold, 'MinPeakDistance', MinPeakDistance);
[pks2, locs2] = findpeaks(ch2, 'MinPeakHeight', threshold, 'MinPeakDistance', MinPeakDistance);

% Unisci e ordina indici dei picchi (passi)
all_peak_indices = sort(unique([locs1; locs2]));
num_peaks = numel(all_peak_indices);

% Visualizza i picchi nella GUI
axes(ax); % seleziona il grafico segnali
plot(ax, time_ch1(locs1), ch1(locs1), 'ob', 'MarkerFaceColor', 'b');
plot(ax, time_ch2(locs2), ch2(locs2), 'or', 'MarkerFaceColor', 'r');

% Messaggio finale
msgbox({msg; ['Numero passi rilevati: ' num2str(num_peaks)]}, 'Risultato Analisi');

disp(msg);
disp(['Numero passi rilevati: ' num2str(num_peaks)]);
