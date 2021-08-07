#include <iostream>
#include <fstream>
#include <algorithm>
#include <string>
#include <vector>
#include <cctype>
#include <cassert>
#include <bitset>
#include <map>


class Parser {
    std::ifstream infile;
    std::vector<std::string> commands;
    std::string currentCommand;
    int idx;

public:
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

    std::string filepath;
    std::string filename;
    std::ofstream outfile;
    int labelCnt = 0;

public:
    void setFileName(std::string filepath) {
        this->filename = filename;
        outfile.open(filepath);
        auto i = filepath.find_last_of("/");
        if (i == std::string::npos) i = -1;
        filename = filepath.substr(i+1, filepath.size() - (i + 1) - 3);
    }


    void writeArithmetic(std::string command) {
        // unary
        if (command == "not") {
            outfile << "@SP" << std::endl;
            outfile << "A=M-1" << std::endl;
            outfile << "M=!M" << std::endl;
            return;
        } else if (command == "neg") {
            outfile << "@SP" << std::endl;
            outfile << "A=M-1" << std::endl;
            outfile << "M=-M" << std::endl;
            return;
        }

        // binary
        outfile << "@SP" << std::endl;
        outfile << "M=M-1" << std::endl;
        outfile << "A=M" << std::endl;
        outfile << "D=M" << std::endl;
        outfile << "@SP" << std::endl;
        outfile << "A=M-1" << std::endl;

        if (command == "add") {
            outfile << "M=M+D" << std::endl;
        } else if (command == "sub") {
            outfile << "M=M-D" << std::endl;
        } else if (command == "or") {
            outfile << "M=M|D" << std::endl;
        } else if (command == "and") {
            outfile << "M=M&D" << std::endl;
        } else {
            outfile << "D=M-D" << std::endl;
            outfile << "@TRUE" << labelCnt << std::endl;
            if (command == "eq") {
                outfile << "D;JEQ" << std::endl;
            } else if (command == "gt") {
                outfile << "D;JGT" << std::endl;
            } else {  // lt
                outfile << "D;JLT" << std::endl;
            }
            outfile << "@SP" << std::endl;
            outfile << "A=M-1" << std::endl;
            outfile << "M=0" << std::endl;
            outfile << "@END" << labelCnt << std::endl;
            outfile << "0;JMP" << std::endl;
            outfile << "(TRUE" << labelCnt << ")" << std::endl;
            outfile << "@SP" << std::endl;
            outfile << "A=M-1" << std::endl;
            outfile << "M=-1" << std::endl;
            outfile << "(END" << labelCnt << ")" << std::endl;
            ++labelCnt;
        }
    }

    void writePushPop(std::string command, std::string segment, int index) {
        if (command == "C_PUSH") {
            // read value
            if (segment == "constant") {
                outfile << "@" << index << std::endl;
                outfile << "D=A" << std::endl;
            } else {
                getAddress(segment, index);
                outfile << "D=M" << std::endl;
            }

            // write to stack
            outfile << "@SP" << std::endl;
            outfile << "A=M" << std::endl;
            outfile << "M=D" << std::endl;

            // increment SP
            outfile << "@SP" << std::endl;
            outfile << "M=M+1" << std::endl;
        } else {
            // get address
            getAddress(segment, index);
            outfile << "D=A" << std::endl;
            outfile << "@address" << std::endl;
            outfile << "M=D" << std::endl;

            // decrement SP and read from stack
            outfile << "@SP" << std::endl;
            outfile << "M=M-1" << std::endl;
            outfile << "A=M" << std::endl;
            outfile << "D=M" << std::endl;

            // write
            outfile << "@address" << std::endl;
            outfile << "A=M" << std::endl;
            outfile << "M=D" << std::endl;
        }
    }

    void close() {
        outfile.close();
    }

private:
    void getAddress(std::string segment, int index) {
        if (segment == "argument") {
            outfile << "@" << index << std::endl;
            outfile << "D=A" << std::endl;
            outfile << "@ARG" << std::endl;
            outfile << "A=D+M" << std::endl;
        } else if (segment == "local") {
            outfile << "@" << index << std::endl;
            outfile << "D=A" << std::endl;
            outfile << "@LCL" << std::endl;
            outfile << "A=D+M" << std::endl;
        } else if (segment == "static") {
            std::cout << "@" << filename << index << std::endl;
            outfile << "@" << filename << index << std::endl;
        } else if (segment == "this") {
            outfile << "@" << index << std::endl;
            outfile << "D=A" << std::endl;
            outfile << "@THIS" << std::endl;
            outfile << "A=D+M" << std::endl;
        } else if (segment == "that") {
            outfile << "@" << index << std::endl;
            outfile << "D=A" << std::endl;
            outfile << "@THAT" << std::endl;
            outfile << "A=D+M" << std::endl;
        } else if (segment == "pointer") {
            outfile << "@R" << (3 + index) << std::endl;
        } else if (segment == "temp") {
            outfile << "@R" << (5 + index) << std::endl;
        }
    }
};


int main(int argc, char *argv[]) {
    std::string infilename = argv[1];
    std::string outfilename = infilename.substr(0, infilename.size() - 3) + ".asm";

    Parser parser(infilename);
    CodeWriter writer;
    writer.setFileName(outfilename);

    while (parser.hasMoreCommands()) {
        parser.advance();
        auto type = parser.commandType();
        std::cout << type << std::endl;
        if (type == "C_ARITHMETIC") {
            writer.writeArithmetic(parser.arg1());
        } else if (type == "C_PUSH" || type == "C_POP") {
            writer.writePushPop(type, parser.arg1(), parser.arg2());
        }
    }

    writer.close();
    return 0;
}
