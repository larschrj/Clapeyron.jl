function ePCSAFT(solvents,ions; 
    idealmodel = BasicIdeal,
    neutralmodel = pharmaPCSAFT,
    ionmodel = DH,
    RSPmodel = ConstRSP,
    userlocations=String[], 
    ideal_userlocations=String[],
     verbose=false)
    components = deepcopy(ions)
    prepend!(components,solvents)

    params = getparams(format_components(components), ["Electrolytes/properties/charges.csv"]; userlocations=userlocations, verbose=verbose)
    charge = params["charge"].values

    icomponents = 1:length(components)

    neutral_path = DB_PATH.*["/SAFT/PCSAFT","/SAFT/PCSAFT/pharmaPCSAFT"]

    init_idealmodel = init_model(idealmodel,components,ideal_userlocations,verbose)
    init_neutralmodel = neutralmodel(components;userlocations=userlocations,verbose=verbose)
    init_ionmodel = ionmodel(solvents,ions;RSPmodel=RSPmodel,userlocations=append!(userlocations,neutral_path),verbose=verbose)

    for i in ions
        init_neutralmodel.params.epsilon[i] = 0.
    end

    references = String[]
    components = format_components(components)
    model = ESElectrolyte(components,icomponents,charge,init_idealmodel,init_neutralmodel,init_ionmodel,references)
    return model
end

export ePCSAFT