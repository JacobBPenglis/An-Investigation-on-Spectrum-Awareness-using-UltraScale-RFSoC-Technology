%Minimum Redundancy Linear Array (MRLA) 

%% 
N = 20;  % Number of elements
D = 0.5; % Element spacing (m)
ula = phased.ULA(N,D);
viewArray(ula,'Title','Uniform Linear Array (ULA)')
set(gca,'CameraViewAngle',4.4);

%%
N = 4;                         % Number of elements
pos = zeros(3,N);
pos(2,:) = [-1.5 -1 0.5 1.5];  % Aperture equivalent to 7-element ULA
mrla = phased.ConformalArray('ElementPosition',pos,...
                           'ElementNormal',zeros(2,N));

viewArray(mrla,'Title','Minimum Redundancy Linear Array (MRLA)')
set(gca,'CameraViewAngle',4.85);