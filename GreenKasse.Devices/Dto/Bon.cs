namespace GreenKasse.Devices.Dto;

public sealed record Bon(string Text, bool Cut = true, bool OpenDrawerAfter = false);