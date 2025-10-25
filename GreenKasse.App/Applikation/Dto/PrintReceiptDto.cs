namespace GreenKasse.App.Applikation.Dto;

public sealed record PrintReceiptDto(
    string Text,
    bool Cut = true,
    bool OpenDrawerAfter = false,
    int Copies = 1
);