clear;
clc;

Fs_start = 2560e6; 
Fs_end = 10e6;
M = Fs_start/Fs_end; %Decimation factor

f_signal = 1e6;

BW = 2e6; %Single sided bandwidth
Fc=Fs_start/(2*M); % New nyquist frequency after decimation
TW = Fc-BW; %transition width


Astop = 74;



%multistage
cOptimal = designMultistageDecimator(M,Fs_start,2*TW,Astop,'CostMethod','design',...
    NumStages="auto",MinTotalCoeffs=true)

cost(cOptimal)

%% compare
filterAnalyzer(cOptimal,FilterNames=["Multistage"]);

cOptimal.getNumStages
cOptimal.order %2490
cOptimal.Stage



%% Fix fig
fig = openfig("filterresponse.fig");

Fs_start = 2560e6;

ax = findall(fig, "Type", "axes");

% Find the top axes by vertical position
positions = arrayfun(@(a) a.Position(2), ax);
[~, topIdx] = max(positions);

topAx = ax(topIdx);

% Delete all other axes
delete(ax(setdiff(1:numel(ax), topIdx))); 

% Resize the top plot to fill the figure
topAx.Position = [0.13 0.15 0.78 0.75];

% Convert x-data from normalised frequency to MHz
scaleFactor = (Fs_start/2)/1e6;

plotObjects = findall(topAx, "Type", "line");

for k = 1:numel(plotObjects)
    plotObjects(k).XData = plotObjects(k).XData * scaleFactor;
end

xlim(topAx, [0 Fs_start/2/1e6]);
title('Magnitude response of Decimation Filter');
xlabel(topAx, "Frequency (MHz)");

hold(topAx, "on");

% Add vertical and horizontal lines using actual MHz values
xline(topAx, 2, "--", "LineWidth", 0.8, "Color", "red");   % 2 MHz passband edge
xline(topAx, 8, "--", "LineWidth", 0.8, "Color", "red");   % 8 MHz stopband edge

yline(topAx, -74, "--", "LineWidth", 0.8, "Color", "red"); % -74 dB stopband attenuation
text(topAx, 200, -70, "A_s = -74 dB", ...
    "Color", "red", ...
    "FontSize", 16, ...
    "HorizontalAlignment", "left", ...
    "VerticalAlignment", "bottom");

% Create zoomed inset axes
%insetAx = axes("Position", [0.52 0.52 0.32 0.32]);
insetAx = axes("Position", [0.47 0.45 0.4 0.37]);

% Copy main plot contents into inset
copyobj(topAx.Children, insetAx);

% Zoom inset to 0–16 MHz
xlim(insetAx, [0 16]);
ylim(insetAx, [-100 5]);   % adjust if needed

grid(insetAx, "on");
box(insetAx, "on");

hold(insetAx, "on");

% Add reference lines to inset using MHz
xline(insetAx, 2, "--", "LineWidth", 0.8, "Color", "red");
xline(insetAx, 8, "--", "LineWidth", 0.8, "Color", "red");
yline(insetAx, -74, "--", "LineWidth", 0.8, "Color", "red");

text(insetAx, 2 + 0.3, -30, "F_s = 2 MHz", ...
    "Color", "red", ...
    "FontSize", 12, ...
    "HorizontalAlignment", "left", ...
    "VerticalAlignment", "middle");

text(insetAx, 8 + 0.3, -30, "F_s = 8 MHz", ...
    "Color", "red", ...
    "FontSize", 12, ...
    "HorizontalAlignment", "left", ...
    "VerticalAlignment", "middle");

title(insetAx, "Filter reponse near cutoff");
xlabel(insetAx, "Frequency (MHz)");
ylabel(insetAx, "Magnitude (dB)");

%%