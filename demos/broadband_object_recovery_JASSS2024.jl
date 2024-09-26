include("../src/mfbd.jl");
using Main.MFBD;
using Statistics;
using LuckyImaging;
show_the_satellite()

############# Data Parameters #############
FTYPE = Float32;
folder = "/home/dan/Desktop/JASS_2024/prime-95b/monte_carlo";
verb = true
plot = true
###########################################

##### Size, Timestep, and Wavelengths #####
image_dim = 512
nλ = 10
nλint = 1
nλtotal = nλ * nλint
λ_nyquist = 400.0
λ_ref = 500.0
λmin = 400.0
λmax = 1000.0
λ = (nλ == 1) ? [mean([λmax, λmin])] : collect(range(λmin, stop=λmax, length=nλ))
λtotal = (nλtotal == 1) ? [mean([λmax, λmin])] : collect(range(λmin, stop=λmax, length=nλtotal))
Δλ = (nλ == 1) ? 1.0 : (λmax - λmin) / (nλ - 1)
Δλtotal = (nλtotal == 1) ? 1.0 : (λmax - λmin) / (nλtotal - 1)
###########################################
id = "_1_nlambda$(nλ)_afterupdate"

########## Anisopatch Parameters ##########
## Unused but sets the size of the layer ##
isoplanatic = true
patch_overlap = 0.5
patch_dim = 64
###### Create Anisoplanatic Patches #######
patches = AnisoplanaticPatches(patch_dim, image_dim, patch_overlap, isoplanatic=isoplanatic, FTYPE=FTYPE)
###########################################

### Detector & Observations Parameters ####
D = 3.6  # m
fov = 8.0  # arcsec
pixscale_full = fov / image_dim
qefile = "data/qe/prime-95b_qe.dat"
~, qe = readqe(qefile, λ=λtotal)
# qe = ones(FTYPE, nλtotal)
rn = 2.0
exptime = 5e-3
ζ = 0.0
######### Create Detector object ##########
filter = Filter(filtername="broadband", λ=λtotal, FTYPE=FTYPE)
detector_full = Detector(
    qe=qe,
    rn=rn,
    pixscale=pixscale_full,
    λ=λtotal,
    λ_nyquist=λ_nyquist,
    exptime=exptime,
    filter=filter,
    FTYPE=FTYPE
)
# detectors = [
#     Detector(
#         qe=qe,
#         rn=rn,
#         pixscale=pixscale_full,
#         λ=λtotal,
#         λ_nyquist=λ_nyquist,
#         exptime=exptime,
#         filter=Filter(λ=[λ[w]], response=[1.0], FTYPE=FTYPE),
#         FTYPE=FTYPE 
#     ) for w=1:nλtotal
# ]
### Create Full-Ap Observations object ####
datafile = "$(folder)/Dr0_20_ISH1x1_images_1.fits"
observations_full = Observations(
    detector_full,
    ζ=ζ,
    D=D,
    α=1.0,
    datafile=datafile,
    FTYPE=FTYPE
)
# datafiles = [
#     "$(folder)/Dr0_20_ISH1x1_images_400nm.fits",
#     "$(folder)/Dr0_20_ISH1x1_images_550nm.fits",
#     "$(folder)/Dr0_20_ISH1x1_images_700nm.fits",
#     "$(folder)/Dr0_20_ISH1x1_images_850nm.fits",
#     "$(folder)/Dr0_20_ISH1x1_images_1000nm.fits"
# ]
# observations = [
#     Observations(
#         detectors[w],
#         ζ=ζ,
#         D=D,
#         α=1.0,
#         datafile=datafiles[w],
#         FTYPE=FTYPE
#     ) for w=1:nλtotal
# ]
##### Create WFS Observations object ######
observations = [observations_full]
###########################################

########### Load Full-Ap Masks ############
masks_full = Masks(
    dim=observations[1].dim,
    nsubaps_side=1, 
    λ=λtotal,
    λ_nyquist=λ_nyquist, 
    FTYPE=FTYPE
)
# masks = [
#     Masks(
#         dim=observations[w].dim,
#         nsubaps_side=1, 
#         λ=[λtotal[w]],
#         λ_nyquist=λ_nyquist, 
#         FTYPE=FTYPE
# ) for w=1:nλtotal]
masks = [masks_full]
###########################################

############ Object Parameters ############
object_height = 515.0  # km
############## Create object ##############
object = Object(
    λ=λ,
    height=object_height, 
    fov=fov,
    dim=observations[1].dim,
    FTYPE=FTYPE
)
# all_subap_images = lucky_image(observations[1].images[:, :, 1, :], dims=3, q=0.9)
# object.object = repeat(all_subap_images, 1, 1, nλ)
# object.object ./= sum(object.object)
# object.object .*= mean(sum(observations[1].images, dims=(1, 2)), dims=(3, 4))
# object.object = zeros(FTYPE, image_dim, image_dim, nλ)
nλ₀ = 10
λ₀ = (nλ₀ == 1) ? [mean([λmax, λmin])] : collect(range(λmin, stop=λmax, length=nλ₀))
Δλ₀ = (nλ₀ == 1) ? 1.0 : (λmax - λmin) / (nλ₀ - 1)
# object.object = readfits("$(folder)/object_recon_nlambda10_deepsolve.fits", FTYPE=FTYPE)
# object.object = repeat(readfits("$(folder)/object_recon_1_nlambda1.fits", FTYPE=FTYPE), 1, 1, nλ)  ./ (nλ * Δλ)
object.object = interpolate_object(readfits("$(folder)/object_recon_1_nlambda$(nλ₀)_opdupdate.fits", FTYPE=FTYPE), λ₀, λ) .* (nλ₀/nλ) .* (Δλ₀/Δλ)
# object.object .= repeat(object.object[:, :, end], 1, 1, nλ)
###########################################

########## Atmosphere Parameters ##########
heights = [0.0, 7.0, 12.5]
wind_speed = wind_profile_roberts2011(heights, ζ)
wind_direction = [45.0, 125.0, 135.0]
wind = [wind_speed wind_direction]
nlayers = length(heights)
scaleby_wavelength = λ_nyquist ./ λtotal
Dmeta = D .+ (fov/206265) .* (heights .* 1000)
sampling_nyquist_mperpix = (2*D / image_dim) .* ones(nlayers)
sampling_nyquist_arcsecperpix = (fov / image_dim) .* (Dmeta ./ D)
############ Create Atmosphere ############
atmosphere = Atmosphere(
    wind=wind, 
    heights=heights, 
    sampling_nyquist_mperpix=sampling_nyquist_mperpix,
    sampling_nyquist_arcsecperpix=sampling_nyquist_arcsecperpix,
    λ=λtotal,
    λ_nyquist=λ_nyquist,
    λ_ref=λ_ref,
    verb=verb,
    FTYPE=FTYPE
)
########## Create phase screens ###########
calculate_screen_size!(atmosphere, observations[1], object, patches, verb=verb)
calculate_pupil_positions!(atmosphere, observations[1], verb=verb)
calculate_layer_masks_eff_alt!(atmosphere, observations[1], object, masks[1], verb=verb)
# atmosphere.masks = ones(FTYPE, atmosphere.dim, atmosphere.dim, atmosphere.nlayers, atmosphere.nλ)
atmosphere.opd = readfits("$(folder)/opd_recon_1_nlambda$(nλ₀)_opdupdate.fits", FTYPE=FTYPE)
atmosphere.opd .*= atmosphere.masks[:, :, :, 1]
# atmosphere.opd = zeros(FTYPE, atmosphere.dim, atmosphere.dim, atmosphere.nlayers)
###########################################

######### Reconstruction Object ###########
reconstruction = Reconstruction(
    atmosphere,
    observations,
    object,
    patches,
    nλ=nλ,
    λmin=λmin,
    λmax=λmax,
    nλint=nλint,
    niter_mfbd=1,
    # indx_boot=[1:nλ],
    maxiter=5000,
    # weight_function=mixed_weighting,
    # gradient_object=gradient_object_mixednoise!,
    # gradient_opd=gradient_opd_mixednoise!,
    maxeval=Dict("opd"=>1, "object"=>10000),
    smoothing=false,
    grtol=1e-4,
    build_dim=image_dim,
    verb=verb,
    plot=plot,
    FTYPE=FTYPE
);
reconstruct_blind!(reconstruction, observations, atmosphere, object, masks, patches)
###########################################

###########################################
## Write isoplanatic phases and images ####
writefits(observations[1].model_images, "$(folder)/models_ISH1x1_recon$(id).fits")
# writefits(patches.psfs[1], "$(folder)/psfs_ISH1x1_recon$(id).fits")
writefits(object.object, "$(folder)/object_recon$(id).fits")
# writefits(atmosphere.opd, "$(folder)/opd_recon$(id).fits")
writefile([reconstruction.ϵ], "$(folder)/recon$(id).dat")
###########################################