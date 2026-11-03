using System;
using System.Linq;
using NuVa.Core.Player;

namespace NuVa.Core.Tests;

public static class GlowTests
{
    [Test]
    public static void MutedTextKeepsItsContrastOnTheGlow()
    {
        foreach (var skin in Skin.All)
        {
            var display = skin.Color(Token.Display, true);
            var muted = skin.Color(Token.DisplayMuted, true);
            // A bright, colourful cover: white, yellow, red and blue quarters.
            var cover = Enumerable.Range(0, 256).Select(i => (i % 16 < 8, i / 16 < 8) switch
            {
                (true, true) => 0xFFFFFFu, (false, true) => 0xFFE000u, (true, false) => 0xE02020u, _ => 0x2040FFu,
            }).ToArray();
            var field = ArtworkGlow.Field(cover, display, muted)!;
            Assert.Equal(ArtworkGlow.Width * ArtworkGlow.Height, field.Length);
            var worst = field.Min(c => Skin.Contrast(muted, c));
            Assert.True(worst >= 4.4, $"{skin.Id}: {worst:F2}");
            Assert.True(field.Distinct().Count() > 10, "a field, not a flat colour");
        }
    }
}
