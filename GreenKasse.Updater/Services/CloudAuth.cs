using GreenKasse.Updater.Models;
using Microsoft.Extensions.Logging;

namespace GreenKasse.Updater.Services;

public sealed class CloudAuth
{
    private readonly CloudClient _cloud;
    private readonly SessionService _sessionStore;
    private readonly Creditentials _credStore;
    private readonly ILogger<CloudAuth> _log;

    public string SessId { get; private set; } = "";
    public int ShiftKey  { get; private set; }

    public CloudAuth(CloudClient cloud, SessionService sessionStore, Creditentials credStore, ILogger<CloudAuth> log)
        => (_cloud, _sessionStore, _credStore, _log) = (cloud, sessionStore, credStore, log);

    public async Task EnsureAsync(CancellationToken ct)
    {
        var existing = _sessionStore.Load();
        if (existing is not null)
        {
            try {
                SessId = existing.SessionId; ShiftKey = existing.ShiftKey;
                await _cloud.PrimeSessionAsync(SessId, ct);
                _log.LogInformation("Session OK (primed).");
                return;
            }
            catch (Exception ex) { _log.LogWarning(ex, "Prime failed, re-login needed."); }
        }

        var creds = _credStore.Load();
        (SessId, ShiftKey) = await _cloud.GetSessionAndShiftAsync(ct);
        await _cloud.PrimeSessionAsync(SessId, ct);
        await _cloud.LoginAsync(SessId, creds.DeviceId, ShiftKey, true, creds.User, creds.Password, creds.Licence, ct);
        _sessionStore.Save(new SessionData(SessId, ShiftKey));
        _log.LogInformation("New session created and saved.");
    }

    // 401/403 => reauth+retry
    public async Task<T> ExecuteWithAuthAsync<T>(Func<CancellationToken, Task<T>> apiCall, CancellationToken ct)
    {
        try { return await apiCall(ct); }
        catch (HttpRequestException ex) when (ex.Message.Contains("401") || ex.Message.Contains("403"))
        {
            _log.LogWarning("Auth error ({Message}) → re-auth and retry once.", ex.Message);
            await EnsureAsync(ct);
            return await apiCall(ct);
        }
    }
}
