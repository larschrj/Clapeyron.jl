const vdWParam = ABCubicParam

abstract type vdWModel <: ABCubicModel end

struct vdW{T <: IdealModel,α,c,M} <: vdWModel
    components::Array{String,1}
    alpha::α
    mixing::M
    translation::c
    params::vdWParam
    idealmodel::T
    references::Array{String,1}
end

export vdW

"""
    vdW(components;
    idealmodel = BasicIdeal,
    alpha = NoAlpha,
    mixing = vdW1fRule,
    activity = nothing,
    translation = NoTranslation,
    userlocations = String[],
    ideal_userlocations = String[],
    alpha_userlocations = String[],
    mixing_userlocations = String[],
    activity_userlocations = String[],
    translation_userlocations = String[],
    reference_state = nothing,
    verbose = false)

## Input parameters
- `Tc`: Single Parameter (`Float64`) - Critical Temperature `[K]`
- `Pc`: Single Parameter (`Float64`) - Critical Pressure `[Pa]`
- `Mw`: Single Parameter (`Float64`) - Molecular Weight `[g/mol]`
- `k`: Pair Parameter (`Float64`) (optional)
- `l`: Pair Parameter (`Float64`) (optional)

## Model Parameters
- `Tc`: Single Parameter (`Float64`) - Critical Temperature `[K]`
- `Pc`: Single Parameter (`Float64`) - Critical Pressure `[Pa]`
- `Mw`: Single Parameter (`Float64`) - Molecular Weight `[g/mol]`
- `a`: Pair Parameter (`Float64`)
- `b`: Pair Parameter (`Float64`)

## Input models
- `idealmodel`: Ideal Model
- `alpha`: Alpha model
- `mixing`: Mixing model
- `activity`: Activity Model, used in the creation of the mixing model.
- `translation`: Translation Model

## Description

van der Wals Equation of state.

```
P = RT/(V-Nb) + a•α(T)/V²
```

## Model Construction Examples
```julia
# Using the default database
model = vdW("water") #single input
model = vdW(["water","ethanol"]) #multiple components
model = vdW(["water","ethanol"], idealmodel = ReidIdeal) #modifying ideal model
model = vdW(["water","ethanol"],alpha = SoaveAlpha) #modifying alpha function
model = vdW(["water","ethanol"],translation = RackettTranslation) #modifying translation
model = vdW(["water","ethanol"],mixing = KayRule) #using another mixing rule
model = vdW(["water","ethanol"],mixing = WSRule, activity = NRTL) #using advanced EoS+gᴱ mixing rule

# Passing a prebuilt model

my_alpha = SoaveAlpha(["ethane","butane"],userlocations = Dict(:acentricfactor => [0.1,0.2]))
model =  vdW(["ethane","butane"],alpha = my_alpha)

# User-provided parameters, passing files or folders

model = vdW(["neon","hydrogen"]; userlocations = ["path/to/my/db","cubic/my_k_values.csv"])

# User-provided parameters, passing parameters directly

model = vdW(["neon","hydrogen"];
        userlocations = (;Tc = [44.492,33.19],
                        Pc = [2679000, 1296400],
                        Mw = [20.17, 2.],
                        acentricfactor = [-0.03,-0.21]
                        k = [0. 0.18; 0.18 0.], #k,l can be ommited in single-component models.
                        l = [0. 0.01; 0.01 0.])
                    )
```

## References

1. van der Waals JD. Over de Continuiteit van den Gasen Vloeistoftoestand. PhD thesis, University of Leiden; 1873

"""
vdW

function vdW(components;
    idealmodel = BasicIdeal,
    alpha = NoAlpha,
    mixing = vdW1fRule,
    activity = nothing,
    translation = NoTranslation,
    userlocations = String[],
    ideal_userlocations = String[],
    alpha_userlocations = String[],
    mixing_userlocations = String[],
    activity_userlocations = String[],
    translation_userlocations = String[],
    reference_state = nothing,
    verbose = false)
    formatted_components = format_components(components)
    params = getparams(formatted_components, ["properties/critical.csv", "properties/molarmass.csv","SAFT/PCSAFT/PCSAFT_unlike.csv"];
        userlocations = userlocations,
        verbose = verbose,
        ignore_missing_singleparams = __ignored_crit_params(alpha))

    k = get(params,"k",nothing)
    l = get(params,"l",nothing)
    pc = params["Pc"]
    Mw = params["Mw"]
    Tc = params["Tc"]
    acentricfactor = get(params,"acentricfactor",nothing)

    init_mixing = init_model(mixing,components,activity,mixing_userlocations,activity_userlocations,verbose)
    a = PairParam("a",formatted_components,zeros(length(Tc)))
    b = PairParam("b",formatted_components,zeros(length(Tc)))
    init_idealmodel = init_model(idealmodel,components,ideal_userlocations,verbose)
    init_alpha = init_alphamodel(alpha,components,acentricfactor,alpha_userlocations,verbose)
    init_translation = init_model(translation,components,translation_userlocations,verbose)
    packagedparams = ABCubicParam(a,b,Tc,pc,Mw)
    references = String[]
    model = vdW(formatted_components,init_alpha,init_mixing,init_translation,packagedparams,init_idealmodel,references)
    recombine_cubic!(model,k,l)
    return model
end

function ab_consts(::Type{<:vdWModel})
    Ωa =  27/64
    Ωb =  1/8
    return Ωa,Ωb
end

cubic_Δ(model::vdWModel,z) = (0.0,0.0)

function a_res(model::vdWModel, V, T, z,_data = data(model,V,T,z))
    n,ā,b̄,c̄ = _data
    RT⁻¹ = 1/(R̄*T)
    ρt = (V/n+c̄)^(-1) # translated density
    ρ  = n/V
    return -log(1+(c̄-b̄)*ρ) - ā*ρt*RT⁻¹
    #
    #return -log(V-n*b̄) - ā*n/(R̄*T*V) + log(V)
end

crit_pure(model::vdWModel) = crit_pure_tp(model)

const CHEB_COEF_L_VDW= ([0.9316136201036852,-0.03865225088424542,-0.0008661148627486168,-3.8336595966463605e-05,-1.930441992932519e-06,-5.810841478132156e-08,6.379356029539984e-09,4.0565692471794534e-10,-3.1201431022198634e-10,-3.4029466744467385e-11,1.369238750159596e-11,1.18192261533423e-12,-7.751924102628038e-13,6.175615574477433e-15,4.091171845743702e-14,-6.980527267330672e-15,-1.2559397966072083e-15,1.4641066137244252e-15,-3.8163916471489756e-17],
[0.8455034879915954,-0.04802256898834967,-0.0015470962415359973,-7.972501988821878e-05,-4.017234579128948e-06,-2.921741757144769e-07,-2.6298690877779585e-08,-1.3988705679923719e-09,-1.5143918064008943e-10,-1.6808554548219945e-11,-1.6921186674068167e-13,-1.6256440638073855e-13,-9.825473767932635e-15,7.077671781985373e-16,-3.608224830031759e-16,-7.632783294297951e-16,-4.163336342344337e-17,8.257283745649602e-16,1.3877787807814457e-17],
[0.7327617276279949,-0.06612960981729517,-0.0032780016312522198,-0.00026019391083406673,-2.6595986463442967e-05,-3.184060496402852e-06,-4.0508839448810674e-07,-5.4371095223326726e-08,-7.554792333386295e-09,-1.076694275403689e-09,-1.5675695463901462e-10,-2.3183531483450537e-11,-3.4755739952707643e-12,-5.273004255457181e-13,-8.064382495120981e-14,-1.3183898417423734e-14,-1.9290125052862095e-15,4.0245584642661925e-16,-5.898059818321144e-17],
[0.6166811517612045,-0.04839066994648989,-0.0021672975061474767,-0.00017570976987404258,-1.8519040533800102e-05,-2.208561613849247e-06,-2.82949510460595e-07,-3.8035669329417043e-08,-5.291587154565569e-09,-7.554387740360546e-10,-1.1004187144836308e-10,-1.6289976312311438e-11,-2.4432955658681976e-12,-3.709324514211687e-13,-5.671157987663378e-14,-9.346690088563037e-15,-1.3600232051658168e-15,3.677613769070831e-16,-3.122502256758253e-17],
[0.5328306974405083,-0.034453741516764766,-0.0014682721939933072,-0.00012182552205808328,-1.2945521315733954e-05,-1.5482578362285837e-06,-1.9873352891802698e-07,-2.6746483347550587e-08,-3.724136381222376e-09,-5.319946913551199e-10,-7.753041264546567e-11,-1.1481385286948864e-11,-1.7225665338571616e-12,-2.6155466681387907e-13,-4.00304789316408e-14,-6.696032617270475e-15,-9.43689570931383e-16,3.885780586188048e-16,-1.734723475976807e-17],
[0.4734609830190833,-0.02424735785371843,-0.0010133644361935874,-8.529016931251368e-05,-9.098505499984672e-06,-1.089985510512731e-06,-1.4004471942871688e-07,-1.8859509249430362e-08,-2.627095759683007e-09,-3.7540060296437083e-10,-5.472236552783727e-11,-8.105231763533283e-12,-1.2161383011743965e-12,-1.8476886687324168e-13,-2.827946210537391e-14,-4.829470157119431e-15,-7.181755190543981e-16,4.2674197509029455e-16,6.938893903907228e-18],
[0.4317586705206012,-0.016998875614382822,-0.0007071969216258488,-6.0002743216675675e-05,-6.413721659864063e-06,-7.690254281537967e-07,-9.885537948645107e-08,-1.3316815754282896e-08,-1.855412701950998e-09,-2.6517297732620015e-10,-3.8659075940472576e-11,-5.726488727653134e-12,-8.592571099086399e-13,-1.30593452718486e-13,-1.9970136655445003e-14,-3.4555691641457997e-15,-4.891920202254596e-16,3.5041414214731503e-16,-6.938893903907228e-18],
[0.4025301670915846,-0.011913454752168377,-0.0004965958130950694,-4.231862747736473e-05,-4.528099139627234e-06,-5.431755606445654e-07,-6.984058851383645e-08,-9.409722008524302e-09,-1.311186739044734e-09,-1.8740799190286594e-10,-2.732347334499785e-11,-4.0475123253003176e-12,-6.073752611968075e-13,-9.242259735309233e-14,-1.4089424071883627e-14,-2.5500435096859064e-15,-3.0878077872387166e-16,3.9898639947466563e-16,-3.122502256758253e-17],
[0.3820369525637211,-0.008358544107590068,-0.00034987653550601003,-2.988469717726469e-05,-3.1993345159762876e-06,-3.8386783924454493e-07,-4.936325082721682e-08,-6.651310394817367e-09,-9.268700876252645e-10,-1.3248298638690592e-10,-1.93161493744487e-11,-2.861148817867587e-12,-4.2926079357741287e-13,-6.528458329491116e-14,-9.988537774674455e-15,-2.067790383364354e-15,-2.740863092043355e-16,2.3592239273284576e-16,-1.734723475976807e-17],
[0.3676497053323325,-0.005873143997041752,-0.0002469394057881408,-2.11177904382992e-05,-2.261380224737042e-06,-2.7135935164526725e-07,-3.489748082521893e-08,-4.70234896160493e-09,-6.552974517182175e-10,-9.366743838890024e-11,-1.3656992203792129e-11,-2.0231802344561345e-12,-3.0342742207700724e-13,-4.5678738569421284e-14,-7.029099524658022e-15,-1.4190038033490282e-15,-1.9081958235744878e-16,2.706168622523819e-16,0.0],
[0.3575341743707003,-0.004132704229989258,-0.0001744465560134939,-1.4927613207975365e-05,-1.5987220087325393e-06,-1.918530817199282e-07,-2.4673554255283392e-08,-3.324766725820716e-09,-4.633303775369857e-10,-6.62290049191494e-11,-9.656359045706608e-12,-1.4302690976020216e-12,-2.1446733278196461e-13,-3.235953172087136e-14,-4.947431353485854e-15,-8.743006318923108e-16,-1.249000902703301e-16,2.706168622523819e-16,-1.3877787807814457e-17],
[0.35041246164734846,-0.0029115644765456902,-0.0001232928553679749,-1.0553674979200955e-05,-1.130355650916931e-06,-1.3565108163485218e-07,-1.744588612809239e-08,-2.3508600899280196e-09,-3.2761145879467435e-10,-4.682861390326032e-11,-6.827677312415403e-12,-1.011458278243893e-12,-1.5187850976872141e-13,-2.3189783426857957e-14,-3.4139358007223564e-15,-1.1136924715771102e-15,2.7755575615628914e-17,5.134781488891349e-16,-1.231653667943533e-16],
[0.3453929468556045,-0.002053229816890382,-8.715997446502935e-05,-7.461959008286251e-06,-7.992427072806008e-07,-9.591642778292164e-08,-1.2335767615723192e-08,-1.662271872232557e-09,-2.3165206211595013e-10,-3.311351193246992e-11,-4.8279401310136194e-12,-7.147511749128199e-13,-1.0711917464156784e-13,-1.676089822488791e-14,-2.4980018054066022e-15,-2.983724378680108e-16,-5.551115123125783e-17,2.393918396847994e-16,-3.469446951953614e-18],
[0.34185203830414934,-0.0014490000408041367,-6.162384665049647e-05,-5.276183904001641e-06,-5.651359926590882e-07,-6.782196396853957e-08,-8.722585896625557e-09,-1.1753904204103716e-09,-1.6380120870795878e-10,-2.3415179517538576e-11,-3.413873350677221e-12,-5.057065877167588e-13,-7.568598525686809e-14,-1.1497747198774277e-14,-1.7867651802561113e-15,-9.783840404509192e-16,-3.8163916471489756e-17,8.673617379884035e-16,4.5102810375396984e-17],
[0.33935254842481155,-0.001023145052791774,-4.35719527140041e-05,-3.7307483613316372e-06,-3.99606561996696e-07,-4.7956948610178296e-08,-6.167757610198166e-09,-8.311229968138711e-10,-1.1582452358327444e-10,-1.6557800269767498e-11,-2.4139960863589494e-12,-3.5761671401957074e-13,-5.354744425645208e-14,-9.089951014118469e-15,-1.2524703496552547e-15,3.0531133177191805e-16,1.0408340855860843e-16,1.1796119636642288e-15,7.45931094670027e-17],
[0.3375873324362272,-0.0007227370941488807,-3.080906979128009e-05,-2.638010219744441e-06,-2.8256276612612097e-07,-3.391053622625595e-08,-4.361249632267583e-09,-5.876913226898761e-10,-8.18994629059322e-11,-1.1706968727764888e-11,-1.7064231971897215e-12,-2.5467475350815505e-13,-3.8767600241129685e-14,-3.230055112268815e-15,-1.0408340855860843e-16,-3.2959746043559335e-16,4.718447854656915e-16,-2.255140518769849e-16,-5.828670879282072e-16],
[0.33634024377980126,-0.0005106811254640582,-2.1784964224096787e-05,-1.8653452834756223e-06,-1.9980143188894073e-07,-2.3978314021844138e-08,-3.083862751968036e-09,-4.15558362026891e-10,-5.791153667722426e-11,-8.274964047316757e-12,-1.206382216345503e-12,-1.7613341340982913e-13,-2.653433028854124e-14,-5.748873599387139e-15,-8.881784197001252e-16,-1.9359513991901167e-15,3.8163916471489756e-17,2.723515857283587e-15,2.0122792321330962e-16],
[0.3354589771042352,-0.0003609193232701237,-1.540417623366666e-05,-1.318994892206965e-06,-1.412807294452756e-07,-1.695521064867811e-08,-2.180618217245689e-09,-2.9384074340388366e-10,-4.09495146125316e-11,-5.853536405586723e-12,-8.535151752031567e-13,-1.2840770113875521e-13,-1.8620521791135047e-14,8.777700788442644e-16,-1.1449174941446927e-16,-3.2612801348363973e-16,-7.28583859910259e-17,-3.642919299551295e-16,-6.418476861114186e-17],
[0.33483610810587444,-0.00025511470266906255,-1.0892355099323403e-05,-9.326690283625871e-07,-9.990048497124371e-08,-1.198913999328477e-08,-1.5419303056596334e-09,-2.0778637838114733e-10,-2.8956462228002522e-11,-4.139157766536172e-12,-6.029898802495381e-13,-8.481410018745805e-14,-1.3000017728970192e-14,-4.253541963095131e-15,-4.961309141293668e-16,-3.400058012914542e-16,2.42861286636753e-16,3.427813588530171e-15,2.5847379792054426e-16],
[0.33439581408722335,-0.00018034628968470814,-7.702043156140176e-06,-6.594961682766798e-07,-7.064028084702301e-08,-8.477598685552312e-09,-1.0903128885852986e-09,-1.4692143335270913e-10,-2.047259237136778e-11,-2.9264958512076333e-12,-4.246672458130263e-13,-6.597153379139797e-14,-1.4110240753595349e-14,-4.624772786954168e-15,1.7104373473131318e-15,-5.898059818321144e-17,1.7243151351209463e-15,-4.9439619065339e-15,-2.6107588313450947e-15],
[0.3340845498332141,-0.0001275005089778833,-5.4461616414841485e-06,-4.6633405621082646e-07,-4.995021219908469e-08,-5.994557138871981e-09,-7.709631162644559e-10,-1.0388243043557566e-10,-1.4478303972387252e-11,-2.0819145019057572e-12,-3.017829042217812e-13,-3.418099137064701e-14,-5.575401251789458e-15,-7.563394355258879e-16,4.440892098500626e-16,6.05765437811101e-15,1.4814538484841933e-15,1.1372847108503947e-14,9.454242944073599e-16],
[0.33372633790262984,-0.0002626883492755708,-5.29284541328362e-05,-2.2974444177099873e-05,-1.2993976963245751e-05,-8.462102700595303e-06,-6.027003266417114e-06,-4.5715123450466855e-06,-3.63574215444043e-06,-3.001990554286904e-06,-2.5563835181763306e-06,-2.2347435701189355e-06,-1.9987819929248585e-06,-1.8246487468939754e-06,-1.6970267719754184e-06,-1.6059148805584733e-06,-1.544804257274518e-06,-1.5096230361819063e-06,-7.490669524691518e-07])

chebyshev_coef_l(model::vdWModel) = CHEB_COEF_L_VDW

chebyshev_Tmin_l(model::vdWModel) = (0.02962962962962963,0.0962962962962963,0.16296296296296295,0.22962962962962963,0.26296296296296295,0.2796296296296296,0.287962962962963,0.29212962962962963,0.29421296296296295,0.2952546296296296,0.295775462962963,0.29603587962962963,0.29616608796296295,0.2962311921296296,0.296263744212963,0.29628002025462963,0.29628815827546295,0.2962922272858796,0.296294261791088,0.29629527904369213,0.2962957876699942,0.29629604198314524)
chebyshev_Tmax_l(model::vdWModel) = (0.0962962962962963,0.16296296296296295,0.22962962962962963,0.26296296296296295,0.2796296296296296,0.287962962962963,0.29212962962962963,0.29421296296296295,0.2952546296296296,0.295775462962963,0.29603587962962963,0.29616608796296295,0.2962311921296296,0.296263744212963,0.29628002025462963,0.29628815827546295,0.2962922272858796,0.296294261791088,0.29629527904369213,0.2962957876699942,0.29629604198314524,0.2962962962962963)

chebyshev_Trange_l(model::vdWModel) = (0.02962962962962963,0.0962962962962963,0.16296296296296295,0.22962962962962963,0.26296296296296295,0.2796296296296296,0.287962962962963,0.29212962962962963,0.29421296296296295,0.2952546296296296,0.295775462962963,0.29603587962962963,0.29616608796296295,0.2962311921296296,0.296263744212963,0.29628002025462963,0.29628815827546295,0.2962922272858796,0.296294261791088,0.29629527904369213,0.2962957876699942,0.29629604198314524,0.2962962962962963)

CHEB_COEF_V_VDW = ([2.2489373895047762e-11,3.688517107894903e-11,2.0894583452709746e-11,8.476583933451082e-12,2.530366544413405e-12,5.637212489418141e-13,9.363230492731065e-14,1.1333103251162971e-14,9.33519994749376e-16,4.1362278059373704e-17,-4.84986420418459e-19,-1.65650780002939e-19,-4.018942009006866e-21,4.891126970541962e-22,2.0177374582077214e-23,-1.6609931787362484e-24,-6.522933053091502e-26,3.332148463653554e-27,-4.030290364774149e-27],
[2.6379937128657115e-09,3.780798221053315e-09,1.6044278594036214e-09,4.4331172895958845e-10,8.361702765680484e-11,1.0880537367567157e-11,9.447363806147374e-13,4.7714402398820264e-14,5.233241126040141e-16,-8.52742988949115e-17,-3.190159512313497e-18,1.504383250318862e-19,7.755246373275116e-21,-3.752718106348484e-22,-1.6549266806029178e-23,-6.308867757850729e-25,-7.270142102516845e-26,1.3231658626580658e-24,1.0339757656912846e-25],
[5.488117599580858e-07,8.246318599119535e-07,3.7495338087883065e-07,1.0860523684389838e-07,2.0169156352224874e-08,2.2464415506045487e-09,1.0692430180323234e-10,-5.062128204483255e-12,-7.086734785957356e-13,1.8598468871247458e-14,3.791438263524812e-15,-1.5845682631384665e-16,-1.6139528628166535e-17,1.4249482656836079e-18,2.1099309474696353e-20,-9.177568896275842e-21,2.61595868719895e-23,-1.4175807747627512e-22,-2.0384832220603676e-22],
[9.198583413591418e-05,0.0001323418019880509,5.269589299645468e-05,1.1673085614775962e-05,1.217520790883859e-06,-5.281166426031512e-09,-9.943118098154909e-09,2.878024017224007e-10,1.005351237026266e-10,-8.653088852547337e-12,-5.972466878192423e-13,1.4256395010153724e-13,-4.811359136869256e-15,-1.1177042446084331e-15,1.499644436891851e-16,-3.257172554437806e-18,-1.0356698315857932e-18,1.720668023008306e-19,-4.5858893159939854e-21],
[0.004754326043670642,0.005941275521721304,0.001655883437830305,0.00017737301927121552,-2.1044306045037264e-06,-2.446112805967309e-07,1.8602953134177618e-07,-1.3107585751750864e-08,-4.852484754108938e-10,4.195957567265955e-10,-6.078596600608724e-11,3.1842478720250315e-12,7.401045989713535e-13,-2.1153502669131463e-13,2.655919239960905e-14,-7.025291264527167e-16,-4.339586958009012e-16,1.0583507269353032e-16,-1.1385816876992305e-17],
[0.036691881497644734,0.027888941391814935,0.003974549212687695,0.0002715266512105239,2.3797626951819117e-05,3.422813454436401e-06,3.9210812700050945e-07,5.451342389246796e-08,7.630582787377174e-09,1.0642235220240798e-09,1.580515761670509e-10,2.3087444716435312e-11,3.480158435736902e-12,5.272167251380022e-13,8.05698823630463e-14,1.2436666280146724e-14,1.932265111803666e-15,3.380542373809803e-16,4.8030156241107846e-17],
[0.09807361548934067,0.03140331546583538,0.0023425610291630955,0.0001748056758866679,1.8480646404825905e-05,2.210790222235623e-06,2.8286844096486047e-07,3.8038013492475153e-08,5.2915361961961005e-09,7.554389618198709e-10,1.1004225222016606e-10,1.6290535326951572e-11,2.443793865186672e-12,3.706427526006806e-13,5.67323965583455e-14,8.677086826835989e-15,1.353951672999898e-15,3.0357660829594124e-16,3.209238430557093e-17],
[0.15708895435350148,0.026473214602337546,0.0015096794373112487,0.00012167462420701724,1.2944662426067101e-05,1.5482932451916717e-06,1.987328542198824e-07,2.6746493632726076e-08,3.7241364748974437e-09,5.31994449361195e-10,7.753074050820263e-11,1.1481976827654172e-11,1.7230132251522257e-12,2.6130746871855237e-13,4.001920322904695e-14,6.041174505089231e-15,9.497611030973019e-16,2.697495005143935e-16,2.2985086056692694e-17],
[0.20464143088991663,0.02037941444367245,0.0010233677370924937,8.527036209769225e-05,9.098480032524933e-06,1.0899862908780866e-06,1.4004471174042243e-07,1.8859509351779047e-08,2.627095993870676e-09,3.754003670419781e-10,5.472267257389252e-11,8.105812895897735e-12,1.2166136154068141e-12,1.8451386252227309e-13,2.827425793494598e-14,4.210173876195711e-15,6.886852199627924e-16,2.3418766925686896e-16,-3.469446951953614e-18],
[0.2405791169899757,0.015094667641419904,0.0007096529008297752,6.0000237077412547e-05,6.413720740528275e-06,7.690254484101627e-07,9.885537929910093e-08,1.331681581152877e-08,1.8554129257303265e-09,2.651727292607431e-10,3.8659369108740016e-11,5.727075064188014e-12,8.597150769062978e-13,1.303020191745219e-13,1.9978810272824887e-14,2.831068712794149e-15,4.666406150377611e-16,2.8622937353617317e-16,1.1275702593849246e-17],
[0.26696049015665074,0.010968687650483065,0.0004972041585612832,4.231831304510672e-05,4.5280991004606475e-06,5.431755610851852e-07,6.98405883993447e-08,9.409722064035453e-09,1.3111869472115512e-09,1.874077785318784e-10,2.732374916603053e-11,4.048053559024822e-12,6.078245545770855e-13,9.212769436217627e-14,1.4092893518835581e-14,1.93421667571414e-15,3.0184188481996443e-16,2.393918396847994e-16,3.642919299551295e-17],
[0.2860388317887753,0.007887981700325456,0.00035002791393559315,2.9884657820819505e-05,3.199334514061153e-06,3.8386783914393097e-07,4.936325074221537e-08,6.651310417368772e-09,9.268703131393163e-10,1.3248275219923666e-10,1.9316418256587475e-11,2.8617264807850873e-12,4.2971702585159477e-13,6.502437477351464e-14,9.985068327722502e-15,1.4536982728685643e-15,2.463307335887066e-16,3.937822290467352e-16,1.3877787807814457e-17],
[0.2997208026355501,0.005638316441575676,0.00024697716181993484,2.1117785516101134e-05,2.2613802245774473e-06,2.713593515168977e-07,3.4897480762768884e-08,4.702349017116081e-09,6.552976390683529e-10,9.366720593595446e-11,1.3657262820654381e-11,2.023738815415399e-12,3.0388191962771316e-13,4.5428938388880624e-14,7.004813395994347e-15,8.222589276130066e-16,1.6653345369377348e-16,3.5041414214731503e-16,1.214306433183765e-17],
[0.3094842337937238,0.004015403659434553,0.00017445598394503006,1.4927612592627315e-05,1.598722008659681e-06,1.918530815638031e-07,2.4673554175486112e-08,3.3247667709235262e-09,4.633306065204845e-10,6.622874818007496e-11,9.656650479250573e-12,1.4308033924326224e-12,2.1489754420400686e-13,3.2085445411667024e-14,4.933553565678039e-15,3.157196726277789e-16,1.0408340855860843e-16,3.5735303605122226e-16,-3.469446951953614e-18],
[0.3164300310090633,0.002852942467447068,0.00012329521096597976,1.0553674902311072e-05,1.1303556508510115e-06,1.356510815030132e-07,1.744588605176456e-08,2.35086013503083e-09,3.276116843087262e-10,4.6828395328102346e-11,6.8279583376185116e-12,1.0120272675440134e-12,1.523364767663793e-13,2.2915697117653622e-14,3.4208746946262636e-15,5.169475958410885e-16,-5.898059818321144e-17,1.0755285551056204e-16,1.1275702593849246e-16],
[0.3213616216197866,0.002023925878183369,8.716056319137827e-05,7.461958998724455e-06,7.992427072528452e-07,9.5916427661491e-08,1.2335767528987018e-08,1.662271934682602e-09,2.316522806911081e-10,3.3113272540630234e-11,4.828210747875872e-12,7.152750614025649e-13,1.0757367219227376e-13,1.6459056340067946e-14,2.4875934645507414e-15,-2.8796409701215e-16,1.734723475976807e-17,4.0245584642661925e-16,8.673617379884035e-18],
[0.32485857647079686,0.0014343498375109544,6.162399381036757e-05,5.27618390287754e-06,5.651359926105159e-07,6.782196385404782e-08,8.722585830706064e-09,1.1753904828604167e-09,1.6380142034422285e-10,2.3414967881274507e-11,3.4141717231150892e-12,5.062547603351675e-13,7.616823838318965e-14,1.1230599783473849e-14,1.7832957333041577e-15,3.7470027081099033e-16,6.938893903907228e-18,-2.185751579730777e-16,-4.336808689942018e-17],
[0.3273360915970311,0.0010158203926102366,4.357198950115382e-05,3.7307483612414316e-06,3.9960656192036814e-07,4.795694848874765e-08,6.167757533870333e-09,8.311230384472346e-10,1.1582474909732632e-10,1.6557578225162572e-11,2.414311806031577e-12,3.581648866379794e-13,5.39950029132541e-14,8.791578576250458e-15,1.2351231148954867e-15,-8.847089727481716e-16,-1.1102230246251565e-16,-5.551115123125783e-16,-7.112366251504909e-17],
[0.3290903207332936,0.0007190748744181456,3.080907898764598e-05,2.6380102197860744e-06,2.8256276604285424e-07,3.391053608747807e-08,4.3612495316536215e-09,5.876913573843456e-10,8.189969188943103e-11,1.1706732805372155e-11,1.7067146307336856e-12,2.552090483387559e-13,3.920475055707584e-14,2.9976021664879227e-15,1.0408340855860843e-16,-2.7755575615628914e-16,-4.891920202254596e-16,8.708311849403572e-16,5.863365348801608e-16],
[0.3303319160946099,0.0005088500431879688,2.178496652304948e-05,1.8653452835380724e-06,1.998014318195518e-07,2.39783138934746e-08,3.0838626687013093e-09,4.1555842447693614e-10,5.791174831348833e-11,8.2747732277344e-12,1.2066458943138514e-12,1.7669546381604562e-13,2.7006175074006933e-14,5.43315392675936e-15,8.916478666520788e-16,1.3530843112619095e-15,-5.898059818321144e-17,-2.0643209364124004e-15,-2.0990154059319366e-16],
[0.3312104361553831,0.0003600037890292736,1.5404176808297282e-05,1.3189948922485983e-06,1.412807293793561e-07,1.695521050990023e-08,2.1806181235706212e-09,2.9384080932337575e-10,4.094972624879567e-11,5.85331783042875e-12,8.538031393001688e-13,1.289766904388756e-13,1.903685542536948e-14,-1.1622647289044608e-15,9.367506770274758e-17,-2.6020852139652106e-16,5.551115123125783e-17,9.957312752106873e-16,5.551115123125783e-17],
[0.331831931854538,0.00025465693727301855,1.0892355242906465e-05,9.326690283938122e-07,9.990048491226311e-08,1.1989139896140255e-08,1.541930194637331e-09,2.0778642001451075e-10,2.8956680803160495e-11,4.138932252484295e-12,6.032882526874062e-13,8.537268114672258e-14,1.3461454173580023e-14,3.986394547794703e-15,4.787836793695988e-16,-2.6020852139652106e-16,-2.7755575615628914e-16,-2.789435349370706e-15,-2.7755575615628914e-16],
[0.33227153922563357,0.0001801174074178534,7.702043191917113e-06,6.594961683530076e-07,7.064028076028683e-08,8.477598543304987e-09,1.0903128191963596e-09,1.469214784555195e-10,2.0472828293760514e-11,2.9262668677088044e-12,4.2494827101613453e-13,6.652664530371055e-14,1.4550860516493458e-14,4.3680337125096e-15,-1.700029006457271e-15,-5.412337245047638e-16,-1.762479051592436e-15,5.571931804837504e-15,2.624636619152909e-15],
[0.33258246015637705,0.00012738606795224122,5.446161650365933e-06,4.663340562940932e-07,4.995021213663464e-08,5.9945570209107846e-09,7.70963039936623e-10,1.0388249288562079e-10,1.4478501730863513e-11,2.081692457300832e-12,3.0205005163708165e-13,3.4736102882959585e-14,6.043776590303196e-15,4.822531263215524e-16,-4.3021142204224816e-16,-6.647460359943125e-15,-1.502270530195915e-15,-1.0724060528488621e-14,-9.384854005034526e-16],
[0.3329404432049817,0.00026257390832178443,5.292845414168676e-05,2.2974444177158854e-05,1.2993976963165954e-05,8.462102700470403e-06,6.027003266333847e-06,4.571512345112605e-06,3.6357421546520663e-06,3.001990554068329e-06,2.5563835184851114e-06,2.2347435706775165e-06,1.9987819933516005e-06,1.8246487466094807e-06,1.69702677196501e-06,1.6059148799860146e-06,1.5448042572502318e-06,1.5096230368202845e-06,7.490669524708865e-07])

chebyshev_coef_v(model::vdWModel) = CHEB_COEF_V_VDW
chebyshev_Trange_v(model::vdWModel) = (0.02962962962962963,0.03796296296296296,0.0462962962962963,0.06296296296296297,0.0962962962962963,0.16296296296296295,0.22962962962962963,0.26296296296296295,0.2796296296296296,0.287962962962963,0.29212962962962963,0.29421296296296295,0.2952546296296296,0.295775462962963,0.29603587962962963,0.29616608796296295,0.2962311921296296,0.296263744212963,0.29628002025462963,0.29628815827546295,0.2962922272858796,0.296294261791088,0.29629527904369213,0.2962957876699942,0.29629604198314524,0.2962962962962963)

const CHEB_COEF_P_VDW = ([8.369016487003571e-13,1.3838182749488314e-12,8.006631877160537e-13,3.3527912014616007e-13,1.043509859614108e-13,2.4518354339464807e-14,4.362454910953413e-15,5.800290149785568e-16,5.5246311563342216e-17,3.341712352615597e-18,6.943507182585673e-20,-6.6172300100790814e-21,-4.799249815587726e-22,8.197853768324654e-24,1.6972506557505968e-24,-1.4268299756055458e-26,-5.664810160392086e-27,4.437342591868191e-31,-1.4685138788754898e-28],
[1.1901434626227093e-10,1.7361780173369773e-10,7.639416392753658e-11,2.219331080562664e-11,4.468985012784936e-12,6.345623163747038e-13,6.256832040916454e-14,3.9794258615342e-15,1.2126532982344795e-16,-2.510288446235168e-18,-3.1189177665897616e-19,-3.0550813286427195e-22,6.384476478410435e-22,2.6783405454063793e-25,-1.4724057241513977e-24,-5.563678192342752e-26,1.0097419586828951e-27,6.679443056687351e-26,5.4526065768876336e-27],
[3.341667610526653e-08,5.118389108542411e-08,2.4371256768154856e-08,7.57899054003236e-09,1.5635438033324503e-09,2.0715013642702e-10,1.5165995758982126e-11,1.6314454982752663e-13,-6.017223931292203e-14,-1.9704412673913643e-15,2.8051398344015177e-16,7.022929896522875e-18,-1.5199614910962848e-18,1.1958046052493347e-20,7.00911492046808e-21,-4.237329623030918e-22,-3.863191954564062e-23,-1.1166938269465874e-23,-1.2818068320304144e-23],
[8.410724206747044e-06,1.2481631400263709e-05,5.378159443205515e-06,1.3704527561658967e-06,1.9136168235190198e-07,8.957711663130537e-09,-9.462672897450059e-10,-6.968811539371602e-11,1.0243849900317855e-11,2.337729169280951e-13,-1.1494530386099005e-13,5.3160592525426036e-15,7.530730564512324e-16,-1.1431990843247566e-16,2.805445086019535e-18,7.988918627843267e-19,-1.0295338058018748e-19,7.210533399624742e-21,5.761312966431838e-22],
[0.0006802593682753608,0.0009003332567452364,0.0002880297751978097,4.118964226458961e-05,7.986981798077676e-07,-2.628431475282669e-07,1.4516582903911464e-08,1.5647152494426528e-09,-4.1929621787396065e-10,3.8557343395626107e-11,8.368753107866514e-13,-8.31125296022126e-13,1.3326079144488354e-13,-8.864161253017153e-15,-8.83270499045497e-16,3.3879136780332834e-16,-4.8188763160481214e-17,2.9076523496871995e-18,3.8719993601362204e-19],
[0.015871052250174933,0.017373046113870208,0.003617191914161977,0.00018958352208271672,-1.4572937633430827e-05,7.218425887058066e-07,2.6419947263015497e-08,-1.4409436469961143e-08,2.6380419456436925e-09,-3.4860393171849517e-10,3.335912880024321e-11,-1.2239621615490678e-12,-4.035014645542914e-13,1.3487363894996995e-13,-2.72259564068969e-14,4.280375966864147e-15,-5.359753439682091e-16,5.147249813874932e-17,-1.531435568635775e-18])

chebyshev_coef_p(model::vdWModel) = CHEB_COEF_P_VDW
chebyshev_Trange_p(model::vdWModel) = (0.02962962962962963,0.03796296296296296,0.0462962962962963,0.06296296296296297,0.0962962962962963,0.16296296296296295,0.2962962962962963)

#for saturation_temperature
chebyshev_prange_T(model::vdWModel) = (2.1344790044356395e-15, 3.490532706109917e-12, 3.963898362480436e-10, 1.1833677572230098e-7, 2.7840281613627896e-5, 0.001910363598204112, 0.03703703703703703)
