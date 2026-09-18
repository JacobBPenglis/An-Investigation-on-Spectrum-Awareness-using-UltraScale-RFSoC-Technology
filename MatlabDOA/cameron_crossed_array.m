clear;
clc;

fc = 1090e6;                         % ADS-B centre frequency [Hz]
c  = physconst('LightSpeed');        % Speed of light [m/s]
lambda = c / fc;                     % Wavelength [m]

dipoleLength = lambda / 2;           % Ideal half-wave dipole length [m]
d = lambda / 2;

% Create z-directed half-wave dipole element
%  F(theta) = cos((pi/2) cos(theta)) / sin(theta)
% theta = 90 deg - elevation
% F(el) = cos((pi/2) sin(el)) / cos(el)

azElement = -180:1:180;
elElement =  -90:1:90;

F = zeros(size(elElement));

% Avoid the 0/0 singularity at +/-90 degrees.
valid = abs(cosd(elElement)) > 1e-12;
F(~valid) = 0;
F(valid) = abs(cos((pi/2) .* sind(elElement(valid))) ./ cosd(elElement(valid)) );

% Convert to dB
F = F ./ max(F);
F_dB = 20*log10(max(F,1e-8));

% Replicate the elevation-dependent pattern over all azimuth angles.
magPattern = repmat(F_dB(:), 1, numel(azElement));
phasePattern = zeros(size(magPattern));

% Create element
halfWaveDipole = phased.CustomAntennaElement( ...
    'AzimuthAngles',   azElement, ...
    'ElevationAngles', elElement, ...
    'MagnitudePattern', magPattern, ...
    'PhasePattern',     phasePattern);


% Create the two perpendiculat 2-element arrays

posX = [ -d/2,  d/2; ... %positions for x array
           0,      0; ...
           0,      0  ];

posY = [    0,      0; ...%positions for y array
         -d/2,   d/2; ...
            0,      0  ];

halfWaveDipoleX = clone(halfWaveDipole);
halfWaveDipoleY = clone(halfWaveDipole);

arrayX = phased.ConformalArray( ...
    'Element',         halfWaveDipoleX, ...
    'ElementPosition', posX, ...
    'ElementNormal',   [0;0], ...
    'Taper',           [1 1]);

arrayY = phased.ConformalArray( ...
    'Element',         halfWaveDipoleY, ...
    'ElementPosition', posY, ...
    'ElementNormal',   [0;0], ...
    'Taper',           [1 1]);

%% Plot the physical layout
figure('Name','Physical layout of crossed arrays');
hold on;
grid on;
axis equal;

% Plot the two baselines.
plot3(posX(1,:),posX(2,:),posX(3,:),'-o', ...
    'LineWidth',2,'MarkerSize',8,'DisplayName','X-axis array');

plot3(posY(1,:),posY(2,:),posY(3,:),'-s', ...
    'LineWidth',2,'MarkerSize',8,'DisplayName','Y-axis array');

% Draw each vertical half-wave dipole as a z-directed line segment.
allPos = [posX posY];
for k = 1:size(allPos,2)
    x0 = allPos(1,k);
    y0 = allPos(2,k);
    z0 = allPos(3,k);

    plot3([x0 x0],[y0 y0], ...
        [z0-d/2 z0+d/2], ...
        'k-','LineWidth',2,'HandleVisibility','off');
end

xlabel('x (m)');
ylabel('y (m)');
zlabel('z (m)');
title('Physical layout of crossed arrays');
legend('Location','best');
view(35,25);

%% Polar plot of actual directivity

azCut = -180:0.25:180;
elCut = 0;

patX = pattern(arrayX,fc,azCut,elCut, ...
    'PropagationSpeed',c, ...
    'Type','directivity');

patY = pattern(arrayY,fc,azCut,elCut, ...
    'PropagationSpeed',c, ...
    'Type','directivity');

% Convert directivity from dBi to linear
DX = 10.^(patX/10);
DY = 10.^(patY/10);

% Convert azimuth to radians
theta = deg2rad(azCut);

figure;

polarplot(theta, DX, 'LineWidth', 1.5);
hold on;
polarplot(theta, DY, 'LineWidth', 1.5);

title('Array Directivity at Elevation = 0°');
legend('X-axis array','Y-axis array', ...
       'Location','best');