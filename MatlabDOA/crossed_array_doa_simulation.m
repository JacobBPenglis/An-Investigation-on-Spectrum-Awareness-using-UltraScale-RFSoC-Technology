%% crossed_array_doa_simulation.m
% Crossed two-element half-wave dipole array DoA simulation
% MATLAB R2025a + Phased Array System Toolbox
%
% Array geometry:
%
%                         Y2 (0,+d/2,0)
%                              |
%                              |
%        X1 (-d/2,0,0) --------+-------- X2 (+d/2,0,0)
%                              |
%                              |
%                         Y1 (0,-d/2,0)
%
% Each pair has d = lambda/2 spacing.
% All four half-wave dipoles are vertical (parallel to z).
%
% The source direction is controlled by:
%   SOURCE_AZ_DEG
%   SOURCE_EL_DEG
%
% MATLAB azimuth/elevation convention:
%   az = 0 deg   -> +x
%   az = 90 deg  -> +y
%   el = 0 deg   -> horizon
%   el = 90 deg  -> directly above array
%
% The two baselines estimate the x and y direction cosines:
%
%   ux = cos(el)*cos(az)
%   uy = cos(el)*sin(az)
%
% From the two measured phase differences:
%
%   ux_hat = dphi_x / (k*d)
%   uy_hat = dphi_y / (k*d)
%
% and the combined DoA estimate is:
%
%   az_hat = atan2(uy_hat, ux_hat)
%   el_hat = acos(sqrt(ux_hat^2 + uy_hat^2))
%
% IMPORTANT:
% Because every antenna lies in the x-y plane, the array cannot distinguish
% +elevation from -elevation. This script assumes the source is above the
% horizon, so elevation is constrained to 0...90 degrees.

clear;
clc;
close all;

%% =========================================================================
% USER CONTROLS
% =========================================================================

SOURCE_AZ_DEG = 173;          % Source azimuth, degrees [-180,180]
SOURCE_EL_DEG = 10;          % Source elevation, degrees [0,90]

SNR_DB = 20;                 % SNR at each antenna [dB]
NUM_SAMPLES = 4096;          % Number of received samples
FS = 10e6;                   % Complex-baseband sample rate [Hz]

BASEBAND_TONE_HZ = 250e3;    % Test tone after downconversion [Hz]
SIGNAL_AMPLITUDE = 1.0;      % Complex-baseband signal amplitude

% If true, apply the ideal half-wave-dipole elevation response.
% This changes received amplitude but does not change the phase-based DoA.
APPLY_DIPOLE_PATTERN = true;

%% =========================================================================
% RF / ARRAY PARAMETERS
% =========================================================================

fc = 1090e6;
c = physconst('LightSpeed');

lambda = c/fc;
d = lambda/2;
k = 2*pi/lambda;

dipoleLength = lambda/2;

fprintf('============================================================\n');
fprintf('CROSSED 2-ELEMENT ARRAY DOA SIMULATION\n');
fprintf('============================================================\n');
fprintf('Carrier frequency      : %.3f MHz\n',fc/1e6);
fprintf('Wavelength             : %.3f mm\n',lambda*1e3);
fprintf('Half-wave dipole length: %.3f mm\n',dipoleLength*1e3);
fprintf('Pair spacing           : %.3f mm = lambda/2\n',d*1e3);
fprintf('Source azimuth         : %.2f deg\n',SOURCE_AZ_DEG);
fprintf('Source elevation       : %.2f deg\n',SOURCE_EL_DEG);
fprintf('SNR                    : %.2f dB\n\n',SNR_DB);

%% =========================================================================
% FOUR ANTENNA POSITIONS
% =========================================================================
%
% Columns are:
%   1 = X1
%   2 = X2
%   3 = Y1
%   4 = Y2

positions = [ ...
    -d/2,  d/2,    0,    0; ...
       0,    0, -d/2,  d/2; ...
       0,    0,    0,    0  ];

elementNames = ["X1"; "X2"; "Y1"; "Y2"];

%% =========================================================================
% OPTIONAL PHASED ARRAY TOOLBOX ARRAY MODEL
% =========================================================================
%
% This object is useful if you later want to use MATLAB's pattern(),
% beamforming, MUSIC, etc. The actual received signal calculation below is
% kept explicit so the phase relationships are easy to inspect.

% Ideal thin half-wave-dipole pattern.
azElement = -180:180;
elElement = -90:90;

F = zeros(size(elElement));
valid = abs(cosd(elElement)) > 1e-12;

F(valid) = abs( ...
    cos((pi/2).*sind(elElement(valid))) ./ ...
    cosd(elElement(valid)) );

F(~valid) = 0;
F = F/max(F);

F_dB = 20*log10(max(F,1e-8));

magPattern = repmat(F_dB(:),1,numel(azElement));
phasePattern = zeros(size(magPattern));

halfWaveDipole = phased.CustomAntennaElement( ...
    'AzimuthAngles',azElement, ...
    'ElevationAngles',elElement, ...
    'MagnitudePattern',magPattern, ...
    'PhasePattern',phasePattern);

crossArray = phased.ConformalArray( ...
    'Element',halfWaveDipole, ...
    'ElementPosition',positions, ...
    'ElementNormal',zeros(2,4), ...
    'Taper',ones(1,4));

%% =========================================================================
% SOURCE SIGNAL
% =========================================================================
%
% A complex baseband tone is used here. The RF carrier is represented by
% fc when calculating the spatial phase across the antennas.

n = (0:NUM_SAMPLES-1).';
t = n/FS;

tx = SIGNAL_AMPLITUDE .* exp(1j*2*pi*BASEBAND_TONE_HZ*t);

%% =========================================================================
% SOURCE DIRECTION UNIT VECTOR
% =========================================================================

uxTrue = cosd(SOURCE_EL_DEG)*cosd(SOURCE_AZ_DEG);
uyTrue = cosd(SOURCE_EL_DEG)*sind(SOURCE_AZ_DEG);
uzTrue = sind(SOURCE_EL_DEG);

uTrue = [uxTrue; uyTrue; uzTrue];

fprintf('True direction cosines:\n');
fprintf('  ux = %+0.6f\n',uxTrue);
fprintf('  uy = %+0.6f\n',uyTrue);
fprintf('  uz = %+0.6f\n\n',uzTrue);

%% =========================================================================
% HALF-WAVE DIPOLE ELEMENT RESPONSE
% =========================================================================
%
% Since all four dipoles have the same orientation, the same element
% response multiplies all four received channels.

if APPLY_DIPOLE_PATTERN
    if abs(cosd(SOURCE_EL_DEG)) < 1e-12
        dipoleFieldGain = 0;
    else
        dipoleFieldGain = abs( ...
            cos((pi/2)*sind(SOURCE_EL_DEG)) / ...
            cosd(SOURCE_EL_DEG) );
    end
else
    dipoleFieldGain = 1;
end

fprintf('Half-wave dipole field factor at source elevation: %.6f\n\n', ...
    dipoleFieldGain);

%% =========================================================================
% SPATIAL PHASE AT EACH ANTENNA
% =========================================================================
%
% Plane-wave phase:
%
%     phi_m = k * r_m dot u
%
% This convention gives:
%
%     phi_X2 - phi_X1 = k*d*ux
%     phi_Y2 - phi_Y1 = k*d*uy

spatialPhase = k .* (positions.' * uTrue);      % 4 x 1 radians
steeringVector = exp(1j*spatialPhase);          % 4 x 1

%% =========================================================================
% RECEIVED SIGNAL AT EACH ANTENNA
% =========================================================================

rxClean = dipoleFieldGain .* tx .* steeringVector.';   % N x 4

% Add independent complex white Gaussian noise to every channel.
signalPower = mean(abs(rxClean(:)).^2);

if signalPower > 0
    noisePower = signalPower / 10^(SNR_DB/10);
else
    noisePower = 10^(-SNR_DB/10);
end

noiseSigma = sqrt(noisePower/2);

noise = noiseSigma .* ...
    (randn(NUM_SAMPLES,4) + 1j*randn(NUM_SAMPLES,4));

rx = rxClean + noise;

% Individual antenna-return variables for convenience.
rxX1 = rx(:,1);
rxX2 = rx(:,2);
rxY1 = rx(:,3);
rxY2 = rx(:,4);

%% =========================================================================
% DISPLAY TRUE PHASE AT EACH ANTENNA
% =========================================================================

phaseTable = table( ...
    elementNames, ...
    positions(1,:).', ...
    positions(2,:).', ...
    positions(3,:).', ...
    spatialPhase, ...
    rad2deg(spatialPhase), ...
    'VariableNames', ...
    {'Element','X_m','Y_m','Z_m','SpatialPhase_rad','SpatialPhase_deg'});

disp('Antenna geometry and true spatial phase:');
disp(phaseTable);

%% =========================================================================
% ESTIMATE PHASE DIFFERENCE FROM THE RECEIVED SAMPLES
% =========================================================================
%
% Cross-correlation removes the unknown/common transmitted signal phase.
%
% For x pair:
%   angle(sum(conj(X1).*X2)) = phi_X2 - phi_X1
%
% For y pair:
%   angle(sum(conj(Y1).*Y2)) = phi_Y2 - phi_Y1

R_x = sum(conj(rxX1).*rxX2);
R_y = sum(conj(rxY1).*rxY2);

dphiX = angle(R_x);
dphiY = angle(R_y);

fprintf('\nMeasured pair phase differences:\n');
fprintf('  X pair: %+9.4f deg\n',rad2deg(dphiX));
fprintf('  Y pair: %+9.4f deg\n',rad2deg(dphiY));

%% =========================================================================
% ESTIMATE DIRECTION COSINES FROM EACH TWO-ELEMENT ARRAY
% =========================================================================
%
% Since d = lambda/2:
%
%   k*d = pi
%
% Therefore each measured phase difference maps directly onto one
% direction cosine. Using lambda/2 spacing avoids spatial aliasing over
% the visible region.

uxEst = dphiX/(k*d);
uyEst = dphiY/(k*d);

% Small noise errors can push estimates slightly outside the physical
% direction-cosine interval.
uxEst = max(-1,min(1,uxEst));
uyEst = max(-1,min(1,uyEst));

fprintf('\nDirection-cosine estimates from the individual pairs:\n');
fprintf('  X pair -> ux_hat = %+0.6f\n',uxEst);
fprintf('  Y pair -> uy_hat = %+0.6f\n',uyEst);

% A useful "local" angle for each baseline:
% this is the angle away from that baseline's broadside plane.
xPairLocalAngle = asind(uxEst);
yPairLocalAngle = asind(uyEst);

fprintf('\nIndividual baseline estimates:\n');
fprintf('  X pair angle away from x-baseline broadside: %+7.3f deg\n', ...
    xPairLocalAngle);
fprintf('  Y pair angle away from y-baseline broadside: %+7.3f deg\n', ...
    yPairLocalAngle);

%% =========================================================================
% COMBINE BOTH PAIRS INTO ONE 2-D DOA ESTIMATE
% =========================================================================

horizontalDirectionMagnitude = hypot(uxEst,uyEst);

% Enforce the physically valid range.
horizontalDirectionMagnitude = min(1,horizontalDirectionMagnitude);

azEst = atan2d(uyEst,uxEst);

% This returns positive elevation only.
% A planar x-y array cannot distinguish +el from -el.
elEst = acosd(horizontalDirectionMagnitude);

fprintf('\n============================================================\n');
fprintf('COMBINED DIRECTION ESTIMATE\n');
fprintf('============================================================\n');
fprintf('True azimuth       : %8.3f deg\n',SOURCE_AZ_DEG);
fprintf('Estimated azimuth  : %8.3f deg\n',azEst);
fprintf('Azimuth error      : %+8.3f deg\n', ...
    wrapTo180Local(azEst-SOURCE_AZ_DEG));
fprintf('\n');
fprintf('True elevation      : %8.3f deg\n',SOURCE_EL_DEG);
fprintf('Estimated elevation : %8.3f deg\n',elEst);
fprintf('Elevation error     : %+8.3f deg\n',elEst-SOURCE_EL_DEG);
fprintf('============================================================\n');

%% =========================================================================
% PLOT ARRAY GEOMETRY AND SOURCE DIRECTION
% =========================================================================

figure('Name','Crossed Array Geometry and Source Direction');
hold on;
grid on;
axis equal;

% Pair baselines.
plot3(positions(1,1:2),positions(2,1:2),positions(3,1:2), ...
    '-o','LineWidth',2,'MarkerSize',8);

plot3(positions(1,3:4),positions(2,3:4),positions(3,3:4), ...
    '-s','LineWidth',2,'MarkerSize',8);

% Draw dipoles.
for m = 1:4
    x0 = positions(1,m);
    y0 = positions(2,m);
    z0 = positions(3,m);

    plot3( ...
        [x0 x0], ...
        [y0 y0], ...
        [z0-dipoleLength/2 z0+dipoleLength/2], ...
        'k-','LineWidth',2);
end

% True source direction.
arrowLength = 1.5*d;

quiver3(0,0,0, ...
    arrowLength*uxTrue, ...
    arrowLength*uyTrue, ...
    arrowLength*uzTrue, ...
    0,'LineWidth',2,'MaxHeadSize',0.4);

% Estimated source direction.
uzEst = sqrt(max(0,1-uxEst^2-uyEst^2));

quiver3(0,0,0, ...
    arrowLength*uxEst, ...
    arrowLength*uyEst, ...
    arrowLength*uzEst, ...
    0,'--','LineWidth',2,'MaxHeadSize',0.4);

xlabel('x (m)');
ylabel('y (m)');
zlabel('z (m)');
title(sprintf( ...
    'True DoA = (%.1f^\\circ, %.1f^\\circ), Estimated = (%.1f^\\circ, %.1f^\\circ)', ...
    SOURCE_AZ_DEG,SOURCE_EL_DEG,azEst,elEst));

legend( ...
    'X-axis pair', ...
    'Y-axis pair', ...
    'Dipoles', ...
    'Dipoles', ...
    'Dipoles', ...
    'Dipoles', ...
    'True direction', ...
    'Estimated direction', ...
    'Location','best');

view(35,25);

%% =========================================================================
% PLOT RECEIVED I/Q AT ALL FOUR ANTENNAS
% =========================================================================

numPlot = min(200,NUM_SAMPLES);

figure('Name','Received Signals at the Four Antennas');

tiledlayout(2,2);

for m = 1:4
    nexttile;

    plot(t(1:numPlot)*1e6,real(rx(1:numPlot,m)),'LineWidth',1);
    hold on;
    plot(t(1:numPlot)*1e6,imag(rx(1:numPlot,m)),'LineWidth',1);

    grid on;
    xlabel('Time (\mus)');
    ylabel('Amplitude');
    title(sprintf('%s return',elementNames(m)));
    legend('I','Q','Location','best');
end

%% =========================================================================
% PLOT RELATIVE PHASE OF EACH CHANNEL
% =========================================================================

% Remove the common transmitted tone phase using X1 as the reference.
relativeToX1 = angle(sum(conj(rxX1).*rx,1));

figure('Name','Measured Relative Antenna Phase');
bar(rad2deg(relativeToX1));
grid on;
xticks(1:4);
xticklabels(elementNames);
ylabel('Phase relative to X1 (degrees)');
title('Measured Relative Spatial Phase');

%% =========================================================================
% PLOT TRUE AND ESTIMATED DIRECTION IN THE HORIZONTAL DIRECTION-COSINE PLANE
% =========================================================================

figure('Name','Direction Cosine Estimate');
hold on;
grid on;
axis equal;

theta = linspace(0,2*pi,500);
plot(cos(theta),sin(theta),'k--');

plot(uxTrue,uyTrue,'o','MarkerSize',10,'LineWidth',2);
plot(uxEst,uyEst,'x','MarkerSize',12,'LineWidth',2);

plot([0 uxTrue],[0 uyTrue],'-','LineWidth',1.5);
plot([0 uxEst],[0 uyEst],'--','LineWidth',1.5);

xlabel('u_x = cos(el) cos(az)');
ylabel('u_y = cos(el) sin(az)');
title('Combining the Two Orthogonal Baselines');
legend('Physical limit','True','Estimated','True vector','Estimated vector', ...
    'Location','best');

xlim([-1.1 1.1]);
ylim([-1.1 1.1]);

%% =========================================================================
% LOCAL HELPER FUNCTION
% =========================================================================

function a = wrapTo180Local(a)
    a = mod(a + 180,360) - 180;
end
