namespace GreenKasse.App.Domain.Errors;

public class DomainException : Exception
{
    public int Code { get; }
    public DomainException(string message, int code = 0) : base(message) => Code = code;
}