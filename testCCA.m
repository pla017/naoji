%% 在线处理 CCA
clc;clear;close all;
% filepath = 'H:\35目标拼字-gtec\DataSave\crq_20211102';
% file = dir(filepath);
% load('C:\Users\DELL\Desktop\35目标拼字-gtec\DataSave\dxy_20211110\dxy_11101717DATA_online')
load('D:\研究生\数据\cjs_20251128\cjs_11281621DATA_online.mat')
fps = [8:0.25:16.5];
Fs = 1200;
Nfps1 = length(fps);
rmax = zeros(1,Nfps1);
len_delay=0;
nn=3;
%%
for k=1:length(fps)
    bufferData=Data_SSMVEP{k};
    SSMVEPData = bufferData(len_delay*Fs+1:round(nn*Fs),:);%
    Nsample = size(SSMVEPData,1);
    t = (0:1/Fs:(Nsample-1)/Fs)';
     SSMVEPData = detrend(SSMVEPData,'constant');
     SSMVEPData = double(SSMVEPData);
%      %% 带通滤波
% wp = [3 40]/(Fs/2);     %40,48,6,8最好-0.72       这个滤波器最好
% ws = [2 49]/(Fs/2);
% Rp = 6;
% Rs = 8;
% [n,Wn]=buttord(wp,ws,Rp,Rs);
% [n,fc] = butter(n,Wn,'bandpass');
% SSMVEPData = filtfilt(n,fc,SSMVEPData);

% wp = [3 20]/(Fs/2);
% ws = [2,22]/(Fs/2);
% Rp = 3;
% Rs = 6;
% [n,Wn]=buttord(wp,ws,Rp,Rs);
% [n,fc] = butter(n,Wn,'bandpass');
% SSMVEPData = filtfilt(n,fc,SSMVEPData);

% %     巴特沃斯滤波器滤除3Hz以下低频噪声
%     fp=[2*3/Fs];                                                            %通带截止频率a=0.01-0.7293, a=0.2-0.7252，a=0.1-0.7279
%     fs=[2*2/Fs];                                                            %阻带截止频率
%     wp=6;                                                                   %通带纹波 6-0.6769,//0.6830,0.6837
%     ws=12;                                                                 %阻带纹波
%     [n,fc]=buttord(fp,fs,wp,ws);
%     [num ,den]=butter(n,fc,'high');                                              
%     SSMVEPData=filter(num,den,SSMVEPData);  

% fmin=3;
% fmax=40;
% [b,a] = butter(3, [fmin fmax]/(Fs/2), 'bandpass');
% SSMVEPData = filter(b,a,SSMVEPData);

%      SSMVEPDataCCA=SSMVEPDataCCA';
%     vep1=zeros(20,length(SSMVEPData));
%     for j=1:20
%         vep1(j,:)=FHN(A,alpha,h,SSMVEPData);                                                                 %FHN随机共振处理
%     end
%     sig1=mean(vep1);
%     sig1=sig1';

    %     if  numel(find(isnan(sig1)))>=1
    %         target(1,:) =0;
    %         return
    %     end
    for kf = 1:Nfps1
        rad0 = pi*fps(kf)*t*2;
        radd=[rad0];%,rad0*2,rad0*4
        coskf = cos(radd);
        sinkf = sin(radd);
        [~, ~, r1] = canoncorr(SSMVEPData,[coskf,sinkf]);
        rmax(kf) = r1(1);
    end
     subplot(5,7,k)
    plot(fps,rmax,'LineWidth',1.2);
    fii_str = fps(k);
    title(['{\itf }=',num2str(fii_str),'Hz'],'Fontname','Times new roman','fontsize',8);
    xlim([8 20])

[Rmax ind] = sort(rmax,'descend');
p = Rmax(1)/Rmax(2);
target(1,k) = ind(1);
end
result(1,:)=1:35;
acc = length(find((target-result)==0))/35;

