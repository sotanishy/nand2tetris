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
        while (std::getline(infile, line)) {
            // remove whitespace characters
            line.erase(std::remove_if(line.begin(), line.end(), isspace), line.end());
            // remove comments
            int i = line.find("//");
            if (i != std::string::npos) {
                line.erase(line.begin() + i, line.end());
            }

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
        if (currentCommand[0] == '@') {
            return "A_COMMAND";
        } else if (currentCommand[0] == '(') {
            return "L_COMMAND";
        } else {
            return "C_COMMAND";
        }
    }

    std::string symbol() {
        if (commandType() == "A_COMMAND") {
            return currentCommand.substr(1);
        } else {
            return currentCommand.substr(1, currentCommand.size() - 2);
        }
    }

    std::string dest() {
        int i = currentCommand.find('=');
        if (i == std::string::npos) {
            return "null";
        } else {
            return currentCommand.substr(0, i);
        }
    }

    std::string comp() {
        int i = currentCommand.find('=');
        if (i == std::string::npos) {
            i = -1;
        }
        int j = currentCommand.find(';');
        if (j == std::string::npos) {
            j = currentCommand.size();
        }
        return currentCommand.substr(i + 1, j - i - 1);
    }

    std::string jump() {
        int j = currentCommand.find(';');
        if (j == std::string::npos) {
            return "null";
        } else {
            return currentCommand.substr(j + 1);
        }
    }

    void reset() {
        idx = 0;
    }
};


class Code {
    const std::vector<std::string> destCommands = {
        "null", "M", "D", "MD", "A", "AM", "AD", "AMD"
    };

    const std::vector<std::string> jumpCommands = {
        "null", "JGT", "JEQ", "JGE", "JLT", "JNE", "JLE", "JMP"
    };

public:
    int dest(std::string s) {
        return std::find(destCommands.begin(), destCommands.end(), s) - destCommands.begin();
    }

    int comp(std::string s) {
        if (s == "0")   return 0b0101010;
        if (s == "1")   return 0b0111111;
        if (s == "-1")  return 0b0111010;
        if (s == "D")   return 0b0001100;
        if (s == "A")   return 0b0110000;
        if (s == "!D")  return 0b0001101;
        if (s == "!A")  return 0b0110001;
        if (s == "-D")  return 0b0001111;
        if (s == "-A")  return 0b0110011;
        if (s == "D+1") return 0b0011111;
        if (s == "A+1") return 0b0110111;
        if (s == "D-1") return 0b0001110;
        if (s == "A-1") return 0b0110010;
        if (s == "D+A") return 0b0000010;
        if (s == "D-A") return 0b0010011;
        if (s == "A-D") return 0b0000111;
        if (s == "D&A") return 0b0000000;
        if (s == "D|A") return 0b0010101;
        if (s == "M")   return 0b1110000;
        if (s == "!M")  return 0b1110001;
        if (s == "-M")  return 0b1110011;
        if (s == "M+1") return 0b1110111;
        if (s == "M-1") return 0b1110010;
        if (s == "D+M") return 0b1000010;
        if (s == "D-M") return 0b1010011;
        if (s == "M-D") return 0b1000111;
        if (s == "D&M") return 0b1000000;
        if (s == "D|M") return 0b1010101;
        return -1;
    }

    int jump(std::string s) {
        return std::find(jumpCommands.begin(), jumpCommands.end(), s) - jumpCommands.begin();
    }
};


class SymbolTable {
    std::map<std::string, int> table;

public:
    SymbolTable() {
        table["SP"]   = 0;
        table["LCL"]  = 1;
        table["ARG"]  = 2;
        table["THIS"] = 3;
        table["THAT"] = 4;
        for (int i = 0; i < 16; ++i) {
            table["R" + std::to_string(i)] = i;
        }
        table["SCREEN"] = 16384;
        table["KBD"]    = 24576;
    }

    void addEntry(std::string symbol, int address) {
        table[symbol] = address;
    }

    bool contains(std::string symbol) {
        return table.count(symbol);
    }

    int getAddress(std::string symbol) {
        return table[symbol];
    }
};


int main(int argc, char *argv[]) {
    std::string infilename = argv[1];
    std::string outfilename = infilename.substr(0, infilename.size() - 4) + ".hack";
    std::ofstream outfile;
    outfile.open(outfilename);

    Parser parser(infilename);
    Code code;
    SymbolTable table;

    // associate labels with addresses
    int address = 0;
    while (parser.hasMoreCommands()) {
        parser.advance();
        if (parser.commandType() == "L_COMMAND") {
            table.addEntry(parser.symbol(), address);
        } else {
            ++address;
        }
    }

    // convert each command to binary
    parser.reset();
    int varAddress = 16;
    while (parser.hasMoreCommands()) {
        parser.advance();
        auto type = parser.commandType();
        if (type == "A_COMMAND") {
            auto s = parser.symbol();
            int a = 0;
            if (std::isdigit(s[0])) {  // number
                a = std::stoi(s);
            } else if (table.contains(s)) {  // symbol that is already defined
                a = table.getAddress(s);
            } else {  // new symbol
                table.addEntry(s, varAddress);
                a = varAddress;
                ++varAddress;
            }
            std::bitset<16> bin(a);
            outfile << bin << std::endl;
        }
        if (type == "C_COMMAND") {
            int c = code.comp(parser.comp());
            int d = code.dest(parser.dest());
            int j = code.jump(parser.jump());
            std::bitset<16> bin((7 << 13) + (c << 6) + (d << 3) + j);
            outfile << bin << std::endl;
        }
    }

    outfile.close();
    return 0;
}
