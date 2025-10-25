
public interface ICredentialService
{
    CloudCreditentials Load();
    void SaveEncrypted(CloudCreditentials creds);
    void Clear();
    CloudCreditentials LoadFile();
}