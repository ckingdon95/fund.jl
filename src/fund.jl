using Distributions

include("SocioEconomicComponent.jl")
include("PopulationComponent.jl")
include("EmissionsComponent.jl")
include("GeographyComponent.jl")
include("ScenarioUncertaintyComponent.jl")
include("ClimateCO2Cycle.jl")
include("ClimateCH4CycleComponent.jl")

import StatsBase.modes
function modes(d::Truncated{Gamma})
    return [mode(d.untruncated)]
end

function convertparametervalue(pv)
    if !isa(pv,Float64)
        if beginswith(pv,"~") & endswith(pv,")")
            args_start_index = search(pv,'(')
            dist_name = pv[2:args_start_index-1]
            args = split(pv[args_start_index+1:end-1], ';')
            fixedargs = filter(i->!contains(i,"="),args)
            optargs = {split(i,'=')[1]=>split(i,'=')[2] for i in filter(i->contains(i,"="),args)}            
            
            if dist_name == "N"
                if length(fixedargs)!=2 error() end
                if length(optargs)>2 error() end
            
                basenormal = Normal(float64(fixedargs[1]),float64(fixedargs[2]))
            
                if length(optargs)==0
                    return basenormal
                else    
                    return Truncated(basenormal,
                        haskey(optargs,"min") ? float64(optargs["min"]) : -Inf,
                        haskey(optargs,"max") ? float64(optargs["max"]) : Inf)
                end            
            elseif beginswith(pv, "~Gamma(")
                if length(fixedargs)!=2 error() end
                if length(optargs)>2 error() end
                
                basegamma = Gamma(float64(fixedargs[1]),float64(fixedargs[2]))
                
                if length(optargs)==0
                    return basegamma
                else    
                    return Truncated(basegamma,
                        haskey(optargs,"min") ? float64(optargs["min"]) : -Inf,
                        haskey(optargs,"max") ? float64(optargs["max"]) : Inf)
                end            
            elseif beginswith(pv, "~Triangular(")
                # ERROR
                triang = TriangularDist(float64(fixedargs[3]), float64(fixedargs[2])-float64(fixedargs[3]))
                return triang
            else
                error("Unknown distribution")
            end
        elseif endswith(pv, "y")
            return int64(strip(pv,'y'))
        else
            error(pv)
        end
        return pv
    else
        return pv
    end    
end

function getbestguess(p)
    if isa(p, ContinuousUnivariateDistribution) then
        return modes(p)[1]
    else
        return p
    end
end

function prepparameters!(parameters)
    for i in parameters
        p = i[2]
        column_count = size(p,2)
        if column_count == 1
            parameters[i[1]] = getbestguess(convertparametervalue(p[1,1]))
        elseif column_count == 2    
            parameters[i[1]] = Float64[getbestguess(convertparametervalue(p[j,2])) for j in 1:size(p,1)]
        elseif column_count == 3    
            length_index1 = length(unique(p[:,1]))
            length_index2 = length(unique(p[:,2]))
            new_p = Array(Float64,length_index1,length_index2)
            cur_1 = 1
            cur_2 = 1
            for j in 1:size(p,1)
                new_p[cur_1,cur_2] = getbestguess(convertparametervalue(p[j,3]))
                cur_2 += 1
                if cur_2 > length_index2
                    cur_2 = 1
                    cur_1 += 1
                end
            end
            parameters[i[1]] = new_p
        end    
    end
end

function getfund(nsteps=566)
	regions = 16
    indices = {:time=>nsteps, :regions=>regions}
    
    # ---------------------------------------------
    # Create components
    # ---------------------------------------------

    c_population = population(indices)
    c_geography = geography(indices)
    c_socioeconomic = socioeconomic(indices)
    c_emissions = emissions(indices)
    c_scenariouncertainty = scenariouncertainty(indices)
    c_climateco2cycle = climateco2cycle(indices)
    c_climatech4cycle = climatech4cycle(indices)

    comps::Vector{ComponentState} = [c_scenariouncertainty, c_geography, c_socioeconomic, c_socioeconomic, c_emissions, c_climateco2cycle, c_climatech4cycle]

    # ---------------------------------------------
    # Load parameters
    # ---------------------------------------------
    files = readdir("../data")
    parameters = {lowercase(splitext(file)[1]) => readdlm(joinpath("../data",file), ',') for file in files};

    prepparameters!(parameters)

    # ---------------------------------------------
    # Set parameters
    # ---------------------------------------------

	c_socioeconomic.Parameters.eloss = ones(nsteps, regions) * 0.0
	c_socioeconomic.Parameters.sloss = ones(nsteps, regions) * 0.0
	c_socioeconomic.Parameters.mitigationcost = ones(nsteps, regions) * 0.0

    c_geography.Parameters.landloss = zeros(nsteps,regions)

    c_climateco2cycle.Parameters.temp = zeros(nsteps)
    #c_climatech4cycle.Parameters.lifech4 = 12.

    # ---------------------------------------------
    # Connect parameters to variables
    # ---------------------------------------------

    c_population.Parameters.pgrowth = c_scenariouncertainty.Variables.pgrowth    

    c_socioeconomic.Parameters.area = c_geography.Variables.area
    c_socioeconomic.Parameters.globalpopulation = c_population.Variables.globalpopulation
    c_socioeconomic.Parameters.populationin1 = c_population.Variables.populationin1
    c_socioeconomic.Parameters.population = c_population.Variables.population  
    c_socioeconomic.Parameters.pgrowth = c_scenariouncertainty.Variables.pgrowth
    c_socioeconomic.Parameters.ypcgrowth = c_scenariouncertainty.Variables.ypcgrowth

    c_emissions.Parameters.income = c_socioeconomic.Variables.income
    c_emissions.Parameters.population = c_population.Variables.population
    c_emissions.Parameters.forestemm = c_scenariouncertainty.Variables.forestemm
    c_emissions.Parameters.aeei = c_scenariouncertainty.Variables.aeei
    c_emissions.Parameters.acei = c_scenariouncertainty.Variables.acei
    c_emissions.Parameters.ypcgrowth = c_scenariouncertainty.Variables.ypcgrowth
    #c_emissions.Parameters.pgrowth = c_scenariouncertainty.Variables.pgrowth

    c_climateco2cycle.Parameters.mco2 = c_emissions.Variables.mco2
    c_climatech4cycle.Parameters.globch4 = c_emissions.Variables.globch4

    # ---------------------------------------------
    # Load remaining parameters from file
    # ---------------------------------------------

    println(parameters["lifech4"])

    for c in comps
        for name in names(c.Parameters)
            if isa(c,climatech4cycle)
                println(name)
                println(isdefined(c.Parameters, name))
            end
            if !isdefined(c.Parameters, name)
                setfield!(c.Parameters,name,parameters[lowercase(string(name))])
            end
        end
    end

    println(c_climatech4cycle.Parameters.lifech4)

    # ---------------------------------------------
    # Return model
    # ---------------------------------------------
    
    return comps
end

m = getfund()

for c in m
    resetvariables(c)
end

run(566, m)