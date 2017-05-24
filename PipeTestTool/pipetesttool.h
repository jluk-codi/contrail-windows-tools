#ifndef PIPETESTTOOL_H
#define PIPETESTTOOL_H

#include <algorithm>
#include <boost/asio.hpp>
#include <boost/asio/system_timer.hpp>

class PipeTestTool
{
public:
    PipeTestTool(const wchar_t *pipe_name, unsigned long timeout_ms);
    void Run();

private:
    void AsyncRead();
    void AsyncWrite();
    void AsyncTimer();
    void ReadHandler(const boost::system::error_code& error, std::size_t bytes_transferred);
    void WriteHandler(const boost::system::error_code& error, std::size_t bytes_transferred);
    void TimeoutHandler();
    void WriteFakeData(size_t echo_len);

    template <typename T>
    void CopyDataToBuff(const T &data)
    {
        const auto size = sizeof(data);
        auto buff = boost::asio::buffer_cast<void*>(write_buff.prepare(size));

        memcpy(buff, &data, size);
        write_buff.commit(size);
    }

    static constexpr size_t MaxReadLen = 4096;

    boost::asio::io_service ios;
    boost::asio::windows::stream_handle stream;
    char read_buff[MaxReadLen];
    boost::asio::streambuf write_buff;
    bool writing = false;

    boost::asio::system_timer timer;
    unsigned long timeout_ms;
};

#endif // PIPETESTTOOL_H
