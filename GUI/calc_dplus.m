function [sdatar, sdatai, srhoa, sphas] = calc_dplus(freq, datar, datai, std, type)
% function [chisq, C ,z ,tau] = dplus(f, c, dc)
%  function [chisq C h tau] = dplus(f, c, dc)
%  Performs D+ inversion of admittance data, yielding smallest
%  possible misfit, chisq, of any 1-D isotropic conductivity
%  profile fitting admittance (-E/E') values at discrete
%  frequencies.
%  f   frequency vector in Hz.
%  c   corresponding vector of complex valued admittances in meters.
%  dc  real or complex standard error vector, meters.
%
%  chisq   smallest possible sum of squared misfits, each
%     element weighted by inverse standard error.
%  C  complex vector of admittance generated by the model.
%  z  vector of depths to delta function conductivites, in km.
%  tau vector of conductances (integral of conductivity) of
%      delta function sheets in D+, best-fitting model, in S/m.
%  calls minimize dpmodel
%

%
% D+ is from Robert L. Parker; the original function was downloaded from
% http://igppweb.ucsd.edu/~parker/Software/
% on 27 August 2015.
%
%
% This version was adjusted 2015, 2016 by GEOTEM Ingenieria S.A. de C.V. to
% suit the need for the GUI Edi2Mare.
%
% Changes made:
% disabled dpmodel, inverted impedances, disabled plot functionality
% suppressed all print statements
% => JUST CALCULATE NEW IMPEDANCE, and Rho_a/Phase thereof.
%

% 1. Convert impedance into admittance
if strcmp(type, 'xy')
    data = 1./complex(datar, datai);
elseif strcmp(type, 'yx')
    data = 1./complex(-datar, -datai);
else
    error('Data-type must be <xy> or <yx>!')
end

% Calculate
[~, sdata ,~ ,~]  = minimize(freq, data, std);

% Convert admittance back to impedance
if strcmp(type, 'xy')
    sdatar = real(1./sdata)';
    sdatai = imag(1./sdata)';
elseif strcmp(type, 'yx')
    sdatar = -real(1./sdata)';
    sdatai = -imag(1./sdata)';
end

% Calculate Apparent resistivity and Phase
cdata.real = sdatar;
cdata.imag = sdatai;
cdata.freq = freq;
[srhoa, sphas] =  calc_rhoaphase(cdata, 'rhoaphas');

% ORIGINAL VERSION
% [chisq, C ,la ,b]  = minimize(f,c,dc);
% [z, tau] = dpmodel(la, b);

return
%----------------------------------------------------------

function [chisq, C, la, b] = minimize(f, c ,dc)
%  function [chisq C la b] = minimize(f, c ,dc)
%  Find minimum chisq corresponding to data vectors
%  calls z2r

M = 50;
nit =4;
nf = length(f);

ome = 2*pi*f(:);
lamin = 0.01*min(ome);
lamax = 5*max(ome);
la = [0, logspace(log10(lamin), log10(lamax), M-1)];

if norm(imag(dc)) == 0
  de = [ dc(:) ; dc(:) ];
else
  de = [real(dc(:)) ; imag(dc(:)) ];
end
SIGinv = diag( 1 ./de ) ;
d =  [real(c(:)) ; imag(c(:))];

%  Solve quadratic program, increasing lambda density near positive components
for iter = 1:nit

% Refinement: increase lambda sampling at +ve elements
  if (iter > 1)
    I = 1 + find(b(3:end-1) > 0)' ;
    upla=la(I)+(la(I+1)-la(I))/3;
    dnla=la(I)-(la(I)-la(I-1))/3;
    la=sort([la, upla, dnla]);
    if b(end) > 0; la = [la, 2*la(end)]; end %#ok
    M=length(la);
  end

  [La, Om] = meshgrid(la, ome);
  Z = 1 ./(La + 1i*Om);
  A = [ones(nf,1),real(Z); zeros(nf,1),imag(Z)];
  b = lsqnonneg(SIGinv*A, SIGinv*d);
  chisq = norm(SIGinv*(A*b-d))^2; %#ok commented chisq out
  % fprintf('With vector length %d chisq= %0.5g',M,chisq)

end  % Refinement iteration

% Merge doublets
j=1;
newla = la;
sumbla=0;
sumb=0;

%  Form weighted average of non-zero lambda
for k = 2:M
  if b(k) > 0
    sumbla = sumbla + b(k)*la(k-1);
    sumb = sumb + b(k);
  else
    if sumb > 0
      newla(j) = sumbla/sumb;
      sumb = 0;
      sumbla = 0;
      j=j+1;
    end
  end
end % k loop

if b(end) > 0
  newla(j)=la(end);
else
 j=j-1;
end

la = newla(1:j)';
M = length(la);  %#ok commented M out

%  Final minimzation on reduced lambda set
[La, Om] = meshgrid(la, ome);
Z = 1 ./(La + 1i*Om);
A = [ones(nf,1),real(Z); zeros(nf,1),imag(Z)];
b = lsqnonneg(SIGinv*A, SIGinv*d);

C = A*b;
C = C(1:nf) + 1i*C(nf+1:end);

% loglog(f, z2r(c'), '+', f, z2r(C'))

chisq = norm(SIGinv*(A*b-d))^2;
% fprintf('With vector length %d chisq= %0.5g',M,chisq)
% disp(' ')
return
%----------------------------------------------------------
function [z, tau] = dpmodel(la, a)  %#ok commented dpmodel out
%  function [z tau] = dpmodel(la, a)
%  la and a are the real numbers in theexpansion:
%  c(om) = a(1) + sum (n=1,2, ...) a(n+1)/(i*om + la(n))
%  outputs depths z to delta function layers of conductivity tau
%  calls qd list

ala = [a(2:end)'; la'];

%  Perform the inscrutable quotient-difference algorithm that stably
%  takes the partial fraction into 1/z type continued fraction
cf = qd(ala);

zf = [a(1); cf];
if la(1) == 0; zf(end) = 0; end

dz = a;
if la(1) > 0; dz = [dz; 0]; end
z = dz;
tau = dz;

% Map continued frsction into conductivity model
emuo =pi*4e-7;

for j = 2:2: length(zf)
  l = j/2;
  if  j > 2;  tau(l) = 1/(emuo*dz(l)*zf(j)); end
  if  j == 2; tau(l) = 1/(emuo*zf(j)); end
  if  zf(j+1) == 0; l=l-1; break; end
  dz(l+1) = 1/(emuo*tau(l)*zf(j+1));
  z(l+1) = z(l) + dz(l+1);
end
z = z(1:l+1);
tau = tau(1:l+1);

if la(1) > 0; tau(l+1) = inf; end

% Print results
disp('D+ model in km and S')
list([z/1000,tau])

if la(1) > 0
 disp('Model terminates with a perfect conductor')
else
 disp('Model terminates with an insulator')
end
%----------------------------------------------------------
function cf =  qd(c_in)
%  function cf =  qd(c_in)
%  Quotient-difference scheme to convert partial fraction in
%  c_in to 1/z-type continued fraction in cf.
% calls solve

[m, n] = size(c_in); %#ok
c = c_in;  cf = zeros(2*n,1);

if n > 1
  for i = 2:n
    c = solve(i, c);
  end
end

cf(1) = c(1,1);
cf(2) = c(2,1);
if n == 1;  return; end
for i = 1:n-1
  j = 2*i+1;
  cf(j) = c(1,i+1)/cf(j-1);
  cf(j+1) = c(2,i+1)-cf(j);
end
return
%_______________________________________________________________________
function c = solve(i, c_in)
%  function c = solve(i, c_in)
%  Adds in one more partial fraction and computes the new c0
%  and alpha,beta arrays
% calls update

alamb = zeros(4,1); c = c_in;

%  New values of c0,alpha(1),beta(1)
c0dash = c(1,1)+c(1,i);
rho1 = c(2,1)-c(2,i);
rho2 = c(1,1)*rho1/c0dash;
c(1,1) = c0dash;
alamb(1) = 0;

if i > 2; alamb(1) = c(1,2)/rho1; end
alamb(2) = rho1-rho2+alamb(1);
c(2,1) = rho2+c(2,i);
c(1,2) = alamb(2)*rho2;

%  Special case when i = 2
if i <= 2
  c(2,2) = alamb(2)+c(2,i);
  return
end

%  Skip case when i = 3
if i > 3
  [alamb, c] = update(i-2, alamb, c, i);
end

%  Calculate final beta value and last two alphas
rho1 = c(2,i-1)-c(2,i)-alamb(1);
rho2 = alamb(1)*rho1/alamb(2);
alamb(4) = rho1-rho2;
c(2,i-1) = alamb(2)+rho2+c(2,i);
c(1,i) = alamb(4)*rho2;
c(2,i) = alamb(4)+c(2,i);
return
%_______________________________________________________________________
function [alamb, c] =  update(n, alamb_inp, c_inp, i)
%  function [alamb c] =  update(n, alamb_inp, c_inp, i)
%  Updates continued fraction when one new partial fracyion
%  term is added; does not do 1st and last levels.
%  cals nothing

alamb = alamb_inp; c = c_inp;

for k = 2:n
  rho1 = c(2,k)-c(2,i)-alamb(1);
  rho2 = alamb(1)*rho1/alamb(2);
  alamb(3) = c(1,k+1)/rho1;
  alamb(4) = rho1-rho2+alamb(3);
  c(2,k)   = alamb(2)+rho2+c(2,i);
  c(1,k+1) = rho2*alamb(4);
  alamb(1) = alamb(3);
  alamb(2) = alamb(4);
end
return
%_______________________________________________________________________
function xy = z2r(z)
% Split complex array z into real imaginary parts as
% a real n by 2 array xy.  Useful for plotting complex functions
%
xy = [real(z(:)), imag(z(:))];
%_______________________________________________________________________
function dum=list(x) %#ok
% Compact listing of an array without all the cols 1 through 7 crap.
% Usage: list(x);
%
[mx,nx]=size(x);
%
% This is a row vector: list it
if (mx == 1),
  for i=1: 8 : nx
    for j=i: min(nx,i+7)
     fprintf('%11.7g ',x(j))
    end
    fprintf('\n')
   end
% This is a matrix: send its rows down to the row vector lister.
% Print a space between rows if row length exceeds 8.
else
  for k=1: mx
    list(x(k,:));
    if (nx > 8),
      fprintf('\n')
    end
  end
end
%_______________________________________________________________________
