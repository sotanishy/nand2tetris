function writepush(io::IOStream, segment::String, index::Int)
    write(io, "push $segment $index\n")
end


function writepop(io::IOStream, segment::String, index::Int)
    write(io, "pop $segment $index\n")
end


function writearithmetic(io::IOStream, command::String)
    write(io, "$command\n")
end


function writelabel(io::IOStream, label::String)
    write(io, "label $label\n")
end


function writegoto(io::IOStream, label::String)
    write(io, "goto $label\n")
end


function writeif(io::IOStream, label::String)
    write(io, "if-goto $label\n")
end


function writecall(io::IOStream, name::String, nargs::Int)
    write(io, "call $name $nargs\n")
end


function writefunction(io::IOStream, name::String, nlocals::Int)
    write(io, "function $name $nlocals\n")
end


function writereturn(io::IOStream)
    write(io, "return\n")
end