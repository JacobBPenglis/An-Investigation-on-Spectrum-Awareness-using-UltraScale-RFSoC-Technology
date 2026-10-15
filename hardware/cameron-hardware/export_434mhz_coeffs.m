% Design a 128 MSPS -> 1 MSPS multistage FIR decimator (72 dB target).
% Run this script in MATLAB with DSP System Toolbox installed.
% Files are saved in ./coeffs relative to MATLAB's current folder.

C = designMultistageDecimator(128, 128e6, 200e3, 72, ...
    'MinTotalCoeffs', true, 'CostMethod', 'design');

outputFolder = fullfile(pwd, 'coeffs');
if ~isfolder(outputFolder)
    mkdir(outputFolder);
end

for stageNumber = 1:getNumStages(C)
    stage = C.(sprintf('Stage%d', stageNumber));
    coefficients = stage.Numerator(:);
    fileName = fullfile(outputFolder, ...
        sprintf('434mhz_stage%d.coe', stageNumber));

    writeCoeFile(fileName, coefficients);
    fprintf('Saved %s (%d taps, decimation by %d)\n', ...
        fileName, numel(coefficients), stage.DecimationFactor);
end

function writeCoeFile(fileName, coefficients)
    [fileID, errorMessage] = fopen(fileName, 'w');
    if fileID == -1
        error('CoefficientExport:FileOpen', ...
            'Cannot open %s: %s', fileName, errorMessage);
    end
    closeFile = onCleanup(@() fclose(fileID));

    fprintf(fileID, 'radix=10;\ncoefdata=\n');
    fprintf(fileID, '%.17g,\n', coefficients(1:end-1));
    fprintf(fileID, '%.17g;\n', coefficients(end));
end
