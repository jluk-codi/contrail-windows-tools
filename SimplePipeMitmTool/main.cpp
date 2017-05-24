#include <iostream>
#include "pipemitmtool.h"

using namespace std;

int main(int argc, char *argv[])
{
    if (argc != 3) {
        cerr << "Usage: " << argv[0] << " <agent_pipe> <extension_pipe>" << endl;
        return EXIT_FAILURE;
    }

    try {
        PipeMitmTool tool(argv[1], argv[2]);
        tool.Run();
    }
    catch (const std::exception &e) {
        cerr << "Error: " << e.what() << endl;
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
