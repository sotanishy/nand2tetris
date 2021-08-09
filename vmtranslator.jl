@enum CommandType c_arithmetic c_push c_pop c_label c_goto c_if c_function c_return c_call


# given an input file, return a list of commands without comments and whitespaces
function readcommands(path::String)::Vector{String}
    commands = []
    open(path, "r") do file
        for line in eachline(file)
            # remove comments
            res = findfirst("//", line)
            if !isnothing(res)
                i = res[1]
                line = line[1:i-1]
            end

            # remove unnecessary whitespaces
            line = join(split(line), " ")

            if !isempty(line)
                push!(commands, line)
            end
        end
    end
    commands
end


# get the type of the given command
function commandtype(command::String)::CommandType
    startswith(command, "push")     && return c_push
    startswith(command, "pop")      && return c_pop
    startswith(command, "label")    && return c_label
    startswith(command, "goto")     && return c_goto
    startswith(command, "if-goto")  && return c_if
    startswith(command, "function") && return c_function
    startswith(command, "return")   && return c_return
    startswith(command, "call")     && return c_call
    c_arithmetic
end


# get the first argument of the given command
function arg1(command::String)::String
    commandtype(command) == c_arithmetic && return command
    split(command)[2]
end


# get the second argument of the given command
function arg2(command::String)::Int
    parse(Int, split(command)[3])
end


# translate vm into asm and write to the file
mutable struct CodeWriter
    io::IOStream
    filename::String
    functionname::String
    labelcnt::Int
    callcnt::Int

    function CodeWriter(path::String)
        name = basename(rstrip(path, '/'))
        new(open(joinpath(path, "$name.asm"), "w"), "null", "null", 0, 0)
    end
end


close(writer::CodeWriter) = Base.close(writer.io)


function setfilename!(writer::CodeWriter, filename::String)
    writer.filename = split(filename, ".")[1]
end


# write initialization code
function writeinit(writer::CodeWriter)
    code = """
    @256
    D=A
    @SP
    M=D
    """
    write(writer.io, code)
    writecall!(writer, "Sys.init", 0)
end


# write arithmetic command
function writearithmetic!(writer::CodeWriter, command::String)
    # unary
    if command in ("not", "neg")
        code = """
        @SP
        A=M-1
        $(command == "not" ? "M=!M" : "M=-M")
        """
        write(writer.io, code)
        return
    end

    # binary
    code = """
    @SP
    AM=M-1
    D=M
    @SP
    A=M-1
    """

    if command == "add"
        code *= "M=M+D\n"
    elseif command == "sub"
        code *= "M=M-D\n"
    elseif command == "or"
        code *= "M=M|D\n"
    elseif command == "and"
        code *= "M=M&D\n"
    else
        code *= """
        D=M-D
        @TRUE$(writer.labelcnt)
        D;J$(uppercase(command))
        @SP
        A=M-1
        M=0
        @END$(writer.labelcnt)
        0;JMP
        (TRUE$(writer.labelcnt))
        @SP
        A=M-1
        M=-1
        (END$(writer.labelcnt))
        """
        writer.labelcnt += 1
    end
    write(writer.io, code)
end


# write push and pop command
function writepushpop(writer::CodeWriter, type::CommandType, segment::String, index::Int)
    if type == c_push
        code = ""
        # get the value to push
        if segment == "constant"
            code = """
            @$index
            D=A
            """
        else
            code *= getaddress(writer, segment, index)
            code *= "D=M\n"
        end
        # write to stack and increment SP
        code *= """
        @SP
        A=M
        M=D
        @SP
        M=M+1
        """
    else
        code = getaddress(writer, segment, index) * """
        D=A
        @R13
        M=D
        @SP
        AM=M-1
        D=M
        @R13
        A=M
        M=D
        """
    end
    write(writer.io, code)
end


# write label command
function writelabel(writer::CodeWriter, label::String)
    code = "($(writer.functionname)\$$label)\n"
    write(writer.io, code)
end


# write goto command
function writegoto(writer::CodeWriter, label::String)
    code = """
    @$(writer.functionname)\$$label
    0;JMP
    """
    write(writer.io, code)
end


# write if command
function writeif(writer::CodeWriter, label::String)
    code = """
    @SP
    AM=M-1
    D=M
    @$(writer.functionname)\$$label
    D;JNE
    """
    write(writer.io, code)
end


# write function command
function writefunction!(writer::CodeWriter, functionname::String, numlocals::Int)
    writer.functionname = functionname
    code = """
    ($functionname)
    @R13
    M=0
    ($functionname-INITLOOP)
    @R13
    D=M
    @$numlocals
    D=D-A
    @$functionname-INITLOOP-END
    D;JEQ
    @SP
    A=M
    M=0
    @SP
    M=M+1
    @R13
    M=M+1
    @$functionname-INITLOOP
    0;JMP
    ($functionname-INITLOOP-END)
    """
    write(writer.io, code)
end


# write return command
function writereturn(writer::CodeWriter)
    code = """
    @5
    D=A
    @LCL
    A=M-D
    D=M
    @R13
    M=D
    @SP
    A=M-1
    D=M
    @ARG
    A=M
    M=D
    @ARG
    D=M+1
    @SP
    M=D
    """
    for label in ["THAT", "THIS", "ARG", "LCL"]
        code *= """
        @LCL
        AM=M-1
        D=M
        @$label
        M=D
        """
    end
    code *= """
    @R13
    A=M;JMP
    """
    write(writer.io, code)
end


# write call command
function writecall!(writer::CodeWriter, functionname::String, numargs::Int)
    code = """
    @RETURN$(writer.callcnt)
    D=A
    @SP
    M=M+1
    A=M-1
    M=D
    """
    for label in ["LCL", "ARG", "THIS", "THAT"]
        code *= """
        @$label
        D=M
        @SP
        M=M+1
        A=M-1
        M=D
        """
    end
    code *= """
    @$(numargs + 5)
    D=A
    @SP
    D=M-D
    @ARG
    M=D
    @SP
    D=M
    @LCL
    M=D
    @$functionname
    0;JMP
    (RETURN$(writer.callcnt))
    """
    writer.callcnt += 1
    write(writer.io, code)
end


# get the address of the specified segment and index
# and store it to the A register
function getaddress(writer::CodeWriter, segment::String, index::Int)::String
    if segment == "static"
        "@$(writer.filename).$index\n"
    elseif segment == "pointer"
        "@R$(3 + index)\n"
    elseif segment == "temp"
        "@R$(5 + index)\n"
    else
        symbol = if segment == "argument"
            "ARG"
        elseif segment == "local"
            "LCL"
        elseif segment == "this"
            "THIS"
        else
            "THAT"
        end
        """
        @$index
        D=A
        @$symbol
        A=D+M
        """
    end
end


function main()
    path = ARGS[1]
    writer = CodeWriter(path)
    writeinit(writer)

    for file in readdir(path)
        !endswith(file, ".vm") && continue

        commands = readcommands(joinpath(path, file))
        setfilename!(writer, file)

        for command in commands
            type = commandtype(command)
            if type == c_arithmetic
                writearithmetic!(writer, arg1(command))
            elseif type in (c_push, c_pop)
                writepushpop(writer, type, arg1(command), arg2(command))
            elseif type == c_label
                writelabel(writer, arg1(command))
            elseif type == c_goto
                writegoto(writer, arg1(command))
            elseif type == c_if
                writeif(writer, arg1(command))
            elseif type == c_function
                writefunction!(writer, arg1(command), arg2(command))
            elseif type == c_return
                writereturn(writer)
            elseif type == c_call
                writecall!(writer, arg1(command), arg2(command))
            end
        end
    end
    close(writer)
end


main()