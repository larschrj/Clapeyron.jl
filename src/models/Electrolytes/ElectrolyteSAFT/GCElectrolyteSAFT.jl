abstract type SAFTgammaMieEModel <: ElectrolyteSAFTModel end

struct SAFTgammaMieE{T<:IdealModel,c<:SAFTModel,i<:IonModel,b,r<:RSPModel} <: SAFTgammaMieEModel
    components::Array{String,1}
    solvents::Union{Array{String,1},Array{Any,1}}
    salts::Array{String,1}
    ions::Array{String,1}
    icomponents::UnitRange{Int}
    isolvents::UnitRange{Int}
    isalts::UnitRange{Int}
    iions::UnitRange{Int}
    stoic_coeff::Array{Float64}
    idealmodel::T
    saftmodel::c
    ionicmodel::i
    bornmodel::b
    rspmodel::r
    absolutetolerance::Float64
    references::Array{String,1}
end

@registermodel SAFTgammaMieE
export SAFTgammaMieE

function SAFTgammaMieE(solvents,salts,ions; saftmodel=SAFTgammaMie,
    idealmodel = BasicIdeal,
    ionicmodel = GCMSA,
    RSPmodel = Schreckenberg,
    bornmodel = Born,
    userlocations=String[], 
    ideal_userlocations=String[],
     verbose=false)
    
    salt_groups = GroupParam(salts, ["Electrolytes/properties/salts.csv"]; verbose=verbose)
    ion_groups = GroupParam(salts, ["SAFT/SAFTgammaMie/"]; verbose=verbose)

    ngions = length(salt_groups.flattenedgroups)
    stoichiometric_coeff = zeros(length(salts),length(ions))
    for i in 1:length(salts)
        stoichiometric_coeff[i,:] = salt_groups.n_flattenedgroups[i]
    end

    components = deepcopy(ions)
    prepend!(components,solvents)

    isolvents = 1:length(solvents)
    iions = (length(solvents)+1):(length(solvents)+length(ions))
    isalts = (length(solvents)+1):(length(solvents)+length(salts))

    init_idealmodel = init_model(idealmodel,components,ideal_userlocations,verbose)
    init_SAFTmodel = saftmodel(components)
    init_Ionicmodel = ionicmodel(solvents,salts;RSPmodel=nothing,SAFTlocations=["SAFT/"*string(saftmodel)])
    if bornmodel !== nothing
        init_bornmodel = bornmodel(solvents,salts;RSPmodel=nothing,SAFTlocations=["SAFT/"*string(saftmodel)])
    else
        init_bornmodel = nothing
    end
    init_RSPmodel = RSPmodel(solvents,salts)

    salts = salt_groups.components
    ions = ion_groups.components
    components = deepcopy(salts)
    prepend!(components,solvents)
    icomponents = 1:length(components)

    references = String[]
    model = SAFTgammaMieE(components,solvents,salts,ions,icomponents,isolvents,isalts,iions,stoichiometric_coeff,init_idealmodel,init_SAFTmodel,init_Ionicmodel,init_bornmodel,init_RSPmodel,1e-12,references)
    return model
end

function a_res(model::SAFTgammaMieEModel, V, T, z,_data=@f(data))
    (data_saft,data_rsp) = _data
    return a_res(model.saftmodel,V,T,z,data_saft)+a_res(model.ionicmodel,V,T,z,data_rsp)+a_res(model.bornmodel,V,T,z,data_rsp)
end

function data(model::SAFTgammaMieEModel, V, T, z)
    data_saft = data(model.saftmodel,V,T,z)
    data_rsp = dielectric_constant(model.rspmodel,V,T,z,data_saft)
    return (data_saft,data_rsp)
end

function x0_volume(model::SAFTgammaMieE,p,T,z; phase = :unknown)
    phase = Symbol(phase)
    if phase === :unknown || is_liquid(phase)
        return 1.5*x0_volume_liquid(model.saftmodel,T,z)
    elseif is_vapour(phase)
        return 1.5*x0_volume_gas(model.saftmodel,p,T,z)
    elseif is_supercritical(phase)
     else
        error("unreachable state on x0_volume")
    end
end

function lb_volume(model::SAFTgammaMieE,z)
    seg = model.saftmodel.params.segment.values
    σ = model.saftmodel.params.sigma.values
    val = π/6*N_A*sum(z[i]*seg[i]*σ[i,i]^3 for i in 1:length(z))
    return val
end

function x0_sat_pure(model::SAFTgammaMieEModel,T,z=[0.5,0.5])
    vl = x0_volume(model.saftmodel,T,z,phase=:l)
    return (log10(vl),10)
end
function scale_sat_pure(model::SAFTgammaMieEModel,z=[0.5,0.5])
    p    = 1/p_scale(model.saftmodel,z)
    μ    = 1/R̄/T_scale(model.saftmodel,z)
    return p,μ
end