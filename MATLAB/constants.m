
clear;
clc;
%% Simulation time
t_total = 20e-03;%5e-03;%

waveFreq = 2000; %Hz

led_rate = t_total/16; %0.5;

%%
% FPGA  clock
FPGAClockMHz = 20;
FPGAClock = FPGAClockMHz*(10^6);

% Software Dimension
SoftwareDataDim = 512;

% Data width for DMA
AXIStreamDataWidth = 64; %bits per beat

% DMA / buffering
NumFrameBuffers = 4;%8;

% DMA Burst length
BurstLength = 64;%256; %beats per burst

% DMA Clock Freq (MHz)
DMAClockFreq = 100;

FIFODepth = 8;%16;%8;
FIFOAlmostFull = floor(0.8 * FIFODepth);

%% Derived
FPGATime = 1/FPGAClock;
