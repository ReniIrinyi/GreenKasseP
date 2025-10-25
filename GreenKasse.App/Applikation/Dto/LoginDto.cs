namespace GreenKasse.App.Applikation.Dto;

public sealed record LoginRequest(string user, string pass, string licence);

public sealed record LoginResponse(
    string sessionId,
    int shiftKey,
    object raw 
);