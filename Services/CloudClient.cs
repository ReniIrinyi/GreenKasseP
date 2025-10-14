using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace KasseApp.Server.Services;

public sealed class CloudAuthClient
{
    private readonly HttpClient _http;
    private readonly CookieContainer _cookies;
    private readonly IConfiguration _cfg;  
    public CloudAuthClient(IConfiguration cfg)
    {
        
        _cfg = cfg; 
        var baseUrl = cfg["Cloud:BaseUrl"] 
                      ?? throw new InvalidOperationException("Missing Cloud:BaseUrl");
        
        _cookies = new CookieContainer();
        var handler = new HttpClientHandler
        {
            CookieContainer = _cookies,
            UseCookies = true,
            AllowAutoRedirect = false
        };
        _http = new HttpClient(handler) { BaseAddress = new Uri(baseUrl, UriKind.Absolute) };
    }
    
    public async Task<(string sessId, int shiftKey)> GetSessionAndShiftAsync(CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "authenticate/");
        req.Headers.TryAddWithoutValidation("isTill", "1");
        using var resp = await _http.SendAsync(req, ct);
        resp.EnsureSuccessStatusCode();

        var raw = await resp.Content.ReadAsStringAsync(ct);
        var tokenStr = raw.Trim().StartsWith("{")
            ? JsonDocument.Parse(raw).RootElement.GetProperty("tokenStr").GetString()!
            : raw.Trim().Trim('"');

        if (tokenStr.Length < 5) throw new InvalidOperationException("tokenStr too short");

        // tail = last 4, => shiftKey
        var tail = tokenStr[^4..];
        var shiftKey = int.Parse(
            new string(tail.Select(c => c == 'x' ? '-' : (char)('0' + Math.Max(0, Math.Min(9, c - 'a')))).ToArray())
                .TrimStart('0')
                .PadLeft(1, '0')
        );

        //  sessId = tokenStr without last 4
        var sessId = tokenStr[..^4];
        return (sessId, shiftKey);
    }

    public async Task PrimeSessionAsync(string sessId, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "authenticate/");
        req.Headers.TryAddWithoutValidation("isTill", "1");
        req.Headers.TryAddWithoutValidation("sessId", sessId);
        using var resp = await _http.SendAsync(req, ct);
        resp.EnsureSuccessStatusCode();
    }
    

    public async Task<JsonDocument> LoginAsync(string tokenId, string deviceId, int shiftKey, bool isTill, string user, string passPlain, string licence, CancellationToken ct)
    {
        Console.WriteLine(tokenId);
        Console.WriteLine(deviceId);
        var passMd5 = Md5Hex(passPlain);
        var payload = JsonSerializer.Serialize(new { u = user, p = passMd5, l = licence });

        Span<int> codes = stackalloc int[payload.Length];
        for (int i = 0; i < payload.Length; i++)
            codes[i] = payload[i] + shiftKey;

        var secret = EncodeDeleteHashZ36(codes);

        var content = new FormUrlEncodedContent(new[]
        {
            new KeyValuePair<string, string>("secret", secret)
        });

        using var req = new HttpRequestMessage(HttpMethod.Put, "login/") { Content = content };
        req.Headers.TryAddWithoutValidation("sessid", tokenId);
        req.Headers.TryAddWithoutValidation("device", deviceId);
        req.Headers.TryAddWithoutValidation("isTill", "1");
        req.Headers.TryAddWithoutValidation("phase", "green");

        using var resp = await _http.SendAsync(req, ct);
        if (!resp.IsSuccessStatusCode)
        {
            var txt = await resp.Content.ReadAsStringAsync(ct);
            throw new HttpRequestException($"Cloud login failed {(int)resp.StatusCode}: {txt}");
        }

        var stream = await resp.Content.ReadAsStreamAsync(ct);
        return await JsonDocument.ParseAsync(stream, cancellationToken: ct);
    }

    
    private static string Md5Hex(string s)
    {
        var bytes = MD5.HashData(Encoding.UTF8.GetBytes(s));
        var sb = new StringBuilder(bytes.Length * 2);
        foreach (var b in bytes) sb.Append(b.ToString("x2"));
        return sb.ToString();
    }

    private static string EncodeDeleteHashZ36(ReadOnlySpan<int> codes)
    {
        // 1) base36 + prefix
        var parts = new List<(bool neg, string digits)>(codes.Length);
        int chunkLen = 1;

        foreach (var v in codes)
        {
            bool neg = v < 0;
            int abs = neg ? -v : v;

            string digits = ToBase36Lower(abs);   // "0", "a3", ...
            parts.Add((neg, digits));

            int needed = digits.Length + (neg ? 1 : 0);
            if (needed > chunkLen) chunkLen = needed;
        }

        if (chunkLen > 25 + 1) 
        {
        }

        var sb = new StringBuilder();
        sb.Append((char)(100 + chunkLen));
        sb.Append('x');

        foreach (var (neg, digits) in parts)
        {
            int pad = chunkLen - digits.Length - (neg ? 1 : 0);
            if (pad < 0)
                throw new InvalidOperationException("pad<0");

            if (neg) sb.Append('A'); 

            while (pad >= 25)
            {
                sb.Append('Z'); 
                pad -= 25;
            }
            if (pad > 0)
            {
                sb.Append((char)('B' + pad - 1)); // 1..24 → B..Y
            }

            sb.Append(digits);
        }

        return sb.ToString();
    }
    
    private static string ToBase36Lower(int value)
    {
        if (value == 0) return "0";
        if (value < 0) return "-" + ToBase36Lower(-value);

        const string alphabet = "0123456789abcdefghijklmnopqrstuvwxyz";
        Span<char> buf = stackalloc char[16];
        var pos = buf.Length;

        while (value > 0)
        {
            var rem = value % 36;
            value /= 36;
            buf[--pos] = alphabet[rem];
        }
        return new string(buf[pos..]);
    }

}
