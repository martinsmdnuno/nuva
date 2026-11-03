using System;
using System.Runtime.InteropServices;
using System.Text;
using NuVa.Core;
using NuVa.Core.Library;

namespace NuVa;

/// <summary>
/// Jellyfin passwords in Windows Credential Manager (the Mac's Keychain), as generic credentials named
/// "NuVa/&lt;source id&gt;", for this user only.
/// </summary>
internal sealed class CredentialStore : ICredentialStore
{
    private const int Generic = 1;
    private const int LocalMachine = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public int Flags;
        public int Type;
        public string TargetName;
        public string? Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string? TargetAlias;
        public string? UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredWrite(ref Credential credential, int flags);

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, int type, int flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);

    private static string Target(string account) => $"NuVa/{account}";

    public string? Password(string account)
    {
        if (!CredRead(Target(account), Generic, 0, out var pointer)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(pointer);
            if (credential.CredentialBlobSize == 0) return "";
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            return Encoding.Unicode.GetString(bytes);
        }
        finally
        {
            CredFree(pointer);
        }
    }

    public void SetPassword(string password, string account)
    {
        var bytes = Encoding.Unicode.GetBytes(password);
        var blob = Marshal.AllocHGlobal(Math.Max(1, bytes.Length));
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new Credential
            {
                Type = Generic,
                TargetName = Target(account),
                CredentialBlobSize = bytes.Length,
                CredentialBlob = blob,
                Persist = LocalMachine,
                UserName = "NuVa",
                Comment = "NuVa: Jellyfin",
            };
            if (!CredWrite(ref credential, 0)) Log.Write($"credentials: not saved ({Marshal.GetLastWin32Error()})");
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
        }
    }

    public void DeletePassword(string account) => CredDelete(Target(account), Generic, 0);
}
