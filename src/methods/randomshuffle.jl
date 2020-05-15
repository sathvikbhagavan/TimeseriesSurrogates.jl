export RandomShuffle
"""
    RandomShuffle() <: Surrogate

A random constrained surrogate, generated by shifting values around.

This method destroys any linear
correlation in the signal, but preserves its amplitude distribution.
"""
struct RandomShuffle <: Surrogate end

function surrogenerator(x::AbstractVector, rf::RandomShuffle)
    return SurrogateGenerator(rf, x, nothing)
end

function (rf::SurrogateGenerator{<:RandomShuffle})()
    n = length(rf.x)
    rf.x[sample(1:n, n, replace = false)]
end