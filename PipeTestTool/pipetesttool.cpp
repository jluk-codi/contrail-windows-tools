#include "pipetesttool.h"
#include "utils.h"
#include "fakedata.h"

#include <iostream>
#include <boost/bind.hpp>

using namespace boost::asio;

PipeTestTool::PipeTestTool(const wchar_t *pipe_name, unsigned long timeout_ms) :
    stream(ios),
    timer(ios),
    timeout_ms(timeout_ms)
{
    const DWORD access_flags = GENERIC_READ | GENERIC_WRITE;
    const DWORD attrs = OPEN_EXISTING;
    const DWORD flags = FILE_FLAG_OVERLAPPED;

    const HANDLE handle = CreateFile(pipe_name, access_flags, 0, NULL, attrs, flags, NULL);
    if (handle == INVALID_HANDLE_VALUE)
        throw std::runtime_error("Error while opening pipe: " + Utils::GetFormattedWindowsErrorMsg());

    stream.assign(handle);
}

void PipeTestTool::Run()
{
    AsyncTimer();
    AsyncRead();

    ios.run();
}

void PipeTestTool::AsyncRead()
{
    auto handler = boost::bind(&PipeTestTool::ReadHandler, this,
                               placeholders::error, placeholders::bytes_transferred);
    stream.async_read_some(buffer(read_buff, MaxReadLen), handler);
}

void PipeTestTool::AsyncWrite()
{
    if (!writing && write_buff.size() > 0) {
        writing = true;
        auto handler = boost::bind(&PipeTestTool::WriteHandler, this,
                                   placeholders::error, placeholders::bytes_transferred);
        stream.async_write_some(write_buff.data(), handler);
    }
}

void PipeTestTool::AsyncTimer()
{
    if (timeout_ms != 0) {
        timer.expires_from_now(std::chrono::milliseconds(timeout_ms));
        timer.async_wait(boost::bind(&PipeTestTool::TimeoutHandler, this));
    }
}

void PipeTestTool::ReadHandler(const boost::system::error_code &error, size_t bytes_transferred)
{
    if (error) {
        std::cerr << "Error while reading data: " << error.message() << std::endl;
        return;
    }

    std::cout << "Received " << bytes_transferred << " bytes: " <<
                 Utils::DataToHex(read_buff, bytes_transferred) << std::endl;

    WriteFakeData(bytes_transferred);
    AsyncRead();
}

void PipeTestTool::WriteHandler(const boost::system::error_code &error, size_t bytes_transferred)
{
    if (error) {
        std::cerr << "Error while writing data: " << error.message() << std::endl;
        return;
    }

    write_buff.consume(bytes_transferred);
    writing = false;

    AsyncWrite();
}

void PipeTestTool::TimeoutHandler()
{
    std::cout << ".";
}

void PipeTestTool::WriteFakeData(size_t echo_len)
{
    CopyDataToBuff(FakeData::FakeEtherHdr);
    CopyDataToBuff(FakeData::FakeAgentHdr);

    const size_t headers_len = sizeof(FakeData::ether_header) + sizeof(FakeData::agent_hdr);
    if (echo_len >= headers_len) {
        const size_t len = echo_len - headers_len;
        const auto buff = boost::asio::buffer_cast<void*>(write_buff.prepare(len));
        memcpy(buff, read_buff + headers_len, len);
        write_buff.commit(len);
    }

    AsyncWrite();
}
