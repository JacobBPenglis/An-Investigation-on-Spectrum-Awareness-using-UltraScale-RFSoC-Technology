%% two_element_x_array_doa.m
% Simple 2-element X-axis DoA simulation
% MATLAB R2025a
%
% Two antennas are separated by lambda/2 along the x-axis:
%
%       Antenna 1 ---------------- Antenna 2
%          x=-d/2                      x=+d/2
%
% Source direction:
%   azimuth   = 35 deg
%   elevation = 20 deg
%
% IMPORTANT:
% A single 2-element X-axis array cannot uniquely estimate both azimuth
% and elevation. It measures only the x-direction cosine:
%
%       ux = cos(el) * cos(az)
%
% In this example, elevation is assumed known so that azimuth magnitude
% can be estimated. The array cannot distinguish +az from -az.

clear;
clc;
close all;

%% ------------------------------------------------------------------------
% User settings
% -------------------------------------------------------------------------

fc = 1090e6;             % RF carrier frequency [Hz]

SOURCE_AZ_DEG = 35;      % True source azimuth [deg]
SOURCE_EL_DEG = 20;      % True source elevation [deg]

SNR_DB = 20;             % SNR per antenna [dB]

FS = 10e6;               % Complex-baseband sample rate [Hz]
TONE_HZ = 250e3;         % Baseband test tone [Hz]
N = 4096;                % Number of samples

%% ------------------------------------------------------------------------
% Array geometry
% -------------------------------------------------------------------------

c = physconst('LightSpeed');

lambda = c/fc;
d = lambda/2;
k = 2*pi/lambda;

% Antenna positions along x-axis
x1 = -d/2;
x2 = +d/2;

fprintf('Carrier frequency : %.1f MHz\n',fc/1e6);
fprintf('Wavelength        : %.3f mm\n',lambda*1e3);
fprintf('Element spacing   : %.3f mm\n\n',d*1e3);

%% ------------------------------------------------------------------------
% Generate complex baseband signal
% -------------------------------------------------------------------------

n = (0:N-1).';
t = n/FS;

s = exp(1j*2*pi*TONE_HZ*t);

%% ------------------------------------------------------------------------
% Calculate the spatial phase at each antenna
% -------------------------------------------------------------------------
%
% For an incoming direction:
%
%   ux = cos(el) * cos(az)
%
% The spatial phase at position x is:
%
%   phi = k*x*ux

uxTrue = cosd(SOURCE_EL_DEG) * cosd(SOURCE_AZ_DEG);

phi1 = k*x1*uxTrue;
phi2 = k*x2*uxTrue;

fprintf('True source direction:\n');
fprintf('  Azimuth   = %.2f deg\n',SOURCE_AZ_DEG);
fprintf('  Elevation = %.2f deg\n',SOURCE_EL_DEG);
fprintf('  ux        = %.6f\n\n',uxTrue);

fprintf('True spatial phases:\n');
fprintf('  Antenna 1 = %+8.3f deg\n',rad2deg(phi1));
fprintf('  Antenna 2 = %+8.3f deg\n',rad2deg(phi2));
fprintf('  Difference = %+8.3f deg\n\n',rad2deg(phi2-phi1));

%% ------------------------------------------------------------------------
% Signal received at each antenna
% -------------------------------------------------------------------------

rx1_clean = s .* exp(1j*phi1);
rx2_clean = s .* exp(1j*phi2);

%% ------------------------------------------------------------------------
% Add independent complex Gaussian noise
% -------------------------------------------------------------------------

signalPower = mean(abs(s).^2);
noisePower = signalPower / 10^(SNR_DB/10);

noiseSigma = sqrt(noisePower/2);

rx1 = rx1_clean + noiseSigma*(randn(N,1) + 1j*randn(N,1));
rx2 = rx2_clean + noiseSigma*(randn(N,1) + 1j*randn(N,1));

%% ------------------------------------------------------------------------
% Estimate phase difference between antennas
% -------------------------------------------------------------------------
%
% conj(rx1).*rx2 removes the common signal phase:
%
%   conj(rx1)*rx2 ~ exp(j*(phi2 - phi1))
%
% Summing over many samples improves the estimate in noise.

R = sum(conj(rx1).*rx2);

dphiEst = angle(R);

fprintf('Estimated phase difference:\n');
fprintf('  dphi = %+8.3f deg\n\n',rad2deg(dphiEst));

%% ------------------------------------------------------------------------
% Convert phase difference into x-direction cosine
% -------------------------------------------------------------------------
%
%   dphi = k*d*ux
%
% therefore:
%
%   ux = dphi/(k*d)
%
% Since d = lambda/2:
%
%   k*d = pi

uxEst = dphiEst/(k*d);

% Protect against small noise errors
uxEst = max(-1,min(1,uxEst));

fprintf('Estimated x-direction cosine:\n');
fprintf('  ux_hat = %.6f\n\n',uxEst);

%% ------------------------------------------------------------------------
% Estimate azimuth IF elevation is known
% -------------------------------------------------------------------------
%
%   ux = cos(el)*cos(az)
%
% therefore:
%
%   cos(az) = ux / cos(el)
%
%   az = acos( ux / cos(el) )
%
% This only gives |az|. A single x-axis pair cannot distinguish
% +35 deg from -35 deg.

cosAzEst = uxEst / cosd(SOURCE_EL_DEG);

cosAzEst = max(-1,min(1,cosAzEst));

azMagnitudeEst = acosd(cosAzEst);

fprintf('Azimuth estimate assuming elevation is known:\n');
fprintf('  True azimuth magnitude      = %.3f deg\n',abs(SOURCE_AZ_DEG));
fprintf('  Estimated azimuth magnitude = %.3f deg\n',azMagnitudeEst);
fprintf('  Error                       = %.3f deg\n\n', ...
    azMagnitudeEst - abs(SOURCE_AZ_DEG));

fprintf('Ambiguous possible azimuths:\n');
fprintf('  +%.3f deg or -%.3f deg\n\n',azMagnitudeEst,azMagnitudeEst);

%% ------------------------------------------------------------------------
% Plot the received I/Q signals
% -------------------------------------------------------------------------

numPlot = 150;

figure('Name','Received Signals');

subplot(2,1,1);
plot(t(1:numPlot)*1e6,real(rx1(1:numPlot)));
hold on;
plot(t(1:numPlot)*1e6,imag(rx1(1:numPlot)));
grid on;
xlabel('Time (\mus)');
ylabel('Amplitude');
title('Antenna 1');
legend('I','Q');

subplot(2,1,2);
plot(t(1:numPlot)*1e6,real(rx2(1:numPlot)));
hold on;
plot(t(1:numPlot)*1e6,imag(rx2(1:numPlot)));
grid on;
xlabel('Time (\mus)');
ylabel('Amplitude');
title('Antenna 2');
legend('I','Q');

%% ------------------------------------------------------------------------
% Plot the simple geometry
% -------------------------------------------------------------------------

figure('Name','Two Element X-axis Array');
hold on;
grid on;
axis equal;

plot([x1 x2],[0 0],'-o','LineWidth',2,'MarkerSize',8);

% True source direction projected into x-y plane
arrowLength = d;

uxPlot = cosd(SOURCE_EL_DEG)*cosd(SOURCE_AZ_DEG);
uyPlot = cosd(SOURCE_EL_DEG)*sind(SOURCE_AZ_DEG);

quiver(0,0,arrowLength*uxPlot,arrowLength*uyPlot,0, ...
    'LineWidth',2,'MaxHeadSize',0.5);

xlabel('x (m)');
ylabel('y (m)');
title(sprintf('2-Element X-axis Array, Source az = %.1f^\\circ, el = %.1f^\\circ', ...
    SOURCE_AZ_DEG,SOURCE_EL_DEG));

legend('Antenna baseline','True horizontal direction','Location','best');
