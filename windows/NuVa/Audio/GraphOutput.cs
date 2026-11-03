using System;
using System.Collections.Generic;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using NuVa.Core;
using NuVa.Core.Audio;
using Windows.Devices.Enumeration;
using Windows.Foundation;
using Windows.Media;
using Windows.Media.Audio;
using Windows.Media.Devices;
using Windows.Media.MediaProperties;
using Windows.Media.Render;
using WinRT;

namespace NuVa.Audio;

/// <summary>An output device the user can choose (the Windows counterpart of the AirPlay picker).</summary>
public sealed record OutputDevice(string? Id, string Name);

/// <summary>
/// The Windows audio engine through AudioGraph: one frame input node in the track's format (the graph
/// converts to the device's rate) into the device output node, whose gain is the volume. Follows the
/// default device unless the user picks one, and rebuilds itself when the device changes or goes away.
/// </summary>
public sealed class GraphOutput : IAudioOutput
{
    private static readonly Guid byteAccess = new("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D");

    private readonly object gate = new();
    private AudioGraph? graph;
    private AudioDeviceOutputNode? device;
    private AudioFrameInputNode? input;
    /// <summary>The format of the node that is <see cref="input"/>; a quantum of an older node is ignored.</summary>
    private AudioFormat inputFormat = new(44100, 2);
    private AudioFormat format = new(44100, 2);
    private bool configured;
    private bool running;
    private double volume = 1;
    private string? deviceId;
    private float[] buffer = new float[8192];
    private int logged;

    public Action<float[], int, AudioFormat>? Render { get; set; }
    public double Latency { get; private set; } = 0.02;

    /// <summary>Name and rate of the device the sound goes to ("Speakers · 48 kHz"); changes on the graph's thread.</summary>
    public string DeviceName { get; private set; } = "";
    public int DeviceRate { get; private set; }
    public event Action? DeviceChanged;

    public GraphOutput()
    {
        MediaDevice.DefaultAudioRenderDeviceChanged += (_, args) =>
        {
            if (args.Role != AudioDeviceRole.Default) return;
            lock (gate)
                if (deviceId != null || graph == null) return;
            Log.Write($"output: the default device changed to {args.Id}");
            Task.Run(Rebuild);
        };
    }

    public double Volume
    {
        get => volume;
        set
        {
            volume = Math.Clamp(value, 0, 1);
            lock (gate)
                if (device != null) device.OutgoingGain = volume;
        }
    }

    /// <summary>The device chosen by the user, or null for Windows' default.</summary>
    public string? SelectedDevice => deviceId;

    public void SelectDevice(string? id)
    {
        lock (gate) deviceId = id;
        Task.Run(Rebuild);
    }

    /// <summary>The output devices Windows offers, the default first.</summary>
    public static async Task<List<OutputDevice>> Devices()
    {
        var list = new List<OutputDevice> { new(null, L.T("Predefinição do sistema")) };
        try
        {
            var found = await DeviceInformation.FindAllAsync(MediaDevice.GetAudioRenderSelector());
            list.AddRange(found.Where(d => d.IsEnabled).Select(d => new OutputDevice(d.Id, d.Name)).OrderBy(d => d.Name));
        }
        catch (Exception e)
        {
            Log.Write($"output: devices unavailable: {e.Message}");
        }
        return list;
    }

    public void Configure(AudioFormat wanted)
    {
        lock (gate)
        {
            format = wanted;
            configured = true;
            if (graph == null) Build(null);
            ReplaceInput();
        }
    }

    public void Start()
    {
        lock (gate)
        {
            running = true;
            if (graph == null && configured)
            {
                Build(null);
                ReplaceInput();
            }
            graph?.Start();
        }
    }

    public void Stop()
    {
        lock (gate)
        {
            running = false;
            graph?.Stop();
        }
    }

    private void Rebuild()
    {
        lock (gate)
        {
            Teardown();
            if (!configured) return;
            try
            {
                Build(null);
                ReplaceInput();
                if (running) graph?.Start();
            }
            catch (Exception e)
            {
                Log.Write($"output: rebuild failed: {e.Message}");
            }
        }
    }

    /// <summary>Creates the graph and its device output (under gate). <paramref name="rate"/> forces the graph's rate.</summary>
    private void Build(int? rate)
    {
        var settings = new AudioGraphSettings(AudioRenderCategory.Media)
        {
            QuantumSizeSelectionMode = QuantumSizeSelectionMode.SystemDefault,
        };
        if (deviceId != null)
        {
            try
            {
                settings.PrimaryRenderDevice = DeviceInformation.CreateFromIdAsync(deviceId).AsTask().GetAwaiter().GetResult();
            }
            catch (Exception e)
            {
                Log.Write($"output: chosen device unavailable, using the default ({e.Message})");
            }
        }
        if (rate is { } r)
        {
            var props = AudioEncodingProperties.CreatePcm((uint)r, 2, 32);
            props.Subtype = MediaEncodingSubtypes.Float;
            settings.EncodingProperties = props;
        }
        var created = AudioGraph.CreateAsync(settings).AsTask().GetAwaiter().GetResult();
        if (created.Status != AudioGraphCreationStatus.Success)
            throw new InvalidOperationException($"AudioGraph: {created.Status} {created.ExtendedError?.Message}");
        graph = created.Graph;
        graph.UnrecoverableErrorOccurred += (_, args) =>
        {
            Log.Write($"output: graph error {args.Error}");
            Task.Run(Rebuild);
        };
        var made = graph.CreateDeviceOutputNodeAsync().AsTask().GetAwaiter().GetResult();
        if (made.Status != AudioDeviceNodeCreationStatus.Success)
            throw new InvalidOperationException($"AudioGraph output: {made.Status} {made.ExtendedError?.Message}");
        device = made.DeviceOutputNode;
        device.OutgoingGain = volume;
        DeviceRate = (int)graph.EncodingProperties.SampleRate;
        DeviceName = device.Device?.Name ?? graph.PrimaryRenderDevice?.Name ?? L.T("Colunas");
        Latency = (graph.LatencyInSamples + graph.SamplesPerQuantum) / (double)Math.Max(1, DeviceRate);
        logged = 0;
        Log.Write($"output: {DeviceName}, {DeviceRate} Hz, {graph.SamplesPerQuantum} frames per quantum, latency {Latency * 1000:F0} ms");
        DeviceChanged?.Invoke();
    }

    /// <summary>A frame input node in the current format (under gate).</summary>
    private void ReplaceInput()
    {
        if (input != null)
        {
            input.QuantumStarted -= OnQuantum;
            try
            {
                input.Stop();
                input.Dispose();
            }
            catch (Exception)
            {
            }
            input = null;
        }
        var props = AudioEncodingProperties.CreatePcm((uint)format.SampleRate, (uint)format.Channels, 32);
        props.Subtype = MediaEncodingSubtypes.Float;
        try
        {
            input = graph!.CreateFrameInputNode(props);
        }
        catch (Exception e)
        {
            // The graph wouldn't convert: run it at the track's own rate instead.
            Log.Write($"output: no input node at {format} ({e.Message}); rebuilding the graph at that rate");
            Teardown();
            Build(format.SampleRate);
            input = graph!.CreateFrameInputNode(props);
        }
        inputFormat = format;
        input.AddOutgoingConnection(device);
        input.QuantumStarted += OnQuantum;
        if (running) graph!.Start();
    }

    private void Teardown()
    {
        if (input != null) input.QuantumStarted -= OnQuantum;
        try
        {
            graph?.Stop();
            input?.Dispose();
            device?.Dispose();
            graph?.Dispose();
        }
        catch (Exception)
        {
        }
        input = null;
        device = null;
        graph = null;
    }

    private unsafe void OnQuantum(AudioFrameInputNode sender, FrameInputNodeQuantumStartedEventArgs args)
    {
        var frames = args.RequiredSamples;
        // A node being replaced may still run one quantum: it mustn't pull the next track's blocks.
        if (frames <= 0 || !ReferenceEquals(sender, input)) return;
        var current = inputFormat;
        var count = frames * current.Channels;
        if (logged < 3)
        {
            logged++;
            Log.Write($"output: quantum asks {frames} frames at {current}, {sender.QueuedSampleCount} queued");
        }
        if (buffer.Length < count) buffer = new float[count];
        try
        {
            Render?.Invoke(buffer, frames, current);
        }
        catch (Exception e)
        {
            Log.Write($"output: render failed: {e.Message}");
            Array.Clear(buffer, 0, count);
        }
        try
        {
            var frame = new AudioFrame((uint)(count * sizeof(float)));
            using (var locked = frame.LockBuffer(AudioBufferAccessMode.Write))
            using (var reference = locked.CreateReference())
            {
                var data = Bytes(reference, out var capacity);
                var bytes = Math.Min((uint)(count * sizeof(float)), capacity);
                fixed (float* source = buffer) Buffer.MemoryCopy(source, data, capacity, bytes);
                locked.Length = bytes;
            }
            sender.AddFrame(frame);
        }
        catch (Exception e)
        {
            if (logged < 6)
            {
                logged++;
                Log.Write($"output: frame not added: {e.Message}");
            }
        }
    }

    /// <summary>The bytes behind a WinRT memory buffer reference, through IMemoryBufferByteAccess.</summary>
    private static unsafe byte* Bytes(IMemoryBufferReference reference, out uint capacity)
    {
        var unknown = ((IWinRTObject)reference).NativeObject.ThisPtr;
        var iid = byteAccess;
        Marshal.ThrowExceptionForHR(Marshal.QueryInterface(unknown, in iid, out var access));
        try
        {
            byte* data;
            uint size;
            var getBuffer = (delegate* unmanaged[Stdcall]<IntPtr, byte**, uint*, int>)(*(void***)access)[3];
            Marshal.ThrowExceptionForHR(getBuffer(access, &data, &size));
            capacity = size;
            return data;
        }
        finally
        {
            Marshal.Release(access);
        }
    }

    public void Dispose()
    {
        lock (gate) Teardown();
    }
}
