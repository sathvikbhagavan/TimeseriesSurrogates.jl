export BlockShuffle, CycleShuffle, CircShift

#########################################################################
# BlockSuffle
#########################################################################
"""
    BlockShuffle(n::Int) <: Surrogate

A block shuffle surrogate constructed by dividing the time series
into `n` blocks of roughly equal width at random indices (end
blocks are wrapped around to the start of the time series).

Block shuffle surrogates roughly preserve short-range temporal properties
in the time series (e.g. correlations at lags less than the block length),
but break any long-term dynamical information (e.g. correlations beyond
the block length).

Hence, these surrogates can be used to test any null hypothesis aimed at
comparing short-range dynamical properties versus long-range dynamical
properties of the signal.
"""
struct BlockShuffle <: Surrogate
    n::Int
end

Base.show(io::IO, bs::BlockShuffle) = show(io, "BlockShuffle(n=$(bs.n))")

# Split time series in two by default.
BlockShuffle() = BlockShuffle(2)

function get_uniform_blocklengths(L::Int, n::Int)
    # Compute block lengths
    N = floor(Int, L/n)
    R = L % n
    blocklengths = [N for i = 1:n]
    for i = 1:R
        blocklengths[i] += 1
    end
    return blocklengths
end

function surrogenerator(x::AbstractVector, bs::BlockShuffle, rng = Random.default_rng())
    L = length(x)
    bs.n < L || error("The number of blocks exceeds number of available points")
    Ls = get_uniform_blocklengths(L, bs.n)
    cs = cumsum(Ls)
    # will hold a rotation version of x
    xrot = similar(x)
    T = eltype(xrot)
    init = NamedTuple{(:L, :Ls, :cs, :xrot),Tuple{Int, Vector{Int}, Vector{Int}, Vector{T}}}((L, Ls, cs, xrot))
    return SurrogateGenerator(bs, x, init, rng)
end

function (bs::SurrogateGenerator{<:BlockShuffle})()
    # TODO: A circular custom array implementation would be much more elegant here
    L = bs.init.L
    Ls = bs.init.Ls
    cs = bs.init.cs
    xrot = bs.init.xrot
    n = bs.method.n
    x = bs.x

    # Just create a temporarily randomly shifted array, so we don't need to mess
    # with indexing twice.
    circshift!(xrot, x, rand(bs.rng, 1:L))

    # Block always must be shuffled (so ordered samples are not permitted)
    draw_order = zeros(Int, n)
    while any(draw_order .== 0) || all(draw_order .== 1:n)
       StatsBase.sample!(bs.rng, 1:n, draw_order, replace = false)
    end

    # The surrogate.
    # TODO: It would be faster to re-allocate, but blocks may
    # be of different sizes and are shifted, so indexing gets messy.
    # Just append for now.
    T = eltype(x)
    s = Vector{T}(undef, 0)
    sizehint!(s, L)

    startinds = [1; cs .+ 1]
    @inbounds for i in draw_order
        inds = startinds[i]:startinds[i]+Ls[i]-1
        append!(s, xrot[inds])
    end

    return s
end

#########################################################################
# CycleShuffle
#########################################################################
"""
    CycleShuffle(n::Int = 7, σ = 0.5) <: Surrogate

Cycle shuffled surrogates[^Theiler1995] that identify successive local peaks in the data and shuffle the
cycles in-between the peaks. Similar to [`BlockShuffle`](@ref), but here
the "blocks" are defined as follows:
1. The timeseries is smoothened via convolution with a Gaussian (`DSP.gaussian(n, σ)`).
2. Local maxima of the smoothened signal define the peaks, and thus the blocks in between them.
3. The first and last index of timeseries can never be peaks and thus signals that
   should have peaks very close to start or end of the timeseries may not perform well. In addition,
   points before the first or after the last peak are never shuffled.
3. The defined blocks are randomly shuffled as in [`BlockShuffle`](@ref).

CSS are used to test the null hypothesis that the signal is generated by a periodic
oscillator with no dynamical correlation between cycles,
i.e. the evolution of cycles is not deterministic.

See also [`PseudoPeriodic`](@ref).

[^Theiler1995]: J. Theiler, On the evidence for low-dimensional chaos in an epileptic electroencephalogram, [Phys. Lett. A 196](https://doi.org/10.1016/0375-9601(94)00856-K)
"""
struct CycleShuffle{T <: AbstractFloat} <: Surrogate
    n::Int
    σ::T
end
CycleShuffle(n = 7, σ = 0.5) = CycleShuffle{typeof(σ)}(n, σ)

function surrogenerator(x::AbstractVector, cs::CycleShuffle, rng = Random.default_rng())
    n, N = cs.n, length(x)
    g = DSP.gaussian(n, cs.σ)
    smooth = DSP.conv(x, g)
    r = length(smooth) - N
    smooth = iseven(r) ? smooth[r÷2+1:end-r÷2] : smooth[r÷2+1:end-r÷2-1]
    peaks = findall(i -> smooth[i-1] < smooth[i] && smooth[i] > smooth[i+1], 2:N-1)
    blocks = [collect(peaks[i]:peaks[i+1]-1) for i in 1:length(peaks)-1]
    init =  (blocks = blocks, s = copy(x), peak1 = peaks[1])
    SurrogateGenerator(cs, x, init, rng)
end

function (sg::SurrogateGenerator{<:CycleShuffle})()
    blocks, s, peak1 = sg.init
    x = sg.x
    shuffle!(sg.rng, blocks)
    i = peak1
    for b in blocks
        s[(0:length(b)-1) .+ i] .= @view x[b]
        i += length(b)
    end
    return s
end

#########################################################################
# Timeshift
#########################################################################
"""
    CircShift(n) <: Surrogate
Surrogates that are circularly shifted versions of the original timeseries.

`n` can be an integer (meaning to shift for `n` indices), or any vector of integers,
which which means that each surrogate is shifted by an integer,
selected randomly among the entries in `n`.
"""
struct CircShift{N} <: Surrogate
    n::N
end

function surrogenerator(x, sd::CircShift, rng = Random.default_rng())
    return SurrogateGenerator(sd, x, nothing, rng)
end

function (sg::SurrogateGenerator{<:CircShift})()
    s = random_shift(sg.method.n, sg.rng)
    return circshift(sg.x, s)
end

random_shift(n::Integer, rng) = n
random_shift(n::AbstractVector{<:Integer}, rng) = rand(rng, n)
