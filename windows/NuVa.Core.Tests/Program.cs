using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;

namespace NuVa.Core.Tests;

/// <summary>Marks a test: a public static void method with no parameters.</summary>
[AttributeUsage(AttributeTargets.Method)]
public sealed class TestAttribute : Attribute { }

public static class Assert
{
    public static void True(bool condition, string message = "expected true")
    {
        if (!condition) throw new Exception(message);
    }

    public static void Equal<T>(T expected, T actual, string message = "")
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new Exception($"expected {expected}, got {actual} {message}");
    }

    public static void Near(double expected, double actual, double tolerance, string message = "")
    {
        if (Math.Abs(expected - actual) > tolerance)
            throw new Exception($"expected {expected} ± {tolerance}, got {actual} {message}");
    }

    public static void Sequence<T>(IEnumerable<T> expected, IEnumerable<T> actual)
    {
        if (!expected.SequenceEqual(actual))
            throw new Exception($"expected [{string.Join(", ", expected)}], got [{string.Join(", ", actual)}]");
    }
}

public static class Program
{
    /// <summary>Runs every [Test] in this assembly; the exit code is the number of failures.</summary>
    public static int Main(string[] args)
    {
        var tests = typeof(Program).Assembly.GetTypes()
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static))
            .Where(m => m.GetCustomAttribute<TestAttribute>() != null)
            .Where(m => args.Length == 0 || args.Any(a => $"{m.DeclaringType!.Name}.{m.Name}".Contains(a, StringComparison.OrdinalIgnoreCase)))
            .OrderBy(m => m.DeclaringType!.Name).ThenBy(m => m.Name)
            .ToList();
        var failed = 0;
        foreach (var test in tests)
        {
            var name = $"{test.DeclaringType!.Name}.{test.Name}";
            try
            {
                test.Invoke(null, null);
                Console.WriteLine($"  ok    {name}");
            }
            catch (TargetInvocationException e)
            {
                failed++;
                Console.WriteLine($"  FAIL  {name}: {e.InnerException?.Message}");
            }
        }
        Console.WriteLine($"{tests.Count - failed} passed, {failed} failed");
        return failed;
    }
}
