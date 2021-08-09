@enum CommandType a_command l_command c_command


# given an input file, return a list of commands without comments and whitespaces
function readcommands(path::String)::Vector{String}
    commands = []
    open(path, "r") do file
        for line in eachline(file)
            # remove whitespace
            line = filter(x -> !isspace(x), line)

            # remove comments
            res = findfirst("//", line)
            if !isnothing(res)
                i = res[1]
                line = line[1:i-1]
            end

            if !isempty(line)
                push!(commands, line)
            end
        end
    end
    commands
end


# get the type of the given command
function commandtype(command::String)::CommandType
    if command[1] == '@'
        a_command
    elseif command[1] == '('
        l_command
    else
        c_command
    end
end


# get the symbol of the given command
# the command should be of either a_command or l_command
function symbol(command::String)::String
    if commandtype(command) == a_command
        command[2:end]
    else
        command[2:end-1]
    end
end


# get the dest part of the given command
# the command should be of c_command
function dest(command::String)::String
    i = findfirst(isequal('='), command)
    if isnothing(i)
        "null"
    else
        command[1:i-1]
    end
end


# get the comp of the given command
# the command should be of C_COMMAND
function comp(command::String)::String
    i = findfirst(isequal('='), command)
    if isnothing(i)
        i = 0
    end
    j = findfirst(isequal(';'), command)
    if isnothing(j)
        j = length(command) + 1
    end
    command[i+1:j-1]
end


# get the jump part of the given command
# the command should be of C_COMMAND
function jump(command::String)::String
    j = findfirst(isequal(';'), command)
    if isnothing(j)
        "null"
    else
        command[j+1:end]
    end
end


# convert dest to binary
function convertdest(s::String)::UInt16
    bin = 0
    'M' in s && (bin += 1)
    'D' in s && (bin += 2)
    'A' in s && (bin += 4)
    bin
end


# convert comp to binary
function convertcomp(s::String)::UInt16
    s == "0"   && return 0b0101010
    s == "1"   && return 0b0111111
    s == "-1"  && return 0b0111010
    s == "D"   && return 0b0001100
    s == "A"   && return 0b0110000
    s == "!D"  && return 0b0001101
    s == "!A"  && return 0b0110001
    s == "-D"  && return 0b0001111
    s == "-A"  && return 0b0110011
    s == "D+1" && return 0b0011111
    s == "A+1" && return 0b0110111
    s == "D-1" && return 0b0001110
    s == "A-1" && return 0b0110010
    s == "D+A" && return 0b0000010
    s == "D-A" && return 0b0010011
    s == "A-D" && return 0b0000111
    s == "D&A" && return 0b0000000
    s == "D|A" && return 0b0010101
    s == "M"   && return 0b1110000
    s == "!M"  && return 0b1110001
    s == "-M"  && return 0b1110011
    s == "M+1" && return 0b1110111
    s == "M-1" && return 0b1110010
    s == "D+M" && return 0b1000010
    s == "D-M" && return 0b1010011
    s == "M-D" && return 0b1000111
    s == "D&M" && return 0b1000000
    s == "D|M" && return 0b1010101
end


# convert jump to binary
function convertjump(s::String)::UInt16
    findfirst(isequal(s), ["null", "JGT", "JEQ", "JGE", "JLT", "JNE", "JLE", "JMP"]) - 1
end


function main()
    inpath = ARGS[1]
    i = findlast(isequal('.'), inpath)
    outpath = inpath[1:i-1] * ".hack"

    commands = readcommands(inpath)

    # symbol table with predefined names
    symbols = Dict{String,UInt16}(
        "SP" => 0,
        "LCL" => 1,
        "ARG" => 2,
        "THIS" => 3,
        "THAT" => 4,
        "SCREEN" => 16384,
        "KBD" => 24576
    )
    for i in 0:15
        symbols["R" * string(i)] = i
    end

    open(outpath, "w") do file
        # associate labels with addresses
        address = 0
        for command in commands
            if commandtype(command) == l_command
                symbols[symbol(command)] = address
            else
                address += 1
            end
        end

        # convert each command to binary
        address::UInt16 = 16
        for command in commands
            type = commandtype(command)
            type == l_command && continue
            if type == a_command
                s = symbol(command)
                bin = if isdigit(s[1])
                    parse(UInt16, s)
                else
                    if !haskey(symbols, s)
                        symbols[s] = address
                        address += 1
                    end
                    symbols[s]
                end
            else
                c = convertcomp(comp(command))
                d = convertdest(dest(command))
                j = convertjump(jump(command))
                bin = (UInt16(7) << 13) + (c << 6) + (d << 3) + j
            end
            write(file, bitstring(bin) * "\n")
        end
    end
end


main()