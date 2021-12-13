"""
    RRTPFlash{T}(;K0 = nothing,rtol= 1e-10,atol = 1e-10,max_iters = 100)

Method to solve non-reactive multicomponent flash problem by using successive substitution in the Rachford-Rice equation.

Only two phases are supported. if K0 is `nothing`, it will be calculated via the Wilson correlation.

The optimizer will stop at `max_iters` evaluations, when the absolute tolerance is less than `atol` or when the relative tolerance is less than `rtol`
"""
Base.@kwdef struct RRTPFlash{T} <: TPFlashMethod  
    K0::T = nothing
    rtol::Float64 = 1e-10
    atol::Float64 = 1e-10
    max_iters::Int = 100
end

#z is the original feed composition, x is a matrix with molar fractions, n is a matrix with molar amounts

function tp_flash_impl(model::EoSModel, p, T, n, method::RRTPFlash)
    if method.K0===nothing
        pure = split_model.(model)
        crit = crit_pure.(pure)
        Tc = [crit[i][1] for i ∈ @comps]
        pc = [crit[i][2] for i ∈ @comps]
        ω = acentric_factor.(pure)
        K0 = @. exp(log(pc/p)+5.373*(1+ω)*(1-Tc/T))
    end
    
    atol = method.atol
    rtol = method.rtol
    max_iters = method.max_iters

    x = zero(n)
    y = zero(n)
    α = zeros(eltype(K0),1)
    φ_α = zero(K0)
    φ_β = zero(K0)
    f(Kout,Kin) = RR_fixpoint(Kout,Kin,model,p,T,n,x,y,φ_α,φ_β,α)

    Solvers.fixpoint(f,K0,Solvers.SSFixPoint();atol,rtol,max_iters)
    α₀ = α[1]
    G = (gibbs_free_energy(model,p,T,x)*(1-α₀)+gibbs_free_energy(model,p,T,y)*α₀)/R̄/T
    
    X = hcat(x,y)'
    nvals = X.*[1-α₀
                α₀]
    return (X, nvals, G)
end

function RR_fixpoint(K1,K0,model,p,T,n,x,y,φ_α,φ_β,α)
    α₀ = rr_vle_vapor_fraction(K0,n)
    α[1] = α₀
    x = rr_flash_liquid!(x,K0,n,α₀)
    y .= K0 .* x
    φ_α .= fugacity_coefficient(model,p,T,x)
    φ_β .= fugacity_coefficient(model,p,T,y)
    K1 .= φ_α./φ_β
    K1
end

export RRTPFlash