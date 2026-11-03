using NuVa.Core;

namespace NuVa.Core.Tests;

public static class UpdateTests
{
    [Test]
    public static void VersionsCompareByNumber()
    {
        Assert.True(Updates.IsNewer("1.10", "1.9"));
        Assert.True(!Updates.IsNewer("1.1", "1.1.0"));
        Assert.True(Updates.IsNewer("1.11", "1.10.1"));
    }

    [Test]
    public static void OnlyReleasesWithTheWindowsZipCount()
    {
        var with = Updates.Parse("""{"tag_name":"v1.11","html_url":"https://x","assets":[{"name":"NuVa.dmg"},{"name":"NuVa-Windows-1.11.zip"}]}""");
        Assert.Equal("1.11", with.Version);
        Assert.True(with.HasWindows);
        var without = Updates.Parse("""{"tag_name":"v1.12","html_url":"https://x","assets":[{"name":"NuVa.dmg"}]}""");
        Assert.True(!without.HasWindows);
    }

    [Test]
    public static void TermsInEachLanguage()
    {
        var md = "# Terms\n\nHello\nworld.\n\n## Privacy\n\n- **One**\n\n---\n\n# Termos\n\nOlá.";
        var en = Terms.Blocks(md, false);
        Assert.Equal((Terms.Kind.Paragraph, "Hello world."), en[1]);
        Assert.Equal(Terms.Kind.Bullet, en[3].Kind);
        Assert.Equal("Termos", Terms.Blocks(md, true)[0].Text);
    }
}
