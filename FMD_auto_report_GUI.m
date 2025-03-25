
%% FIRST GUI SELECTION DOES THE FOLLOW

% Seleziona il file video
[videoFile, videoPath] = uigetfile({'*.mp4;*.avi', 'Video Files (*.mp4, *.avi)'}, 'Select Video File');
if isequal(videoFile, 0)
    disp('File selection cancelled');
    return;
end
videoPathFile = fullfile(videoPath, videoFile);
videoObj = VideoReader(videoPathFile);

%% SECOND GUI SELECTION DOES THE FOLLOW (Only if first gui selection has been run succesfully)


% Calibrazione spaziale
pixelTocm = spatial_calibration(videoObj, 1); % Usa il primo frame per la calibrazione

% Selezione della ROI (area di interesse)
data = readFrame(videoObj);
data = rgb2gray(data);

figure(1); 

clf;
imshow(data);
uiwait(msgbox('Select Artery Range-of-Interest (ROI)', 'Instruction', 'modal'));
[~, rect] = imcrop(data); % L'utente seleziona la ROI
data = imcrop(data, rect);
[n, m] = size(data);
close(1);

% Definizione linea di riferimento tra i bordi
ref_line = Cut_Between(data);

% Inizializzazione vettori
Orientation = zeros(videoObj.NumFrames, 1);
distance = zeros(videoObj.NumFrames, 1);

% Determina il percorso e il nome del file originale
[originalPath, originalName, ~] = fileparts(videoPathFile);

% Crea il nome del file per il video tracciato (nella stessa directory del video originale)
trackedVideoName = fullfile(originalPath, ['tracked_' originalName '.mp4']);

% Configura il VideoWriter per salvare il video tracciato
videoTracked = VideoWriter(trackedVideoName, 'MPEG-4');
videoTracked.FrameRate = videoObj.FrameRate;


%% THIRD GUI SELECTION DOES THE FOLLOW (Only if SECOND gui selection has been run succesfully)


% Apri il VideoWriter per iniziare a scrivere il video
open(videoTracked);

% Barra di avanzamento
Wbar = waitbar(0, 'Analyzing...');

% Analisi del video frame per frame
frameIdx = 1;
while hasFrame(videoObj)
    waitbar(frameIdx / videoObj.NumFrames, Wbar);

    % Acquisizione e elaborazione del frame corrente
    data = readFrame(videoObj);
    data = rgb2gray(data);
    data = imcrop(data, rect);

    % Rilevamento bordi
    [bordo_inferiore, bordo_superiore] = Border_Detection(data, ref_line, false);

    % Calcolo distanza e angolo
    distance(frameIdx) = mean(bordo_inferiore - bordo_superiore, "all", "omitnan");
    p = polyfit(1:m, bordo_superiore, 1);
    Up_Y = polyval(p, [1 m]);
    p = polyfit(1:m, bordo_inferiore, 1);
    Low_Y = polyval(p, [1 m]);

    v_1 = [1, Up_Y(2), 0] - [1, Up_Y(1), 0];
    v_2 = [1, Low_Y(2), 0] - [1, Low_Y(1), 0];
    Orientation(frameIdx) = atan2d(norm(cross(v_1, v_2)), dot(v_1, v_2));
    set(gcf, 'Resize', 'off');         % Disabilita ridimensionamento della finestra

    figure(1);    % Assicura che la figura sia attivata
clf;          % Pulisce il contenuto della figura
imshow(data); % Mostra il frame grezzo
drawnow;      % Forza il rendering immediato

    
    
%     imshow(data); % Mostra il frame grezzo
    hold on;
    plot(bordo_inferiore, '-', 'LineWidth', 1.5, 'Color', 'red'); % Bordo inferiore
    plot(bordo_superiore, '-', 'LineWidth', 1.5, 'Color', 'red'); % Bordo superiore
    hold off;
    
    % Scrivi il frame nel video tracciato
    F = getframe(gcf); % Cattura il frame con i bordi sovrapposti
    writeVideo(videoTracked, F);

    frameIdx = frameIdx + 1;
end

% Chiudi il video tracciato e la barra di avanzamento
close(videoTracked); % Aggiungi questa linea per chiudere correttamente il video
close(Wbar);
close(1); % Chiude la figura 1

% Elaborazione finale
Time = (0:1/videoObj.FrameRate:(videoObj.NumFrames-1)/videoObj.FrameRate)';
Time = round(Time, 3);
Orientation = fillmissing(Orientation, 'nearest');
diameter = distance .* cosd(Orientation) / pixelTocm;
diameterFilt = round(sgolayfilt(diameter, 3, 11), 4);

% Salvataggio dei risultati
[path, name] = fileparts(videoPathFile);
if ~exist(fullfile(path, 'FMD_reports'), 'dir')
    mkdir(fullfile(path, 'FMD_reports'));
end



%% FMD
% Finestra di dialogo per inserire i valori di baseline
prompt = {'Baseline start (s):', 'Baseline end (s):', 'Cuff release (s)'};
dlgtitle = 'Values';
dims = [1 35];
definput = {'1', '2', '3'};
baselineVals = inputdlg(prompt, dlgtitle, dims, definput);
 
% Verifica che l'utente non abbia annullato e che i valori siano numerici
if isempty(baselineVals)
    disp('Operation cancelled.');
    return;
end
 
baseline1 = str2double(baselineVals{1});
baseline2 = str2double(baselineVals{2});
baseline3 = str2double(baselineVals{3});
 
% Verifica che i valori siano numerici e positivi
if any([isnan(baseline1), isnan(baseline2), isnan(baseline3)]) || any([baseline1, baseline2, baseline3] <= 0)
    error('Baseline values must be numeric and positive.');
end
 
% Assicura che baseline1 sia minore di baseline2, e baseline2 minore di baseline3
baselineValsSorted = sort([baseline1, baseline2, baseline3]);
baseline1 = baselineValsSorted(1);
baseline2 = baselineValsSorted(2);
baseline3 = baselineValsSorted(3);
 
% Trova gli indici più vicini ai valori di baseline1 e baseline2
[~, idx1] = min(abs(Time - baseline1));
[~, idx2] = min(abs(Time - baseline2));
 
% Calcola la media dei valori di diameterFilt tra i due indici di baseline
meanDiameterBaseline = nanmean(diameterFilt(idx1:idx2));
 
% Inizia il ciclo per le finestre di tempo
windowSize = 5; % dimensione finestra in secondi
timeStart = baseline3; % inizia con baseline3
percentChanges = []; % Vettore per i cambiamenti percentuali
diameters_during_FMD = []; 
timeLabels = {}; % Etichette temporali per l'asse x del grafico
 
% Inizia il ciclo per le finestre di tempo
while timeStart + windowSize <= max(Time)
    timeEnd = timeStart + windowSize;
    
    % Trova gli indici più vicini ai tempi di inizio e fine della finestra
    [~, idxStart] = min(abs(Time - timeStart));
    [~, idxEnd] = min(abs(Time - timeEnd));
    
    % Calcola la media dei valori di diameterFilt nella finestra
    meanDiameterWindow = mean(diameterFilt(idxStart:idxEnd));
    diameters_during_FMD = [diameters_during_FMD; meanDiameterWindow];
 
    % Calcola la variazione percentuale rispetto al valore medio della baseline
    percentChange = (meanDiameterWindow / meanDiameterBaseline - 1) * 100;

    percentChanges = [percentChanges; percentChange];
    
    % Aggiungi la label temporale per l'asse x
    timeLabels = [timeLabels, [num2str(timeStart), '-', num2str(timeEnd), 's']];
    
    % Aggiorna il tempo di inizio per la prossima finestra
    timeStart = timeEnd;
end
  
% Plottaggio dei cambiamenti percentuali
fig = figure('Visible', 'off');

bar(percentChanges); % Grafico a barre dei cambiamenti percentuali
 
% Creazione delle etichette dell'asse X con intervalli di 5s
timeLabelsModified = cell(1, length(percentChanges));
for i = 1:length(percentChanges)
    startTime = (i - 1) * 5; % Tempo di inizio dell'intervallo (0-5s, 5-10s, ecc.)
    endTime = startTime + 5;  % Tempo di fine dell'intervallo (5-10s, 10-15s, ecc.)
    timeLabelsModified{i} = [num2str(startTime), '-', num2str(endTime), 's']; % Etichetta del tempo
end
 
% Imposta le etichette dell'asse X
set(gca, 'XTick', 1:length(percentChanges)); % Posizione dei tick sull'asse X
set(gca, 'XTickLabel', timeLabelsModified);  % Etichette temporali modificate
% xlabel('Tempi (Finestra di 5s)');
% ylabel('Variazione Percentuale (%)');
% title('Variazione Percentuale di diameterFilt in Funzione del Tempo');
xlabel('Time (5s Window)');
ylabel('Percentage Change (%)');
title('Percentage Change of diameter as a function of time');

xtickangle(45); % Ruota le etichette sull'asse x per migliorare la visibilità

% Salva il grafico come immagine
saveas(fig, 'grafico_percentChanges.jpg', 'jpg');

% Chiudi la figura appena creata
close(fig);  % Chiude la figura corrente

% Creazione della tabella
fig = figure('Visible', 'off');

% Dati da visualizzare nella tabella
timeIntervals = (0:length(percentChanges)-1)'*windowSize; % Calcola gli intervalli di tempo in secondi
timeIntervalsLabels = strcat(num2str(timeIntervals), '-', num2str(timeIntervals + windowSize), 's'); % Etichette del tempo per la tabella
 
% Assicurati che timeIntervalsLabels sia una colonna singola
timeIntervalsLabels = cellstr(timeIntervalsLabels); % Converti a cella per compatibilità
 
% Combinazione di tempo e cambiamento percentuale
data = [timeIntervalsLabels, num2cell(percentChanges)]; % Combina le etichette e i dati numerici
 
% Dimensioni della cella della tabella
rowHeight = 22; % Altezza di ogni riga in pixel
headerHeight = 25; % Altezza dell'intestazione della tabella
numRows = size(data, 1); % Numero di righe della tabella
tableHeight = numRows * rowHeight + headerHeight; % Altezza totale della tabella
 
% Creazione della tabella statica
% t = uitable('Data', data, ...
%     'ColumnName', {'Intervallo di Tempo (s)', 'Variazione Percentuale (%)'}, ...
%     'RowName', [], 'ColumnWidth', {200, 150});
t = uitable('Data', data, ... 
    'ColumnName', {'Time Interval (s)', 'Percentage Change (%)'}, ...
    'RowName', [], 'ColumnWidth', {200, 150});

 
% Calcola la posizione della tabella e della finestra
tableWidth = 400; % Larghezza della tabella
windowWidth = tableWidth + 50; % Aggiungi margine per la finestra
windowHeight = tableHeight + 50; % Aggiungi margine per la finestra
 
% Imposta posizione e dimensioni della tabella
set(t, 'Position', [25, 25, tableWidth, tableHeight]);
 
% Imposta dimensioni della finestra
set(gcf, 'Position', [100, 100, windowWidth, windowHeight]);
 
% Salva la finestra della tabella come immagine
% frame = getframe(gcf);  % Cattura la finestra attuale
frame = getframe(fig);  % Cattura la finestra attuale

imwrite(frame.cdata, 'tabella_percentChanges.jpg');  % Salva come immagine
  
% Creazione del report in PDF
import mlreportgen.report.*;
import mlreportgen.dom.*;
 
% Estrai il nome del file video senza estensione
[~, name, ~] = fileparts(videoPathFile);
 
% Crea il nome del report PDF
pdfFileName = fullfile(path, 'FMD_reports', [name '_FMD_report.pdf']);
 
% Crea il report
% report = Report('FMD_Report', 'pdf');
report = Report(pdfFileName, 'pdf');

 
% Aggiungi il titolo
add(report, TitlePage('Title', 'FMD Report', 'Author', 'Dev. by A. Gentilin at al.'));
 
% Aggiungi il sommario
add(report, TableOfContents);
 
% Aggiungi una sezione con le informazioni generali
section1 = Section('General Information');
add(section1, Paragraph(['Filename: ', name]));
add(section1, Paragraph(['Baseline1: ', num2str(baseline1), 's']));
add(section1, Paragraph(['Baseline2: ', num2str(baseline2), 's']));
add(section1, Paragraph(['Cuff Release (Baseline3): ', num2str(baseline3), 's']));
 
% Aggiungi il grafico
add(report, Section('Percentage Change Chart'));
add(report, Paragraph('Bar chart of the percentage change between time windows.'));
graficoImg = Image('grafico_percentChanges.jpg');
graficoImg.Width = '5in';  % Imposta la larghezza dell'immagine a 5 pollici
graficoImg.Height = '3in';  % Imposta l'altezza dell'immagine a 3 pollici (modifica in base alle necessità)
add(report, graficoImg);
 
% Aggiungi la tabella
add(report, Section('Percentage Change Table'));
add(report, Paragraph('Table of percentage changes between time windows.'));
tabellaImg = Image('tabella_percentChanges.jpg');
tabellaImg.Width = '5in';  % Imposta la larghezza dell'immagine a 5 pollici
tabellaImg.Height = '3in';  % Imposta l'altezza dell'immagine a 3 pollici (modifica in base alle necessità)
add(report, tabellaImg);
 
% Concludi il report
close(report);

% Crea il nome del file Excel (lo stesso nome del video)
excelFileName = fullfile(path, 'FMD_reports', [originalName '_FMDdata.xlsx']);
T = table(timeIntervalsLabels, percentChanges, 'VariableNames', {'Time_interval_(s)', 'Percentage_change'});
writetable(T, excelFileName);

allFigures = findall(0, 'Type', 'figure');
disp(allFigures);
