using System.Text.Json;

namespace GreenKasse.App.Applikation.Services.Auth;

public sealed class LoginService
{
    private readonly CloudAuthClient _cloud;

    public LoginService(CloudAuthClient cloud, DeviceService device)
    {
        _cloud = cloud;
    }

    public async Task<object> LoginAsync(Dto.LoginRequest dto, CancellationToken ct)
    {

        var (sessId, shiftKey) = await _cloud.GetSessionAndShiftAsync(ct);
        await _cloud.PrimeSessionAsync(sessId, ct);

        using var doc = await _cloud.LoginAsync(
            tokenId:  sessId,
            shiftKey: shiftKey,
            isTill:   true,
            user:     dto.user,
            passPlain:dto.pass,
            licence:  dto.licence,
            ct:       ct);

        var rawObj = JsonSerializer.Deserialize<object>(doc.RootElement.GetRawText())!;
        return rawObj;
    }
}