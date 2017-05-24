#include "pipemitmtool.h"
#include "utils.h"

#include <boost/bind.hpp>
#include <iostream>

using namespace boost::asio;

PipeMitmTool::PipeMitmTool(const std::string &a_pipe_name, const std::string &e_pipe_name) :
    pipe_a(ios, a_pipe_name, true),
    pipe_e(ios, e_pipe_name, false)
{
    pipe_a.SetDataHandler([this](const auto &data)
    {
        HandleRead("[A --> E]", data);
        pipe_e.Write(data);
    });

    pipe_e.SetDataHandler([this](const auto &data)
    {
        HandleRead("[A <-- E]", data);
        pipe_a.Write(data);
    });
}

void PipeMitmTool::Run()
{
    pipe_a.Run();
    pipe_e.Run();
    ios.run();
}

void PipeMitmTool::HandleRead(const std::string &dir_str, const std::vector<char> &data)
{
    std::cout << dir_str << ": " << Utils::DataToHex(data) << std::endl;
}

PipeMitmTool::PipeContext::PipeContext(io_service &ios, const std::string &pipe_name, bool create) :
    stream(ios)
{
    const auto wname = Utils::StrToWide(pipe_name);
    const HANDLE handle = create ? CreatePipe(wname) : OpenPipe(wname);
    stream.assign(handle);
}

void PipeMitmTool::PipeContext::SetDataHandler(DataHandler handler)
{
    data_handler = handler;
}

void PipeMitmTool::PipeContext::Run()
{
    AsyncRead();
}

void PipeMitmTool::PipeContext::Write(const std::vector<char> &data)
{
    buffer_copy(tx_buff.prepare(data.size()), buffer(data));
    tx_buff.commit(data.size());

    AsyncWrite();
}

HANDLE PipeMitmTool::PipeContext::CreatePipe(const std::wstring &pipe_name)
{
    const DWORD open_mode = PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE;
    const DWORD pipe_mode = PIPE_TYPE_BYTE | PIPE_READMODE_BYTE;

    const HANDLE handle = CreateNamedPipe(pipe_name.c_str(), open_mode, pipe_mode, 1, MaxReadLen, MaxReadLen, 0, NULL);
    if (handle == INVALID_HANDLE_VALUE)
        throw std::runtime_error("Error while creating pipe: " + Utils::GetFormattedWindowsErrorMsg());

    return handle;
}

HANDLE PipeMitmTool::PipeContext::OpenPipe(const std::wstring &pipe_name)
{
    const DWORD access_flags = GENERIC_READ | GENERIC_WRITE;
    const DWORD attrs = OPEN_EXISTING;
    const DWORD flags = FILE_FLAG_OVERLAPPED;

    const HANDLE handle = CreateFile(pipe_name.c_str(), access_flags, 0, NULL, attrs, flags, NULL);
    if (handle == INVALID_HANDLE_VALUE)
        throw std::runtime_error("Error while opening pipe: " + Utils::GetFormattedWindowsErrorMsg());

    return handle;
}

void PipeMitmTool::PipeContext::AsyncRead()
{
    auto handler = boost::bind(&PipeContext::ReadHandler, this, placeholders::error, placeholders::bytes_transferred);
    stream.async_read_some(rx_buff.prepare(MaxReadLen), handler);
}

void PipeMitmTool::PipeContext::AsyncWrite()
{
    if (!writing && tx_buff.size() > 0) {
        writing = true;
        auto handler = boost::bind(&PipeContext::WriteHandler, this, placeholders::error, placeholders::bytes_transferred);
        stream.async_write_some(tx_buff.data(), handler);
    }
}

void PipeMitmTool::PipeContext::ReadHandler(const boost::system::error_code &error, size_t bytes_transferred)
{
    // FIXME: Ugly, CPU intensive hack. It should wait for remote connection instead.
    if (error && error.value() != ERROR_PIPE_LISTENING) {
        throw std::runtime_error("[ReadHandler] " + error.message());
    }

    rx_buff.commit(bytes_transferred);
    const std::vector<char> data = Utils::StreambufToVector(rx_buff);

    if (data_handler && bytes_transferred > 0) {
        data_handler(data);
    }

    AsyncRead();
}

void PipeMitmTool::PipeContext::WriteHandler(const boost::system::error_code &error, size_t bytes_transferred)
{
    if (error) {
        throw std::runtime_error("[WriteHandler] " + error.message());
    }

    tx_buff.consume(bytes_transferred);
    writing = false;

    AsyncWrite();
}
