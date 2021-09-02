include("jacktokenizer.jl")
include("symboltable.jl")
include("vmwriter.jl")
include("compilationengine.jl")


function main()
    inpath = ARGS[1]
    files = []
    if endswith(inpath, ".jack")
        push!(files, inpath)
    else
        for file in readdir(inpath, join=true)
            if endswith(file, ".jack")
                push!(files, file)
            end
        end
    end

    for file in files
        outpath = file[1:end-5] * ".vm"

        tok = JackTokenizer(file)
        engine = CompilationEngine(tok, outpath)

        compileclass!(engine)

        close(tok)
        close(engine)
    end
end


main()