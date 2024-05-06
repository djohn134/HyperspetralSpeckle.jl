using TwoDimensional
using LinearInterpolators


function create_extractor_operator(position, screen_dim, output_dim, scaleby_height, scaleby_wavelength; FTYPE=FTYPE)
    kernel = LinearSpline(FTYPE)
    transform = AffineTransform2D{FTYPE}()
    screen_size = (Int64(screen_dim), Int64(screen_dim))
    output_size = (Int64(output_dim), Int64(output_dim))
    full_transform = ((transform + Tuple(position)) * (1/(scaleby_height*scaleby_wavelength))) - (output_dim÷2, output_dim÷2)
    extractor = TwoDimensionalTransformInterpolator(output_size, screen_size, kernel, full_transform)
    return extractor
end

function create_extractor_adjoint(position, screen_dim, input_dim, scaleby_height, scaleby_wavelength; FTYPE=FTYPE)
    kernel = LinearSpline(FTYPE)
    transform = AffineTransform2D{FTYPE}()
    screen_size = (Int64(screen_dim), Int64(screen_dim))
    input_size = (Int64(input_dim), Int64(input_dim))
    full_transform = ((transform + (input_dim÷2, input_dim÷2)) * (scaleby_height*scaleby_wavelength)) - Tuple(position)
    extractor_adj = TwoDimensionalTransformInterpolator(screen_size, input_size, kernel, full_transform)
    return extractor_adj
end

function position2phase(ϕ_full, position, scaleby_height, scaleby_wavelength, dim; FTYPE=Float64)
    ϕ_out = zeros(FTYPE, dim, dim)
    extractor = create_extractor_operator(position, size(ϕ_full, 1), dim, scaleby_height, scaleby_wavelength, FTYPE=FTYPE)
    position2phase!(ϕ_out, ϕ_full, extractor)
    return ϕ_out
end

function position2phase!(ϕ_out, ϕ_full, extractor)
    mul!(ϕ_out, extractor, ϕ_full)
end

function create_refraction_operator(λ, λ_ref, ζ, pixscale, build_dim; FTYPE=Float64)
    kernel = LinearSpline(FTYPE)
    transform = AffineTransform2D{FTYPE}()
    θref = get_refraction(λ_ref, ζ)
    build_size = (Int64(build_dim), Int64(build_dim))
    θλ = get_refraction(λ, ζ)
    Δpix = FTYPE(206265*(θλ-θref) / (pixscale * FTYPE(build_dim)))
    refraction = TwoDimensionalTransformInterpolator(build_size, build_size, kernel, transform - (Δpix, 0))
    return refraction
end

function pupil2psf(mask, λ, λ_ref, ζ, A, ϕ, build_dim, α, scale_psf, pixscale; FTYPE=Float64)
    P = zeros(FTYPE, build_dim, build_dim)
    p = zeros(Complex{FTYPE}, build_dim, build_dim)
    psf = zeros(FTYPE, build_dim, build_dim)
    psf_temp = zeros(FTYPE, build_dim, build_dim)
    refraction = create_refraction_operator(λ, λ_ref, ζ, pixscale, build_dim; FTYPE=FTYPE)
    pupil2psf!(psf, psf_temp, mask, P, p, A, ϕ, α, scale_psf, FTYPE(build_dim), refraction)
    return psf
end

function pupil2psf!(psf, psf_temp, mask, P, p, A, ϕ, α, scale_psf, scale_ifft::AbstractFloat, refraction)
    P .= mask .* scale_psf .* A .* cis.(ϕ)
    p .= ift(P) .* scale_ifft
    psf_temp .= α .* abs2.(p)
    mul!(psf, refraction, psf_temp)
end

function pupil2psf!(psf, psf_temp, mask, P, p, A, ϕ, α, scale_psf, ifft_prealloc!::Function, refraction)
    P .= mask .* scale_psf .* A .* cis.(ϕ)
    ifft_prealloc!(p, P)
    psf_temp .= α .* abs2.(p)
    mul!(psf, refraction, psf_temp)
end

function create_monochromatic_image(object, psf, dim)
    image_big = conv_psf(object, psf)
    image_small = block_reduce(image_big, dim)
    return image_small
end

function create_monochromatic_image!(image_small, image_big, object::AbstractMatrix{<:AbstractFloat}, psf)
    image_big .= conv_psf(object, psf)
    block_reduce!(image_small, image_big)
end

function create_monochromatic_image!(image_small, image_big, o_conv::Function, psf)
    image_big .= o_conv(psf)
    block_reduce!(image_small, image_big)
end

function create_polychromatic_image(object, psfs, λ, Δλ, dim; FTYPE=Float64)
    build_dim = size(psfs, 1)
    image = zeros(FTYPE, build_dim, build_dim)
    image_small = zeros(FTYPE, dim, dim)
    image_big = zeros(FTYPE, build_dim, build_dim)
    create_polychromatic_image!(image, image_small, image_big, object, psfs, λ, Δλ)
    return image
end

@views function create_polychromatic_image!(image, image_small::AbstractArray{<:AbstractFloat, 2}, image_big, object::AbstractArray{<:AbstractFloat, 3}, psfs, λ, Δλ)
    nλ = length(λ)
    for w=1:nλ
        create_monochromatic_image!(image_small, image_big, object[:, :, w], psfs[:, :, w])
        image .+= image_small
    end
    image .*= Δλ
end

@views function create_polychromatic_image!(image, image_small::AbstractArray{<:AbstractFloat, 2}, image_big, o_conv::AbstractVector{<:Function}, psfs, λ, Δλ)
    nλ = length(λ)
    for w=1:nλ
        create_monochromatic_image!(image_small, image_big, o_conv[w], psfs[:, :, w])
        image .+= image_small
    end
    image .*= Δλ
end

@views function create_polychromatic_image!(image, image_small::AbstractArray{<:AbstractFloat, 3}, image_big, object, psfs, λ, Δλ)
    nλ = length(λ)
    for w=1:nλ
        create_monochromatic_image!(image_small[:, :, w], image_big, object[:, :, w], psfs[:, :, w])
        image .+= image_small[:, :, w]
    end
    image .*= Δλ
end

@views function create_polychromatic_image!(image, image_small::AbstractMatrix{<:AbstractFloat}, image_big, ω, object_patch, object::AbstractArray{<:AbstractFloat, 3}, psfs, λ, Δλ)
    nλ = length(λ)
    for w=1:nλ
        object_patch .= ω .* object[:, :, w]
        create_monochromatic_image!(image_small, image_big, object_patch, psfs[:, :, w])
        image .+= image_small
    end
    image .*= Δλ
end

@views function create_polychromatic_image!(image, image_small::AbstractArray{<:AbstractFloat, 3}, image_big, ω, object_patch, object::AbstractArray{<:AbstractFloat, 3}, psfs, λ, Δλ)
    nλ = length(λ)
    for w=1:nλ
        object_patch .= ω .* object[:, :, w]
        create_monochromatic_image!(image_small[:, :, w], image_big, object_patch, psfs[:, :, w])
        image .+= image_small
    end
    image .*= Δλ
end

function add_noise!(image, rn, poisson::Bool; FTYPE=Float64)
    if poisson == true
        image .= FTYPE.(rand.(Distributions.Poisson.(image)))
    end
    ## Read noise has a non-zero mean and sigma!
    image .+= rn .* randn(FTYPE, size(image))
    image .= max.(image, Ref(zero(FTYPE)))
end
