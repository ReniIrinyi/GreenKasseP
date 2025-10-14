
using GreenKasse.Setup.Models;

string Prompt(string label)
{
    Console.Write(label);
    return Console.ReadLine() ?? "";
}

var creds = new CloudCreditentials()
{
    User = Prompt("Benutzername: "),
    Password = Prompt("Passwort: "),
    Licence = Prompt("Lizenz: "),
    DeviceId = new DeviceProvider().GetDeviceId()
};

new CreditentialService().SaveEncrypted(creds);
Console.WriteLine("✓ Cloud Zugangsdaten gespeichert.");