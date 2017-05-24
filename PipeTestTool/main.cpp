#include <iostream>
#include "utils.h"
#include "pipetesttool.h"
#include <Windows.h>

using namespace std;

int usage(const char *app_name)
{
    cerr << "Usage: " << app_name << " <pipe> [timer_timeout_ms]" << endl;
    return EXIT_FAILURE;
}

int main(int argc, char *argv[])
{
    unsigned long timer_timeout_ms = 0;

    if (argc != 2 && argc != 3)
        return usage(argv[0]);

    if (argc == 3) {
        try {
            timer_timeout_ms = stoul(argv[2]);
        }
        catch(const std::exception &e) {
            cerr << "Timeout conversion error: " << e.what() << endl;
            return usage(argv[0]);
        }
    }

    wstring wide_name = Utils::StrToWide(argv[1]);

    try {
        PipeTestTool tool(wide_name.c_str(), timer_timeout_ms);
        tool.Run();
    }
    catch (const std::exception &e) {
        cerr << "Error: " << e.what() << endl;
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
