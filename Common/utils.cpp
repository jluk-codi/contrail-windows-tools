#include "utils.h"
#include <sstream>
#include <iomanip>
#include <Windows.h>

std::string Utils::GetFormattedWindowsErrorMsg()
{
    const DWORD error = GetLastError();
    LPSTR message = NULL;

    const DWORD flags = (FORMAT_MESSAGE_ALLOCATE_BUFFER |
                         FORMAT_MESSAGE_FROM_SYSTEM |
                         FORMAT_MESSAGE_IGNORE_INSERTS);
    const DWORD lang_id = MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT);
    const DWORD ret = FormatMessageA(flags, NULL, error, lang_id, (LPSTR)message, 0, NULL);

    std::ostringstream sstr;

    if (ret != 0) {
        sstr << message << " ";
    }

    sstr << "[" << error << "]";
    LocalFree(message);

    return sstr.str();
}

std::string Utils::DataToHex(const char *data, size_t length)
{
    std::ostringstream sstr;

    for (int i = 0; i < length; ++i) {
        int value = static_cast<int>(static_cast<unsigned char>(data[i]));
        sstr << std::hex << std::setw(2) << std::setfill('0') << value  << " ";
    }

    return sstr.str();
}

std::string Utils::DataToHex(const std::vector<char> &data)
{
    return Utils::DataToHex(data.data(), data.size());
}

std::wstring Utils::StrToWide(const std::string &str)
{
    const int buf_size = MultiByteToWideChar(CP_ACP, MB_PRECOMPOSED, str.c_str(), -1, NULL, 0);
    if (buf_size == 0) {
        throw std::runtime_error("Error converting string: " + Utils::GetFormattedWindowsErrorMsg());
    }

    const auto wide_name = std::unique_ptr<wchar_t[]>(new wchar_t[buf_size]);

    if (!MultiByteToWideChar(CP_ACP, MB_PRECOMPOSED, str.c_str(), -1, wide_name.get(), buf_size)) {
        throw std::runtime_error("Error converting string: " + Utils::GetFormattedWindowsErrorMsg());
    }

    return wide_name.get();
}

std::vector<char> Utils::StreambufToVector(boost::asio::streambuf &buf)
{
    using namespace boost::asio;

    std::vector<char> data(buf.size());
    buffer_copy(buffer(data), buf.data());
    buf.consume(buf.size());

    return data;
}
