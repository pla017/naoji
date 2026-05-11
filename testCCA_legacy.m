clc;clear;close all;
load('/Users/jack/Documents/MATLAB/ts-35-fbcca_10311619DATA_online.mat')
data_index = 2;

fps = [8:0.25:16.5];
Fs = 1200;
Nfps1 = length(fps);
rmax = zeros(1,Nfps1);
len_delay=0;
nn=3;

bufferData=Data_SSMVEP{data_index};
SSMVEPData = bufferData(len_delay*Fs+1:round(nn*Fs),:);
Nsample = size(SSMVEPData,1);
t = (0:1/Fs:(Nsample-1)/Fs)';
SSMVEPData = detrend(SSMVEPData,'constant');
SSMVEPData = double(SSMVEPData);

for kf = 1:Nfps1
    rad0 = pi*fps(kf)*t*2;
    radd=[rad0];
    coskf = cos(radd);
    sinkf = sin(radd);
    [~, ~, r1] = canoncorr(SSMVEPData,[coskf,sinkf]);
    rmax(kf) = r1(1);
end

[Rmax, ind] = sort(rmax,'descend');
p = Rmax(1)/Rmax(2);
recognized_freq_index = ind(1);
recognized_freq = fps(recognized_freq_index);

fprintf('Ê¶±ðÆµÂÊ: %.2f Hz\n', recognized_freq);

