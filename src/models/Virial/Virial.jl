abstract type VirialModel <: EoSModel end

struct SecondVirial{I,T} <: VirialModel
    idealmodel::I
    model::T
end

@registermodel SecondVirial

function SecondVirial(model;idealmodel = BasicIdeal())
    return SecondVirial{typeof(idealmodel),typeof(model)}(idealmodel,model)
end

function a_res(model::SecondVirial,V,T,z)
    B = second_virial_coefficient(model,T,z)
    return - B/V
end

lb_volume(model::SecondVirial,z = SA[1.0]) = zero(eltype(z))

second_virial_coefficient(model::SecondVirial,T,z=SA[1.0]) =  second_virial_coefficient(model.model,T,z)


