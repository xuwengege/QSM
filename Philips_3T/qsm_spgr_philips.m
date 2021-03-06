function qsm_spgr_philips(path_dicom, path_out, options)
%QSM_SPGR_PHILIPS Quantitative susceptibility mapping from SPGR sequence at philips.
%   QSM_SPGR_PHILIPS(PATH_DICOM, PATH_OUT, OPTIONS) reconstructs susceptibility maps.
%
%   Re-define the following default settings if necessary
%
%   PATH_DICOM   - directory for input GE dicoms
%   PATH_OUT     - directory to save nifti and/or matrixes   : QSM_SPGR_PHILIPS
%   OPTIONS      - parameter structure including fields below
%    .readout    - multi-echo 'unipolar' or 'bipolar'        : 'unipolar'
%    .r_mask     - whether to enable the extra masking       : 1
%    .fit_thr    - extra filtering based on the fit residual : 20
%    .bet_thr    - threshold for BET brain mask              : 0.4
%    .bet_smooth - smoothness of BET brain mask at edges     : 2
%    .ph_unwrap  - 'prelude' or 'bestpath'                   : 'bestpath'
%    .bkg_rm     - background field removal method(s)        : 'resharp'
%                  options: 'pdf','sharp','resharp','esharp','lbv'
%                  to try all e.g.: {'pdf','sharp','resharp','esharp','lbv'}
%    .t_svd      - truncation of SVD for SHARP               : 0.1
%    .smv_rad    - radius (mm) of SMV convolution kernel     : 3
%    .tik_reg    - Tikhonov regularization for resharp       : 1e-4
%    .cgs_num    - max interation number for RESHARP         : 200
%    .lbv_peel   - LBV layers to be peeled off               : 2
%    .lbv_tol    - LBV interation error tolerance            : 0.01
%    .tv_reg     - Total variation regularization parameter  : 5e-4
%    .tvdi_n     - iteration number of TVDI (nlcg)           : 500
%    .interp     - interpolate the image to the double size  : 0


% AUTHOR: Hongfu Sun
% EMAIL: sunhongfu@gmail.com
% PAPER TO REFERENCE: Sun H, Wilman AH. Background field removal using spherical mean value
% filtering and Tikhonov regularization. Magn Reson Med. 2014 Mar;71(3):1151-7.
% doi: 10.1002/mrm.24765. PubMed PMID: 23666788.


if ~ exist('path_dicom','var') || isempty(path_dicom)
    error('Please input the directory of DICOMs')
end

if ~ exist('path_out','var') || isempty(path_out)
    path_out = pwd;
    disp('Current directory for output')
end

if ~ exist('options','var') || isempty(options)
    options = [];
end

if ~ isfield(options,'readout')
    options.readout = 'unipolar';
end

if ~ isfield(options,'r_mask')
    options.r_mask = 1;
end

if ~ isfield(options,'fit_thr')
    options.fit_thr = 20;
end

if ~ isfield(options,'bet_thr')
    options.bet_thr = 0.4;
end

if ~ isfield(options,'bet_smooth')
    options.bet_smooth = 2;
end

if ~ isfield(options,'ph_unwrap')
    options.ph_unwrap = 'bestpath';
end

if ~ isfield(options,'bkg_rm')
    options.bkg_rm = 'resharp';
    % options.bkg_rm = {'pdf','sharp','resharp','esharp','lbv'};
end

if ~ isfield(options,'t_svd')
    options.t_svd = 0.1;
end

if ~ isfield(options,'smv_rad')
    options.smv_rad = 3;
end

if ~ isfield(options,'tik_reg')
    options.tik_reg = 1e-4;
end

if ~ isfield(options,'cgs_num')
    options.cgs_num = 200;
end

if ~ isfield(options,'lbv_tol')
    options.lbv_tol = 0.01;
end

if ~ isfield(options,'lbv_peel')
    options.lbv_peel = 2;
end

if ~ isfield(options,'tv_reg')
    options.tv_reg = 5e-4;
end

if ~ isfield(options,'inv_num')
    options.inv_num = 500;
end

if ~ isfield(options,'interp')
    options.interp = 0;
end

readout    = options.readout;
r_mask     = options.r_mask;
fit_thr    = options.fit_thr;
bet_thr    = options.bet_thr;
bet_smooth = options.bet_smooth;
ph_unwrap  = options.ph_unwrap;
bkg_rm     = options.bkg_rm;
t_svd      = options.t_svd;
smv_rad    = options.smv_rad;
tik_reg    = options.tik_reg;
cgs_num    = options.cgs_num;
lbv_tol    = options.lbv_tol;
lbv_peel   = options.lbv_peel;
tv_reg     = options.tv_reg;
inv_num    = options.inv_num;
interp     = options.interp;

% read in MESPGR dicoms (multi-echo gradient-echo)
path_dicom = cd(cd(path_dicom));
list_dicom = dir(path_dicom);
list_dicom = list_dicom(~strncmpi('.', {list_dicom.name}, 1));


dicom_info = dicominfo([path_dicom,filesep,list_dicom(1).name]);

imsize = single([dicom_info.Width, dicom_info.Height, ...
            length(list_dicom)/dicom_info.EchoTrainLength/2, ...
                dicom_info.EchoTrainLength]);

% the slice thickness seems to be wrong in the dicom header!
% vox = [dicom_info.PixelSpacing(1), dicom_info.PixelSpacing(2), dicom_info.SliceThickness];

% angles!!!
Xz = dicom_info.ImageOrientationPatient(3);
Yz = dicom_info.ImageOrientationPatient(6);
%Zz = sqrt(1 - Xz^2 - Yz^2);
Zxyz = cross(dicom_info.ImageOrientationPatient(1:3),dicom_info.ImageOrientationPatient(4:6));
Zz = Zxyz(3);
z_prjs = [Xz, Yz, Zz];


% read in all the dicoms into MATLAB matrix
mag = zeros(imsize(1),imsize(2),imsize(3)*imsize(4),'single');
ph = zeros(imsize(1),imsize(2),imsize(3)*imsize(4),'single');
for i = 1:length(list_dicom)/2
    mag(:,:,i) = dicomread([path_dicom,filesep,list_dicom(i).name]);
end
% reshape the matrix into 4D
mag = reshape(mag,[imsize(1),imsize(2),imsize(4),imsize(3)]);
mag = permute(mag,[2 1 4 3]);
% read in phase images
for i = length(list_dicom)/2+1:length(list_dicom)
    ph(:,:,i-length(list_dicom)/2) = dicomread([path_dicom,filesep,list_dicom(i).name]);
end
ph = reshape(ph,[imsize(1),imsize(2),imsize(4),imsize(3)]);
ph = permute(ph,[2 1 4 3]);
% convert the scale of phjase images
ph = ph/4094*2*pi - pi;

% calculate the slice thickness
dicom_info = dicominfo([path_dicom,filesep,list_dicom(1).name]);
minSlice = dicom_info.SliceLocation;
dicom_info = dicominfo([path_dicom,filesep,list_dicom(end).name]);
maxSlice = dicom_info.SliceLocation;
vox = double([dicom_info.PixelSpacing(1), dicom_info.PixelSpacing(2), abs(maxSlice-minSlice)/(imsize(3)-1)]);

% read in the TEs
for i = 1:imsize(4)
    dicom_info = dicominfo([path_dicom,filesep,list_dicom(i).name]);
    TE(i) = dicom_info.EchoTime*1e-3;
end

% define output directories
path_qsm = [path_out '/QSM_SPGR_PHILIPS'];
[~,~,~] = mkdir(path_qsm);
init_dir = pwd;
cd(path_qsm);



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% discard the first 17 slices for this dataset!!!
%mag = mag(:,:,18:end,:);
%ph = ph(:,:,18:end,:);
%imsize(3) = imsize(3) - 17;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% save magnitude and raw phase niftis for each echo
[~,~,~] = mkdir('src');
for echo = 1:imsize(4)
    nii = make_nii(mag(:,:,:,echo),vox);
    save_nii(nii,['src/mag' num2str(echo) '.nii']);
    nii = make_nii(ph(:,:,:,echo),vox);
    save_nii(nii,['src/ph' num2str(echo) '.nii']);
end


% brain extraction
% generate mask from magnitude of the 1th echo
disp('--> extract brain volume and generate mask ...');
setenv('bet_thr',num2str(bet_thr));
setenv('bet_smooth',num2str(bet_smooth));
[~,~] = unix('rm BET*');
unix('bet2 src/mag1.nii BET -f ${bet_thr} -m -w ${bet_smooth}');
unix('gunzip -f BET.nii.gz');
unix('gunzip -f BET_mask.nii.gz');
nii = load_nii('BET_mask.nii');
mask = single(nii.img);


%%%%%%%%%%%%% is this needed? %%%%%%%%%%%%%%%%%%%% 
 % phase offset correction
 % if unipolar
 %if strcmpi('unipolar',readout)
 %    ph_corr = geme_cmb(mag.*exp(1j*ph),vox,TE,mask);
 %% if bipolar
 %elseif strcmpi('bipolar',readout)
 %    ph_corr = zeros(imsize);
 %    ph_corr(:,:,:,1:2:end) = geme_cmb(mag(:,:,:,1:2:end).*exp(1j*ph(:,:,:,1:2:end)),vox,TE(1:2:end),mask);
 %    ph_corr(:,:,:,2:2:end) = geme_cmb(mag(:,:,:,2:2:end).*exp(1j*ph(:,:,:,2:2:end)),vox,TE(2:2:end),mask);
 %else
 %    error('is the sequence unipolar or bipolar readout?')
 %end
ph_corr = ph;
clear ph;
% save offset corrected phase niftis
for echo = 1:imsize(4)
    nii = make_nii(ph_corr(:,:,:,echo),vox);
    save_nii(nii,['src/ph_corr' num2str(echo) '.nii']);
end


% unwrap phase from each echo
if strcmpi('prelude',ph_unwrap)
    disp('--> unwrap aliasing phase for all TEs using prelude...');
    setenv('echo_num',num2str(imsize(4)));
    bash_command = sprintf(['for ph in src/ph_corr[1-$echo_num].nii\n' ...
    'do\n' ...
    '   base=`basename $ph`;\n' ...
    '   dir=`dirname $ph`;\n' ...
    '   mag=$dir/"mag"${base:7};\n' ...
    '   unph="unph"${base:7};\n' ...
    '   prelude -a $mag -p $ph -u $unph -m BET_mask.nii -n 12&\n' ...
    'done\n' ...
    'wait\n' ...
    'gunzip -f unph*.gz\n']);
    unix(bash_command);

    unph = zeros(imsize);
    for echo = 1:imsize(4)
        nii = load_nii(['unph' num2str(echo) '.nii']);
        unph(:,:,:,echo) = double(nii.img);
    end


elseif strcmpi('bestpath',ph_unwrap)
    % unwrap the phase using best path
    disp('--> unwrap aliasing phase using bestpath...');
    mask_unwrp = uint8(abs(mask)*255);
    fid = fopen('mask_unwrp.dat','w');
    fwrite(fid,mask_unwrp,'uchar');
    fclose(fid);

    [pathstr, ~, ~] = fileparts(which('3DSRNCP.m'));
    setenv('pathstr',pathstr);
    setenv('nv',num2str(imsize(1)));
    setenv('np',num2str(imsize(2)));
    setenv('ns',num2str(imsize(3)));

    unph = zeros(imsize);

    for echo_num = 1:imsize(4)
        setenv('echo_num',num2str(echo_num));
        fid = fopen(['wrapped_phase' num2str(echo_num) '.dat'],'w');
        fwrite(fid,ph_corr(:,:,:,echo_num),'float');
        fclose(fid);
        if isdeployed
            bash_script = ['~/bin/3DSRNCP wrapped_phase${echo_num}.dat mask_unwrp.dat ' ...
            'unwrapped_phase${echo_num}.dat $nv $np $ns reliability${echo_num}.dat'];
        else    
            bash_script = ['${pathstr}/3DSRNCP wrapped_phase${echo_num}.dat mask_unwrp.dat ' ...
            'unwrapped_phase${echo_num}.dat $nv $np $ns reliability${echo_num}.dat'];
        end
        unix(bash_script);

        fid = fopen(['unwrapped_phase' num2str(echo_num) '.dat'],'r');
        tmp = fread(fid,'float');
        % tmp = tmp - tmp(1);
        unph(:,:,:,echo_num) = reshape(tmp - round(mean(tmp(mask==1))/(2*pi))*2*pi ,imsize(1:3)).*mask;
        fclose(fid);

        fid = fopen(['reliability' num2str(echo_num) '.dat'],'r');
        reliability_raw = fread(fid,'float');
        reliability_raw = reshape(reliability_raw,imsize(1:3));
        fclose(fid);

        nii = make_nii(reliability_raw.*mask,vox);
        save_nii(nii,['reliability_raw' num2str(echo_num) '.nii']);
    end
    
    clear reliability_raw mask_unwrp tmp;

    nii = make_nii(unph,vox);
    save_nii(nii,'unph_bestpath.nii');

else
    error('what unwrapping methods to use? prelude or bestpath?')
end

clear ph_corr;

% check and correct for 2pi jump between echoes
disp('--> correct for potential 2pi jumps between TEs ...')

% nii = load_nii('unph_cmb1.nii');
% unph1 = double(nii.img);
% nii = load_nii('unph_cmb2.nii');
% unph2 = double(nii.img);
% unph_diff = unph2 - unph1;

% nii = load_nii('unph_diff.nii');
% unph_diff = double(nii.img);
unph_diff = unph(:,:,:,2) - unph(:,:,:,1);
if strcmpi('bipolar',readout)
    unph_diff = unph_diff/2;
end

for echo = 2:imsize(4)
    meandiff = unph(:,:,:,echo)-unph(:,:,:,1)-double(echo-1)*unph_diff;
    meandiff = meandiff(mask==1);
    meandiff = mean(meandiff(:));
    njump = round(meandiff/(2*pi));
    disp(['    ' num2str(njump) ' 2pi jumps for TE' num2str(echo)]);
    unph(:,:,:,echo) = unph(:,:,:,echo) - njump*2*pi;
    unph(:,:,:,echo) = unph(:,:,:,echo).*mask;
end

clear unph_diff;

nii = make_nii(unph,vox);
save_nii(nii,'unph_corrected.nii');

% fit phase images with echo times
disp('--> magnitude weighted LS fit of phase to TE ...');
[tfs, fit_residual] = echofit(unph,mag,TE,0); 
Mag = mag(:,:,:,end);

clear unph mag;

% extra filtering according to fitting residuals
if r_mask
    % generate reliability map
    fit_residual = smooth3(fit_residual,'box',round(1./vox)*2+1); 
    nii = make_nii(fit_residual,vox);
    save_nii(nii,'fit_residual_blur.nii');
    R = ones(size(fit_residual),'single');
    R(fit_residual >= fit_thr) = 0;
else
    R = 1;
end

clear fit_residual

% normalize to main field
% ph = gamma*dB*TE
% dB/B = ph/(gamma*TE*B0)
% units: TE s, gamma 2.675e8 rad/(sT), B0 3T
tfs = tfs/(2.675e8*dicom_info.MagneticFieldStrength)*1e6; % unit ppm

nii = make_nii(tfs,vox);
save_nii(nii,'tfs.nii');


% background field removal and dipole inversion
% PDF
if sum(strcmpi('pdf',bkg_rm))
    disp('--> PDF to remove background field ...');
    lfs_pdf = projectionontodipolefields(tfs,mask.*R,vox,Mag,z_prjs);
    % 3D 2nd order polyfit to remove any residual background
    % lfs_pdf= lfs_pdf - poly3d(lfs_pdf,mask_pdf);

    % save nifti
    [~,~,~] = mkdir('PDF');
    nii = make_nii(lfs_pdf,vox);
    save_nii(nii,'PDF/lfs_pdf.nii');

    % inversion of susceptibility 
    disp('--> TV susceptibility inversion on PDF...');
    sus_pdf = tvdi(lfs_pdf,mask_pdf,vox,tv_reg,Mag,z_prjs,inv_num); 

    % save nifti
    nii = make_nii(sus_pdf.*mask_pdf,vox);
    save_nii(nii,['PDF/sus_pdf_tv_', num2str(tv_reg), '_num_', num2str(inv_num), '.nii']);
end

% SHARP (t_svd: truncation threthold for t_svd)
if sum(strcmpi('sharp',bkg_rm))
    disp('--> SHARP to remove background field ...');
    [lfs_sharp, mask_sharp] = sharp(tfs,mask.*R,vox,smv_rad,t_svd);
    % % 3D 2nd order polyfit to remove any residual background
    % lfs_sharp= lfs_sharp - poly3d(lfs_sharp,mask_sharp);

    % save nifti
    [~,~,~] = mkdir('SHARP');
    nii = make_nii(lfs_sharp,vox);
    save_nii(nii,'SHARP/lfs_sharp.nii');
    
    % inversion of susceptibility 
    disp('--> TV susceptibility inversion on SHARP...');
    sus_sharp = tvdi(lfs_sharp,mask_sharp,vox,tv_reg,Mag,z_prjs,inv_num); 
   
    % save nifti
    nii = make_nii(sus_sharp.*mask_sharp,vox);
    save_nii(nii,['SHARP/sus_sharp_tv_', num2str(tv_reg), '_num_', num2str(inv_num), '.nii']);
end

% RE-SHARP (tik_reg: Tikhonov regularization parameter)
if sum(strcmpi('resharp',bkg_rm))
    disp('--> RESHARP to remove background field ...');
    [lfs_resharp, mask_resharp] = resharp(tfs,mask.*R,vox,smv_rad,tik_reg,cgs_num);
    % % 3D 2nd order polyfit to remove any residual background
    % lfs_resharp= lfs_resharp - poly3d(lfs_resharp,mask_resharp);

    % save nifti
    [~,~,~] = mkdir('RESHARP');
    nii = make_nii(lfs_resharp,vox);
    save_nii(nii,['RESHARP/lfs_resharp_tik_', num2str(tik_reg), '_num_', num2str(cgs_num), '.nii']);

    % inversion of susceptibility 
    disp('--> TV susceptibility inversion on RESHARP...');
    sus_resharp = tvdi(lfs_resharp,mask_resharp,vox,tv_reg,Mag,z_prjs,inv_num); 
   
    % save nifti
    nii = make_nii(sus_resharp.*mask_resharp,vox);
    save_nii(nii,['RESHARP/sus_resharp_tik_', num2str(tik_reg), '_tv_', num2str(tv_reg), '_num_', num2str(inv_num), '.nii']);
end

% E-SHARP (SHARP edge extension)
if sum(strcmpi('esharp',bkg_rm))
    disp('--> E-SHARP to remove background field ...');
    Parameters.voxelSize             = vox; % in mm
    Parameters.resharpRegularization = tik_reg ;
    Parameters.resharpKernelRadius   = smv_rad ; % in mm
    Parameters.radius                = [ 10 10 5 ] ;

    % pad matrix size to even number
    pad_size = mod(size(tfs),2);
    tfs = tfs.*mask.*R;
    tfs = padarray(tfs, pad_size, 'post');

    % taking off additional 1 voxels from edge - not sure the outermost 
    % phase data included in the original mask is reliable. 
    mask_shaved = shaver( ( tfs ~= 0 ), 1 ) ; % 1 voxel taken off
    totalField  = mask_shaved .* tfs ;

    % resharp 
    [reducedLocalField, maskReduced] = ...
        resharp( totalField, ...
                 double(mask_shaved), ...
                 Parameters.voxelSize, ...
                 Parameters.resharpKernelRadius, ...
                 Parameters.resharpRegularization ) ;

    % extrapolation ~ esharp 
    reducedBackgroundField = maskReduced .* ( totalField - reducedLocalField) ;

    extendedBackgroundField = extendharmonicfield( ...
       reducedBackgroundField, mask, maskReduced, Parameters) ;

    backgroundField = extendedBackgroundField + reducedBackgroundField ;
    localField      = totalField - backgroundField ;

    lfs_esharp      = localField(1+pad_size(1):end,1+pad_size(2):end,1+pad_size(3):end);
    mask_esharp     = mask_shaved(1+pad_size(1):end,1+pad_size(2):end,1+pad_size(3):end);  

    % % 3D 2nd order polyfit to remove any residual background
    % lfs_esharp = lfs_esharp - poly3d(lfs_esharp,mask_esharp);

    % save nifti
    [~,~,~] = mkdir('ESHARP');
    nii = make_nii(lfs_esharp,vox);
    save_nii(nii,'ESHARP/lfs_esharp.nii');

    % inversion of susceptibility 
    disp('--> TV susceptibility inversion on ESHARP...');
    sus_esharp = tvdi(lfs_esharp,mask_esharp,vox,tv_reg,Mag,z_prjs,inv_num); 
   
    % save nifti
    nii = make_nii(sus_esharp.*mask_esharp,vox);
    save_nii(nii,['ESHARP/sus_esharp_tv_', num2str(tv_reg), '_num_', num2str(inv_num), '.nii']);
end

% LBV
if sum(strcmpi('lbv',bkg_rm))
   disp('--> LBV to remove background field ...');
   lfs_lbv = LBV(tfs,mask.*R,imsize(1:3),vox,lbv_tol,lbv_peel); % strip 2 layers
   mask_lbv = ones(imsize(1:3));
   mask_lbv(lfs_lbv==0) = 0;
   % 3D 2nd order polyfit to remove any residual background
   % lfs_lbv= lfs_lbv - poly3d(lfs_lbv,mask_lbv);

   % save nifti
   [~,~,~] = mkdir('LBV');
   nii = make_nii(lfs_lbv,vox);
   save_nii(nii,'LBV/lfs_lbv.nii');

   % inversion of susceptibility 
   disp('--> TV susceptibility inversion on lbv...');
   sus_lbv = tvdi(lfs_lbv,mask_lbv,vox,tv_reg,Mag,z_prjs,inv_num);   

   % save nifti
   nii = make_nii(sus_lbv.*mask_lbv,vox);
   save_nii(nii,['LBV/sus_lbv_tv_', num2str(tv_reg), '_num_', num2str(inv_num), '.nii']);
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% tik-qsm
%
%% pad zeros
%tfs_pad = padarray(tfs,[0 0 20]);
%mask_pad = padarray(mask,[0 0 20]);
%R_pad = padarray(R,[0 0 20]);
%
%for r = [1 2 3] 
%
%    [X,Y,Z] = ndgrid(-r:r,-r:r,-r:r);
%    h = (X.^2/r^2 + Y.^2/r^2 + Z.^2/r^2 <= 1);
%    ker = h/sum(h(:));
%    imsize = size(mask_pad);
%    mask_tmp = convn(mask_pad.*R_pad,ker,'same');
%    mask_ero = zeros(imsize);
%    mask_ero(mask_tmp > 1-1/sum(h(:))) = 1; % no error tolerance
%
%    % try total field inversion on regular mask, regular prelude
%    Tik_weight = 0.01;
%    TV_weight = 0.0005;
%    chi = tikhonov_qsm(tfs_pad, mask_ero, 1, mask_ero, mask_ero, TV_weight, Tik_weight, vox, z_prjs, 2000);
%    nii = make_nii(chi(:,:,21:end-20).*mask_ero(:,:,21:end-20).*R_pad(:,:,21:end-20),vox);
%    save_nii(nii,['chi_brain_pad20_ero' num2str(r) '_TV_' num2str(TV_weight) '_Tik_' num2str(Tik_weight) '_2000.nii']);
%
%end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

save('all.mat','-v7.3');
cd(init_dir);

