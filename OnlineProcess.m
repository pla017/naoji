%% 在线处理 CCA
function [target]= OnlineProcess(StimFs,Daq,bufferData)

fps = StimFs;
Fs = Daq.Fs;
%%
SSMVEPData = bufferData(:,:);
Nsample = size(SSMVEPData,1);
SSMVEPData = detrend(SSMVEPData,'constant');
SSMVEPData = double(SSMVEPData);
% %% 带通滤波
% wp = [3 20]/500;
% ws = [2,22]/500;
% Rp = 3;
% Rs = 6;
% [n,Wn]=buttord(wp,ws,Rp,Rs);
% [n,fc] = butter(n,Wn,'bandpass');
% SSMVEPData = filtfilt(n,fc,SSMVEPData);
% SSMVEPData=SSMVEPData';
%%
t = (0:1/Fs:(Nsample-1)/Fs)';
Nfps1 = length(fps);
disp('//////////////////cca//////////////////////////////////////');
rmax = zeros(1,Nfps1);
for kf = 1:Nfps1
    rad0 = pi*fps(kf)*t*2;
    radd=[rad0,rad0*2,rad0*4];
    coskf = cos(radd);
    sinkf = sin(radd);
    [~, ~, r1] = canoncorr(SSMVEPData,[coskf,sinkf]);
    rmax(kf) = r1(1);
end

[Rmax ind] = sort(rmax,'descend');
p = Rmax(1)/Rmax(2);
target = ind(1);


end