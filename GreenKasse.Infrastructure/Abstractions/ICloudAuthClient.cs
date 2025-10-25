using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
// --- DTO-k / Recordok ---

/// <summary>
/// /authenticate/register → 202 PENDING eredménye
/// </summary>
public sealed record RegisterDeviceResult(
    string SessId,
    int ShiftKey,
    string PairingCode);

/// <summary>
/// /login → 200 OK eredménye (első belépés pairingCode-dal VAGY normál belépés).
/// </summary>
public sealed record LoginResult(
    string SessionToken,
    IReadOnlyList<DeviceConfigSummary> DeviceConfigs,
    JsonElement Raw // ha átmenetileg kell a teljes JSON
);

/// <summary>
/// Konfig listaeleme (UI választ ehhez).
/// </summary>
public sealed record DeviceConfigSummary(
    string ConfigId,
    string Name);

/// <summary>
/// /api/greenkasse/device/bind → 200 OK
/// </summary>
public sealed record BindDeviceResult(
    bool Bound);

public sealed record PosConfig(
    string ConfigId,
    JsonElement Raw);
public interface ICloudAuthClient
{
    
    
        Task<(string sessId, int shiftKey)> GetSessionAndShiftAsync(CancellationToken ct = default);

        Task PrimeSessionAsync(string sessId, CancellationToken ct = default);

        Task<JsonDocument> LoginAsync(
            string tokenId,
            int shiftKey,
            bool isTill,
            string user,
            string passPlain,
            string licence,
            CancellationToken ct = default);

        // --------- Erst-Pairing + Bind flow ---------
        
        Task<RegisterDeviceResult> RegisterDeviceAsync(
            string deviceId,
            CancellationToken ct = default);

  
        Task<LoginResult> LoginWithPairingCodeAsync(
            string deviceId,
            string username,
            string passwordPlain,
            string pairingCode,
            CancellationToken ct = default);


        Task<BindDeviceResult> BindDeviceAsync(
            string deviceId,
            string configId,
            CancellationToken ct = default);


        Task<PosConfig> GetConfigAsync(
            string configId,
            CancellationToken ct = default);
    }


