export AAFT
"""
    AAFT()

An amplitude-adjusted-fourier-transform surrogate[^Theiler1992].

AAFT have the same linear correlation, or periodogram, and also
preserves the amplitude distribution of the original data.
"""
struct AAFT <: Surrogate end

function surrogenerator(x, method::AAFT)
    init = surrogenerator(x, RandomFourier(true))
    return SurrogateGenerator(method, x, init)
end

function (rf::SurrogateGenerator{<:AAFT})()
    x = rf.x
    xs = sort(x)
    s = rf.init()
    s[sortperm(s)] .= xs
    return s
end