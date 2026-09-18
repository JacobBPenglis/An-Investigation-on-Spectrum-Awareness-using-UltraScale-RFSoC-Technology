%% crossed_two_element_dipole_arrays.m
% Two orthogonal 2-element phased arrays made from ideal half-wave dipoles
% MATLAB R2025a + Phased Array System Toolbox
%
% Geometry:
%
%                    Y-array element 2
%                          (0,+d/2)
%                              |
%                              |
% X-array element 1 -----------+----------- X-array element 2
%       (-d/2,0)                           (+d/2,0)
%                              |
%                              |
%                    Y-array element 1
%                          (0,-d/2)
%
% Each subarray has two elements separated by d = lambda/2.
% All dipoles are vertically oriented (parallel to the z-axis).
% The script plots:
%   1. Cross-array geometry
%   2. 3-D directivity of the X-axis two-element array
%   3. 3-D directivity of the Y-axis two-element array
%   4. An overlaid azimuth cut of both arrays at elevation = 0 deg
%
% IMPORTANT:
% phased.ShortDipoleAntennaElement models a SHORT dipole rather than an
% exact half-wave dipole. Therefore, this script uses an analytical
% half-wave-dipole element pattern in phased.CustomAntennaElement.

clear;
clc;
close all;

%% ------------------------------------------------------------------------
% 1. Operating frequency and physical dimensions
% -------------------------------------------------------------------------

fc = 1090e6;                         % ADS-B centre frequency [Hz]
c  = physconst('LightSpeed');        % Speed of light [m/s]
lambda = c / fc;                     % Wavelength [m]

dipoleLength = lambda / 2;           % Ideal half-wave dipole length [m]
d = lambda / 2;                      % Element spacing within each 2-el array

fprintf('Centre frequency       : %.3f MHz\n', fc/1e6);
fprintf('Wavelength             : %.3f mm\n', lambda*1e3);
fprintf('Half-wave dipole length: %.3f mm\n', dipoleLength*1e3);
fprintf('Element spacing        : %.3f mm (lambda/2)\n\n', d*1e3);

%% ------------------------------------------------------------------------
% 2. Create an ideal z-directed half-wave dipole element
% -------------------------------------------------------------------------
%
% For a thin, centre-fed half-wave dipole aligned with z:
%
%       F(theta) = cos((pi/2) cos(theta)) / sin(theta)
%
% where theta is measured down from +z.
%
% MATLAB's azimuth/elevation convention uses:
%
%       theta = 90 deg - elevation
%
% so:
%
%       F(el) = cos((pi/2) sin(el)) / cos(el)
%
% The ideal pattern is independent of azimuth.

azElement = -180:1:180;
elElement =  -90:1:90;

F = zeros(size(elElement));

% Avoid the removable 0/0 singularity at +/-90 degrees.
valid = abs(cosd(elElement)) > 1e-12;
F(valid) = abs( ...
    cos((pi/2) .* sind(elElement(valid))) ./ ...
    cosd(elElement(valid)) );

% At +/-90 deg, an ideal z-directed dipole has a null.
F(~valid) = 0;

% Numerical protection before conversion to dB.
F = F ./ max(F);
F_dB = 20*log10(max(F,1e-8));

% Replicate the elevation-dependent pattern over all azimuth angles.
magPattern = repmat(F_dB(:), 1, numel(azElement));
phasePattern = zeros(size(magPattern));

halfWaveDipole = phased.CustomAntennaElement( ...
    'AzimuthAngles',   azElement, ...
    'ElevationAngles', elElement, ...
    'MagnitudePattern', magPattern, ...
    'PhasePattern',     phasePattern);

%% ------------------------------------------------------------------------
% 3. Define the two perpendicular 2-element arrays
% -------------------------------------------------------------------------
%
% X-array:
%   elements lie along x at x = +/-d/2
%
% Y-array:
%   elements lie along y at y = +/-d/2
%
% Both arrays are centred at the origin and use equal in-phase weights.

posX = [ -d/2,  d/2; ...
           0,      0; ...
           0,      0  ];

posY = [    0,      0; ...
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

%% ------------------------------------------------------------------------
% 4. Plot the physical cross geometry
% -------------------------------------------------------------------------

figure('Name','Crossed Two-Element Array Geometry');
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
        [z0-dipoleLength/2 z0+dipoleLength/2], ...
        'k-','LineWidth',2,'HandleVisibility','off');
end

xlabel('x (m)');
ylabel('y (m)');
zlabel('z (m)');
title('Two Orthogonal 2-Element Arrays of Half-Wave Dipoles');
legend('Location','best');
view(35,25);

%% ------------------------------------------------------------------------
% 5. Plot the 3-D pattern of the X-axis array
% -------------------------------------------------------------------------

az3D = -180:2:180;
el3D =  -90:2:90;

figure('Name','X-axis 2-Element Array Pattern');
pattern(arrayX,fc,az3D,el3D, ...
    'PropagationSpeed',c, ...
    'CoordinateSystem','polar', ...
    'Type','directivity');
title('X-axis 2-Element Array - Directivity');

%% ------------------------------------------------------------------------
% 6. Plot the 3-D pattern of the Y-axis array
% -------------------------------------------------------------------------

figure('Name','Y-axis 2-Element Array Pattern');
pattern(arrayY,fc,az3D,el3D, ...
    'PropagationSpeed',c, ...
    'CoordinateSystem','polar', ...
    'Type','directivity');
title('Y-axis 2-Element Array - Directivity');

%% ------------------------------------------------------------------------
% 7. Compare both azimuth patterns on one plot
% -------------------------------------------------------------------------
%
% Elevation = 0 deg gives a horizontal-plane cut.
% Because the dipoles are vertical, this is also where an ideal half-wave
% dipole has maximum element response.

azCut = -180:0.25:180;
elCut = 0;

patX = pattern(arrayX,fc,azCut,elCut, ...
    'PropagationSpeed',c, ...
    'Type','directivity');

patY = pattern(arrayY,fc,azCut,elCut, ...
    'PropagationSpeed',c, ...
    'Type','directivity');

% Normalize each pattern to its own maximum so the shapes can be compared.
patX_norm = patX - max(patX(:));
patY_norm = patY - max(patY(:));

figure('Name','Azimuth Pattern Comparison');
plot(azCut,patX_norm,'LineWidth',1.7);
hold on;
plot(azCut,patY_norm,'LineWidth',1.7);
grid on;

xlabel('Azimuth (degrees)');
ylabel('Normalized directivity (dB)');
title('Horizontal-Plane Patterns of the Two Orthogonal 2-Element Arrays');
legend('X-axis array','Y-axis array','Location','best');
xlim([-180 180]);
ylim([-40 1]);

%% ------------------------------------------------------------------------
% 8. Optional polar comparison
% -------------------------------------------------------------------------
%
% polarplot expects a non-negative radius, so convert the normalized
% directivity in dB to a normalized linear field magnitude.

patX_linear = 10.^(patX_norm/20);
patY_linear = 10.^(patY_norm/20);

figure('Name','Polar Azimuth Pattern Comparison');
pax = polaraxes;
hold(pax,'on');

polarplot(pax,deg2rad(azCut),patX_linear,'LineWidth',1.7);
polarplot(pax,deg2rad(azCut),patY_linear,'LineWidth',1.7);

pax.ThetaZeroLocation = 'right';
pax.ThetaDir = 'counterclockwise';
rlim(pax,[0 1]);

title(pax,'Normalized Azimuth Patterns at Elevation = 0 deg');
legend(pax,'X-axis array','Y-axis array','Location','bestoutside');

%% ------------------------------------------------------------------------
% 9. Print expected broadside directions
% -------------------------------------------------------------------------

fprintf('Expected horizontal-plane behaviour for in-phase lambda/2 pairs:\n');
fprintf('  X-axis array: broadside near azimuth +/-90 deg\n');
fprintf('  Y-axis array: broadside near azimuth 0 and 180 deg\n');
fprintf('\nThe two subarrays therefore provide perpendicular angular sensitivity.\n');
