#ifndef UTILS_H
#define UTILS_H

#include <string>
#include <vector>
#include <boost/asio/streambuf.hpp>

class Utils
{
public:
    static std::string GetFormattedWindowsErrorMsg();
    static std::string DataToHex(const char *data, std::size_t length);
    static std::string DataToHex(const std::vector<char> &data);
    static std::wstring StrToWide(const std::string &str);
    static std::vector<char> StreambufToVector(boost::asio::streambuf &buf);
};

#endif // UTILS_H
