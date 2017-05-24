#ifndef PIPEMITMTOOL_H
#define PIPEMITMTOOL_H

#include <string>
#include <boost/asio.hpp>
#include <Windows.h>


class PipeMitmTool
{
public:
    PipeMitmTool(const std::string &a_pipe_name, const std::string &e_pipe_name);
    void Run();

private:
    class PipeContext {
    public:
        using DataHandler = std::function<void(const std::vector<char>&)>;

        PipeContext(boost::asio::io_service &ios, const std::string &pipe_name, bool create);
        void SetDataHandler(DataHandler handler = nullptr);
        void Run();
        void Write(const std::vector<char> &data);

    private:
        HANDLE CreatePipe(const std::wstring &pipe_name);
        HANDLE OpenPipe(const std::wstring &pipe_name);
        void AsyncRead();
        void AsyncWrite();
        void ReadHandler(const boost::system::error_code& error, std::size_t bytes_transferred);
        void WriteHandler(const boost::system::error_code& error, std::size_t bytes_transferred);

        static constexpr size_t MaxReadLen = 4096;

        boost::asio::windows::stream_handle stream;
        boost::asio::streambuf rx_buff;
        boost::asio::streambuf tx_buff;

        bool writing = false;
        DataHandler data_handler = nullptr;
    };

    void HandleRead(const std::string &dir_str, const std::vector<char> &data);

    boost::asio::io_service ios;
    PipeContext pipe_a;
    PipeContext pipe_e;
};

#endif // PIPEMITMTOOL_H
