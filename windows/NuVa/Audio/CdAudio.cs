using System;
using NuVa.Core.Audio;

namespace NuVa.Audio;

/// <summary>Opens cdda://D/3 locations (drive letter, track number). Filled in with the audio CD support.</summary>
internal static class CdDecoderFactory
{
    public static IDecoder Open(string location) => throw new NotSupportedException("Audio CDs come in a later step");
}
