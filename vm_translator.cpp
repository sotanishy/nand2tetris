#include <iostream>
#include <fstream>
#include <algorithm>
#include <string>
#include <vector>
#include <cctype>
#include <cassert>
#include <filesystem>


class Parser {
    std::ifstream infile;
    std::vector<std::string> commands;
    int idx = 0;

public:
    std::string currentCommand;
    Parser(std::string filename) : infile(filename) {
        assert(infile.is_open());

        std::string line;
        const std::string whitespace = " \t\r";
        while (std::getline(infile, line)) {
            // remove comments
            int i = line.find("//");
            if (i != std::string::npos) {
                line.erase(line.begin() + i, line.end());
            }

            // remove leading and trailing whitespaces
            auto start = line.find_first_not_of(whitespace);
            if (start == std::string::npos) continue;
            auto end = line.find_last_not_of(whitespace);
            line = line.substr(start, end - start + 1);

            // remove consecutive whitespaces
            line.erase(std::unique(line.begin(), line.end(), [&](char a, char b) {
                return isspace(a) && isspace(b);
            }), line.end());

            if (!line.empty()) {
                commands.push_back(line);
            }
        }

        infile.close();
    }

    bool hasMoreCommands() {
        return idx < commands.size();
    }

    void advance() {
        assert(hasMoreCommands());
        currentCommand = commands[idx++];
    }

    std::string commandType() {
        if (currentCommand.substr(0, 4) == "push") {
            return "C_PUSH";
        }
        if (currentCommand.substr(0, 3) == "pop") {
            return "C_POP";
        }
        if (currentCommand.substr(0, 5) == "label") {
            return "C_LABEL";
        }
        if (currentCommand.substr(0, 4) == "goto") {
            return "C_GOTO";
        }
        if (currentCommand.substr(0, 7) == "if-goto") {
            return "C_IF";
        }
        if (currentCommand.substr(0, 8) == "function") {
            return "C_FUNCTION";
        }
        if (currentCommand.substr(0, 6) == "return") {
            return "C_RETURN";
        }
        if (currentCommand.substr(0, 4) == "call") {
            return "C_CALL";
        }
        return "C_ARITHMETIC";
    }

    std::string arg1() {
        auto type = commandType();
        if (type == "C_ARITHMETIC") {
            return currentCommand;
        }
        const std::string whitespace = " \t";
        auto i = currentCommand.find_first_of(whitespace);
        if (type == "C_PUSH" || type == "C_POP" || type == "C_FUNCTION" || type == "C_CALL") {
            auto j = currentCommand.find_last_of(whitespace);
            return currentCommand.substr(i+1, j-i-1);
        }
        return currentCommand.substr(i+1);
    }

    int arg2() {
        const std::string whitespace = " \t";
        auto i = currentCommand.find_first_of(whitespace);
        auto j = currentCommand.find_last_of(whitespace);
        return std::stoi(currentCommand.substr(j+1));
    }
};


class CodeWriter {

    std::string filename;
    std::string functionName;
    std::ofstream outfile;
    int labelCnt = 0;
    int callCnt = 0;

public:
    CodeWriter(std::string path) {
        auto i = path.find_last_of("/");
        if (i == std::string::npos) i = -1;
        auto name = path.substr(i+1);
        outfile.open(path + "/" + name + ".asm");
    }

    void setFileName(std::string path) {
        auto i = path.find_last_of("/");
        if (i == std::string::npos) i = -1;
        auto name = path.substr(i+1, path.size()-i-4);
        filename = name;
    }

    void writeInit() {
        outfile << "@256\n";
        outfile << "D=A\n";
        outfile << "@SP\n";
        outfile << "M=D\n";
        writeCall("Sys.init", 0);
        // outfile << "@Sys.init\n";
        // outfile << "0;JMP\n";
    }

    void writeArithmetic(std::string command) {
        // unary
        if (command == "not") {
            outfile << "@SP\n";
            outfile << "A=M-1\n";
            outfile << "M=!M\n";
            return;
        } else if (command == "neg") {
            outfile << "@SP\n";
            outfile << "A=M-1\n";
            outfile << "M=-M\n";
            return;
        }

        // binary
        outfile << "@SP\n";
        outfile << "AM=M-1\n";
        outfile << "D=M\n";
        outfile << "@SP\n";
        outfile << "A=M-1\n";

        if (command == "add") {
            outfile << "M=M+D\n";
        } else if (command == "sub") {
            outfile << "M=M-D\n";
        } else if (command == "or") {
            outfile << "M=M|D\n";
        } else if (command == "and") {
            outfile << "M=M&D\n";
        } else {
            outfile << "D=M-D\n";
            outfile << "@TRUE" << labelCnt << "\n";
            if (command == "eq") {
                outfile << "D;JEQ\n";
            } else if (command == "gt") {
                outfile << "D;JGT\n";
            } else {  // lt
                outfile << "D;JLT\n";
            }
            outfile << "@SP\n";
            outfile << "A=M-1\n";
            outfile << "M=0\n";
            outfile << "@END" << labelCnt << "\n";
            outfile << "0;JMP\n";
            outfile << "(TRUE" << labelCnt << ")\n";
            outfile << "@SP\n";
            outfile << "A=M-1\n";
            outfile << "M=-1\n";
            outfile << "(END" << labelCnt << ")\n";
            ++labelCnt;
        }
    }

    void writePushPop(std::string command, std::string segment, int index) {
        if (command == "C_PUSH") {
            // read value
            if (segment == "constant") {
                outfile << "@" << index << "\n";
                outfile << "D=A\n";
            } else {
                getAddress(segment, index);
                outfile << "D=M\n";
            }

            // write to stack
            outfile << "@SP\n";
            outfile << "A=M\n";
            outfile << "M=D\n";

            // increment SP
            outfile << "@SP\n";
            outfile << "M=M+1\n";
        } else {
            // get address
            getAddress(segment, index);
            outfile << "D=A\n";
            outfile << "@R13\n";
            outfile << "M=D\n";

            // decrement SP and read from stack
            outfile << "@SP\n";
            outfile << "AM=M-1\n";
            outfile << "D=M\n";

            // write
            outfile << "@R13\n";
            outfile << "A=M\n";
            outfile << "M=D\n";
        }
    }

    void writeLabel(std::string label) {
        outfile << "(" << functionName << "$" << label << ")\n";
    }

    void writeGoto(std::string label) {
        outfile << "@" << functionName << "$" << label << "\n";
        outfile << "0;JMP\n";
    }

    void writeIf(std::string label) {
        outfile << "@SP\n";
        outfile << "AM=M-1\n";
        outfile << "D=M\n";
        outfile << "@" << functionName << "$" << label << "\n";
        outfile << "D;JNE" << "\n";
    }

    void writeCall(std::string functionName, int numArgs) {
        // push return address
        outfile << "@RETURN" << callCnt << "\n";
        outfile << "D=A\n";
        outfile << "@SP\n";
        outfile << "M=M+1\n";
        outfile << "A=M-1\n";
        outfile << "M=D\n";
        // push variables
        std::vector<std::string> labels = {"LCL", "ARG", "THIS", "THAT"};
        for (auto& label : labels) {
            outfile << "@" << label << "\n";
            outfile << "D=M\n";
            outfile << "@SP\n";
            outfile << "M=M+1\n";
            outfile << "A=M-1\n";
            outfile << "M=D\n";
        }
        // update arg
        outfile << "@" << (numArgs + 5) << "\n";
        outfile << "D=A\n";
        outfile << "@SP\n";
        outfile << "D=M-D\n";
        outfile << "@ARG\n";
        outfile << "M=D\n";
        // update lcl
        outfile << "@SP\n";
        outfile << "D=M\n";
        outfile << "@LCL\n";
        outfile << "M=D\n";
        // goto f
        outfile << "@" << functionName << "\n";
        outfile << "0;JMP\n";
        // return address
        outfile << "(RETURN" << callCnt << ")\n";
        ++callCnt;
    }

    void writeReturn() {
        outfile << "@5\n";
        outfile << "D=A\n";
        outfile << "@LCL\n";
        outfile << "A=M-D\n";
        outfile << "D=M\n";
        outfile << "@R13\n";
        outfile << "M=D\n";

        outfile << "@SP\n";
        outfile << "A=M-1\n";
        outfile << "D=M\n";
        outfile << "@ARG\n";
        outfile << "A=M\n";
        outfile << "M=D\n";

        outfile << "@ARG\n";
        outfile << "D=M+1\n";
        outfile << "@SP\n";
        outfile << "M=D\n";

        std::vector<std::string> labels = {"THAT", "THIS", "ARG", "LCL"};
        for (auto& label : labels) {
            outfile << "@LCL\n";
            outfile << "AM=M-1\n";
            outfile << "D=M\n";
            outfile << "@" << label << "\n";
            outfile << "M=D\n";
        }

        outfile << "@R13\n";
        outfile << "A=M;JMP\n";
    }

    void writeFunction(std::string functionName, int numLocals) {
        this->functionName = functionName;
        outfile << "(" << functionName << ")\n";

        outfile << "@R13\n";
        outfile << "M=0\n";
        outfile << "(" << functionName << "-INITLOOP)\n";
        outfile << "@R13\n";
        outfile << "D=M\n";
        outfile << "@" << numLocals << "\n";
        outfile << "D=D-A\n";
        outfile << "@" << functionName << "-INITLOOP-END\n";
        outfile << "D;JEQ\n";
        outfile << "@SP\n";
        outfile << "A=M\n";
        outfile << "M=0\n";
        outfile << "@SP\n";
        outfile << "M=M+1\n";
        outfile << "@R13\n";
        outfile << "M=M+1\n";
        outfile << "@" << functionName << "-INITLOOP\n";
        outfile << "0;JMP\n";
        outfile << "(" << functionName << "-INITLOOP-END)\n";
    }

    void close() {
        outfile.close();
    }

private:
    void getAddress(std::string segment, int index) {
        if (segment == "argument") {
            outfile << "@" << index << "\n";
            outfile << "D=A\n";
            outfile << "@ARG\n";
            outfile << "A=D+M\n";
        } else if (segment == "local") {
            outfile << "@" << index << "\n";
            outfile << "D=A\n";
            outfile << "@LCL\n";
            outfile << "A=D+M\n";
        } else if (segment == "static") {
            outfile << "@" << filename << "." << index << "\n";
        } else if (segment == "this") {
            outfile << "@" << index << "\n";
            outfile << "D=A\n";
            outfile << "@THIS\n";
            outfile << "A=D+M\n";
        } else if (segment == "that") {
            outfile << "@" << index << "\n";
            outfile << "D=A\n";
            outfile << "@THAT\n";
            outfile << "A=D+M\n";
        } else if (segment == "pointer") {
            outfile << "@R" << (3 + index) << "\n";
        } else if (segment == "temp") {
            outfile << "@R" << (5 + index) << "\n";
        }
    }
};

bool ends_with(const std::string& value, const std::string& ending) {
    if (ending.size() > value.size()) return false;
    return std::equal(ending.rbegin(), ending.rend(), value.rbegin());
}


int main(int argc, char *argv[]) {
    std::string path = argv[1];
    CodeWriter writer(path);
    writer.writeInit();
    for (auto& file : std::filesystem::directory_iterator(path)) {
        std::string filename = file.path();
        if (!ends_with(filename, ".vm")) continue;

        Parser parser(filename);
        writer.setFileName(filename);

        while (parser.hasMoreCommands()) {
            parser.advance();
            auto type = parser.commandType();
            if (type == "C_ARITHMETIC") {
                writer.writeArithmetic(parser.arg1());
            } else if (type == "C_PUSH" || type == "C_POP") {
                writer.writePushPop(type, parser.arg1(), parser.arg2());
            } else if (type == "C_LABEL") {
                writer.writeLabel(parser.arg1());
            } else if (type == "C_GOTO") {
                writer.writeGoto(parser.arg1());
            } else if (type == "C_IF") {
                writer.writeIf(parser.arg1());
            } else if (type == "C_FUNCTION") {
                writer.writeFunction(parser.arg1(), parser.arg2());
            } else if (type == "C_RETURN") {
                writer.writeReturn();
            } else if (type == "C_CALL") {
                writer.writeCall(parser.arg1(), parser.arg2());
            }
        }
    }

    writer.close();
    return 0;
}
