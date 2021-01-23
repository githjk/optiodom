close all
clear
clc

%% INITIALIZATION

visualize = true;

% Dataset filenames:
% - UMBmark and Jung&Chung: only 1 dataset of square paths.
% - Ivanjko               : only 1 dataset of Ivanjko's path (straight line + 180º on-the-spot rotation).
% - Sousa et al           : any dataset.
Dataset.filenames = {
  %'../../../data/diff/square/230620202042/230620202042',
  %'../../../data/diff/square/230620202144/230620202144',
  %'../../../data/diff/square/230620202258/230620202258',
  %'../../../data/diff/square/230620202317/230620202317',
  %'../../../data/diff/square/231220200029/231220200029',
  %'../../../data/diff/square/231220200040/231220200040',
  %'../../../data/diff/square/231220200045/231220200045',
  '../../../data/diff/square/231220200048/231220200048'
};
Dataset.metadata  = '../../../data/diff/square/231220200048/231220200048_metadata.csv';
Dataset.N    = length(Dataset.filenames);
Dataset.data = cell(1,Dataset.N);

% Method parameters:
% some methods require specific parameters for their execution
Method.name       = 'jung&chung';
Method.sampleDist = [];
% Method. ...

% Robot parameters:
[RobotParam] = readRobotParametersMetadata(Dataset.metadata);
% ... you can change the robot parameters after reading them from a metadata csv file

% Agregated data
t    = {};
Odo  = {};
XOdo = {};
XGt  = {};
XErr = {};
XOdoCal = {};
XErrCal = {};
Filenames = {};

%% DATA PROCESSMENT
k = 1;
for i=1:Dataset.N
  Dataset.data{i}.parameters = readDatasetParameters(strcat(Dataset.filenames{i},'_metadata.csv'));

  for j=1:Dataset.data{i}.parameters.N
    Filenames{k} = strcat(Dataset.filenames{i},sprintf('_run-%02d.csv', j));

    [ Dataset.data{i}.parameters.Tsampling , ...
      Dataset.data{i}.numSamples{j}        , ...
      Dataset.data{i}.time{j} , ...
      Dataset.data{i}.XGt{j}  , ...
      Dataset.data{i}.Odo{j}  ] = loadData(Filenames{k},RobotParam);
    
    [Dataset.data{i}.XOdo{j},~] = simulateRobot_diff( ...
      Dataset.data{i}.XGt{j}(1,:)                   , ...
      Dataset.data{i}.Odo{j}                        , ...
      Dataset.data{i}.parameters.Tsampling          , ...
      RobotParam                                    , ...
      Method.sampleDist);
    
    Dataset.data{i}.XErr{j} = Dataset.data{i}.XGt{j} - Dataset.data{i}.XOdo{j};
    
    % Agregated data
    t{k}    = Dataset.data{i}.time{j};
    XGt{k}  = Dataset.data{i}.XGt{j};
    Odo{k}  = Dataset.data{i}.Odo{j};
    XOdo{k} = Dataset.data{i}.XOdo{j};
    XErr{k} = Dataset.data{i}.XErr{j};
    k = k+1;
  end
end

%% METHOD: JUNG&CHUNG
% - UMBmark and Jung&Chung: assumed that it the only dataset it is first CW (clockwise) and then CCW (counterclockwise).
% - Ivanjko               : any dataset of Ivanjko's path (straight line + 180º on-the-spot rotation).
% - Sousa et al           : any dataset.

% Evaluation measures
N = length(t)/2;                                 % N runs clockwise (CW) and N runs counterclockwise (CCW)
L = Dataset.data{i}.parameters.L;
XErrCw  = cellarray2cellarray(XErr,1  ,N  );
XErrCcw = cellarray2cellarray(XErr,1+N,N*2);
Method.results.uncalibrated     = computeEvaluationMeasures(XErr);
Method.results.uncalibrated.cw  = computeEvaluationMeasures(XErrCw);
Method.results.uncalibrated.ccw = computeEvaluationMeasures(XErrCcw);

% Calibration procedure
% - angles originated from systematic errors (unequal wheels diameters and wheelbase uncertainty - the method assume independent)
Method.results.alphaEb = ( Method.results.uncalibrated.cw.cgTH - Method.results.uncalibrated.ccw.cgTH ) / ( 8 );
Method.results.betaEd  = ( Method.results.uncalibrated.cw.cgTH + Method.results.uncalibrated.ccw.cgTH ) / ( 8 );
Method.results.alphaEd = pi*RobotParam.L(1)*Method.results.betaEd/(4*L);
% - curvature radius:
Method.results.R = (L/2)/sin(Method.results.betaEd/2);
% - systematic errors:
Method.results.Eb = (pi/2)/(pi/2 - (Method.results.alphaEb + Method.results.alphaEd));
Method.results.Ed = (Method.results.R + Method.results.Eb*RobotParam.L(1)/2)/(Method.results.R - Method.results.Eb*RobotParam.L(1)/2);
% - update robot parameters:
RobotEstParam = RobotParam;
RobotEstParam.L(1) = Method.results.Eb * RobotParam.L(1);
diamAvrg           = sum(RobotParam.D(1:2))/2;
RobotEstParam.D(1) = 2 * diamAvrg / (1+1/Method.results.Ed); % right wheel
RobotEstParam.D(2) = 2 * diamAvrg / (1+Method.results.Ed); % left wheel

%% SIMULATE CALIBRATED ROBOT

% Odometry data
k = 1;
for i=1:Dataset.N
  for j=1:Dataset.data{i}.parameters.N    
    [Dataset.data{i}.XOdoCal{j},~] = simulateRobot_diff( ...
      Dataset.data{i}.XGt{j}(1,:)                      , ...
      Dataset.data{i}.Odo{j}                           , ...
      Dataset.data{i}.parameters.Tsampling             , ...
      RobotEstParam                                    , ...
      Method.sampleDist);
    
    Dataset.data{i}.XErrCal{j} = Dataset.data{i}.XGt{j} - Dataset.data{i}.XOdoCal{j};
    
    % Agregated data
    XOdoCal{k} = Dataset.data{i}.XOdoCal{j};
    XErrCal{k} = Dataset.data{i}.XErrCal{j};
    k = k+1;
  end
end

% Evaluation measures
XErrCalCw  = cellarray2cellarray(XErrCal,1  ,N  );
XErrCalCcw = cellarray2cellarray(XErrCal,1+N,N*2);
Method.results.calibrated     = computeEvaluationMeasures(XErrCal);
Method.results.calibrated.cw  = computeEvaluationMeasures(XErrCalCw);
Method.results.calibrated.ccw = computeEvaluationMeasures(XErrCalCcw);


%% VISUALIZATION
main_visualizationSimplex

if (visualize)
  main_visualization
end