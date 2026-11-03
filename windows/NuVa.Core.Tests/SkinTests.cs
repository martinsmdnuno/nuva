using System.Linq;

namespace NuVa.Core.Tests;

public static class SkinTests
{
    // The same pairs as Tests/SkinTests.swift: text 4.5:1, keys, LEDs and focus 3:1.
    private static readonly (Token Fg, Token Bg, double Min)[] pairs =
    [
        (Token.Ink, Token.Surface0, 4.5), (Token.InkMuted, Token.Surface0, 4.5), (Token.Ink, Token.Surface1, 4.5),
        (Token.Ink, Token.Surface2, 4.5), (Token.DisplayInk, Token.Display, 4.5), (Token.DisplayMuted, Token.Display, 4.5),
        (Token.KeyInk, Token.KeyFace, 4.5), (Token.KeyInk, Token.KeyPlay, 4.5), (Token.KeyModeInk, Token.KeyMode, 4.5),
        (Token.Signal, Token.Surface0, 4.5), (Token.Led, Token.Surface0, 3), (Token.Focus, Token.Surface0, 3),
    ];

    [Test]
    public static void EveryPairHasContrast()
    {
        foreach (var skin in Skin.All)
            foreach (var dark in new[] { false, true })
                foreach (var (fg, bg, min) in pairs)
                {
                    var ratio = Skin.Contrast(skin.Color(fg, dark), skin.Color(bg, dark));
                    Assert.True(ratio >= min, $"{skin.Id} {(dark ? "dark" : "light")} {fg} on {bg}: {ratio:F2}");
                }
    }

    [Test]
    public static void OldIdsMapToCurrentSkins()
    {
        Assert.Equal("rams", Skin.With("nuno").Id);
        Assert.Equal("graphite-orange", Skin.With("graphite-green").Id);
        Assert.Equal("rams", Skin.With(null).Id);
        Assert.Equal(3, Skin.All.Select(s => s.Id).Distinct().Count());
    }
}
