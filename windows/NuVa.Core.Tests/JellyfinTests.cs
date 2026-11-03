using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using NuVa.Core.Library;

namespace NuVa.Core.Tests;

/// <summary>A stand-in Jellyfin: answers by path, records the requests.</summary>
public sealed class FakeJellyfin : HttpMessageHandler
{
    public readonly List<string> Requests = new();
    public Func<HttpRequestMessage, (int, string)> Answer = _ => (404, "");

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request.RequestUri!.PathAndQuery);
        var (status, body) = Answer(request);
        return Task.FromResult(new HttpResponseMessage((HttpStatusCode)status) { Content = new StringContent(body, Encoding.UTF8, "application/json") });
    }
}

public static class JellyfinTests
{
    private const string Auth = """{"AccessToken":"tok","User":{"Id":"u1"}}""";

    private static (JellyfinSource, FakeJellyfin) Make()
    {
        var fake = new FakeJellyfin();
        fake.Answer = request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            var query = request.RequestUri.Query;
            if (path.EndsWith("/Users/AuthenticateByName")) return (200, Auth);
            if (path.EndsWith("/UserViews")) return (200, """{"Items":[{"Id":"lib","Name":"Music","CollectionType":"music"},{"Id":"mov","Name":"Films","CollectionType":"movies"}]}""");
            if (path.EndsWith("/Items") && query.Contains("parentId=lib"))
                return (200, """{"Items":[{"Id":"a1","Name":"Fleetwood Mac","IsFolder":true,"Path":"D:\\Music\\Fleetwood Mac"}]}""");
            if (path.EndsWith("/Items") && query.Contains("parentId=a1"))
                return (200, """{"Items":[{"Id":"r1","Name":"Rumours","IsFolder":true,"Path":"D:\\Music\\Fleetwood Mac\\Rumours (1977)"},{"Id":"t9","Name":"Notes","IsFolder":false,"Path":"D:\\Music\\Fleetwood Mac\\notes.txt"}]}""");
            if (path.EndsWith("/Items") && query.Contains("parentId=r1"))
                return (200, """{"Items":[{"Id":"t2","Name":"Dreams","IsFolder":false,"Path":"D:\\Music\\Fleetwood Mac\\Rumours (1977)\\02 Dreams.flac","RunTimeTicks":2570000000},{"Id":"t1","Name":"Second Hand News","IsFolder":false,"Path":"D:\\Music\\Fleetwood Mac\\Rumours (1977)\\01 Second Hand News.flac"}]}""");
            return (404, "");
        };
        var source = new JellyfinSource(Guid.NewGuid(), "Jellyfin · home", new Uri("https://jf.example"), "nuno", "dev", () => "pw", new HttpClient(fake));
        return (source, fake);
    }

    [Test]
    public static void BrowsesByPathNotTags()
    {
        var (source, _) = Make();
        var root = source.List("").Result;
        Assert.Sequence(["Fleetwood Mac"], root.Select(e => e.Name));
        var artist = source.List("Fleetwood Mac").Result;
        // Folder names as on the disk ("Rumours (1977)"), never Jellyfin's album name.
        Assert.Sequence(["Rumours (1977)"], artist.Select(e => e.Name));
        var album = source.List("Fleetwood Mac/Rumours (1977)").Result;
        Assert.Sequence(["01 Second Hand News.flac", "02 Dreams.flac"], album.Select(e => e.Name));
        Assert.Near(257, album[1].Duration!.Value, 0.01);
    }

    [Test]
    public static void StreamsTheOriginalFile()
    {
        var (source, _) = Make();
        var album = source.List("Fleetwood Mac/Rumours (1977)").Result;
        Assert.Equal("https://jf.example/Audio/t2/stream.flac?static=true&api_key=tok", source.Url(album[1]).Result);
    }

    [Test]
    public static void ReopensDeepPathsLevelByLevel()
    {
        var (source, fake) = Make();
        // After a restart: no ids in memory, a deep path straight away.
        var album = source.List("Fleetwood Mac/Rumours (1977)").Result;
        Assert.Equal(2, album.Count);
        Assert.True(fake.Requests.Count(r => r.Contains("parentId=")) == 3, string.Join(" ", fake.Requests));
    }

    [Test]
    public static void ServerAddresses()
    {
        Assert.Equal("https://jf.example/", JellyfinSource.ServerUrl("jf.example/")!.AbsoluteUri);
        Assert.Equal("http://192.168.1.2:8096/", JellyfinSource.ServerUrl(" http://192.168.1.2:8096 ")!.AbsoluteUri);
        Assert.Equal(null, JellyfinSource.ServerUrl(""));
        Assert.Equal(null, JellyfinSource.ServerUrl("ftp://x"));
    }

    [Test]
    public static void WrongPasswordSaysSo()
    {
        var fake = new FakeJellyfin { Answer = _ => (401, "") };
        try
        {
            JellyfinSource.Login(new Uri("https://jf.example"), "a", "b", "d", new HttpClient(fake)).Wait();
            Assert.True(false, "no error");
        }
        catch (AggregateException e)
        {
            Assert.True(e.InnerException is SourceException, e.InnerException?.GetType().Name ?? "");
        }
    }
}
