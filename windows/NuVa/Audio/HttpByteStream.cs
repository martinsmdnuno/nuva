using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using NuVa.Core;

namespace NuVa.Audio;

/// <summary>
/// A stream over HTTP range requests, as a COM IStream for Media Foundation, for servers whose streams
/// Media Foundation won't open by URL. Reads ahead in 512 KB pieces; a seek costs one request.
/// </summary>
internal sealed class HttpByteStream : IStream
{
    private const int Piece = 512 * 1024;
    private static readonly HttpClient http = new() { Timeout = TimeSpan.FromSeconds(30) };
    private readonly string url;
    private readonly long length;
    private long position;
    private byte[] buffer = [];
    private long bufferStart = -1;

    public string? ContentType { get; }

    public HttpByteStream(string url)
    {
        this.url = url;
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.Range = new RangeHeaderValue(0, 0);
        using var response = http.Send(request, HttpCompletionOption.ResponseHeadersRead);
        response.EnsureSuccessStatusCode();
        // 206: the length is in Content-Range ("bytes 0-0/12345"); 200: the server ignores ranges and sends it all.
        length = response.StatusCode == System.Net.HttpStatusCode.PartialContent
            ? response.Content.Headers.ContentRange?.Length ?? throw new InvalidOperationException("The server doesn't say how long the file is")
            : response.Content.Headers.ContentLength ?? throw new InvalidOperationException("The server doesn't say how long the file is");
        ContentType = response.Content.Headers.ContentType?.MediaType;
    }

    private void Fetch(long at)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        var end = Math.Min(length - 1, at + Piece - 1);
        request.Headers.Range = new RangeHeaderValue(at, end);
        using var response = http.Send(request);
        response.EnsureSuccessStatusCode();
        var data = response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult();
        if (response.StatusCode == System.Net.HttpStatusCode.OK)
        {
            // No range support: the whole file came back. Keep all of it, so it comes only once.
            buffer = data;
            bufferStart = 0;
        }
        else
        {
            buffer = data;
            bufferStart = at;
        }
    }

    public void Read(byte[] pv, int cb, IntPtr pcbRead)
    {
        var done = 0;
        try
        {
            while (done < cb && position < length)
            {
                if (bufferStart < 0 || position < bufferStart || position >= bufferStart + buffer.Length) Fetch(position);
                if (buffer.Length == 0) break;
                var offset = (int)(position - bufferStart);
                var n = Math.Min(cb - done, buffer.Length - offset);
                Array.Copy(buffer, offset, pv, done, n);
                done += n;
                position += n;
            }
        }
        catch (Exception e)
        {
            Log.Write($"http stream: {e.Message}");
            if (done == 0) throw new COMException("Read failed", unchecked((int)0x80004005));
        }
        if (pcbRead != IntPtr.Zero) Marshal.WriteInt32(pcbRead, done);
    }

    public void Seek(long dlibMove, int dwOrigin, IntPtr plibNewPosition)
    {
        position = dwOrigin switch { 0 => dlibMove, 1 => position + dlibMove, _ => length + dlibMove };
        position = Math.Clamp(position, 0, length);
        if (plibNewPosition != IntPtr.Zero) Marshal.WriteInt64(plibNewPosition, position);
    }

    public void Stat(out STATSTG pstatstg, int grfStatFlag)
    {
        pstatstg = new STATSTG { cbSize = length, type = 2 /* STGTY_STREAM */, grfMode = 0 };
    }

    public void Clone(out IStream ppstm) => throw new NotImplementedException();
    public void Commit(int grfCommitFlags) { }
    public void CopyTo(IStream pstm, long cb, IntPtr pcbRead, IntPtr pcbWritten) => throw new NotImplementedException();
    public void LockRegion(long libOffset, long cb, int dwLockType) => throw new NotImplementedException();
    public void Revert() { }
    public void SetSize(long libNewSize) => throw new NotImplementedException();
    public void UnlockRegion(long libOffset, long cb, int dwLockType) => throw new NotImplementedException();
    public void Write(byte[] pv, int cb, IntPtr pcbWritten) => throw new NotImplementedException();
}
