class_name CredentialStore
extends RefCounted
## Speichert API-Keys nur auf ausdruecklichen Wunsch in der Windows-Anmeldeinformationsverwaltung
## (Credential Manager, Typ "Generisch", Ziel "PixelTransportRivals/<Slot>").
## Der Schluessel wird per kurzzeitig gesetzter Umgebungsvariable an PowerShell vererbt, nie als Kommandozeilenargument.

const PREFIX := "PixelTransportRivals/"
const CHUNK := 1200       # Zeichen je Tresoreintrag (Grenze der Windows-Anmeldeinformationsverwaltung: 1280)
const MAX_PARTS := 8     # bis 9600 Zeichen

const CS := """
using System; using System.Runtime.InteropServices; using System.Text;
public static class PtrCred {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CRED { public int Flags; public int Type; public string TargetName; public string Comment;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten; public int CredentialBlobSize;
    public IntPtr CredentialBlob; public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName; }
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredWriteW(ref CRED c, int f);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredReadW(string t, int ty, int f, out IntPtr c);
  [DllImport("advapi32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CredDeleteW(string t, int ty, int f);
  [DllImport("advapi32.dll")] static extern void CredFree(IntPtr p);
  public static bool Write(string target, string secret) {
    byte[] b = Encoding.Unicode.GetBytes(secret);
    CRED c = new CRED(); c.Type = 1; c.TargetName = target; c.Persist = 2; c.UserName = "PixelTransportRivals";
    c.CredentialBlobSize = b.Length; c.CredentialBlob = Marshal.AllocHGlobal(b.Length);
    Marshal.Copy(b, 0, c.CredentialBlob, b.Length);
    bool ok = CredWriteW(ref c, 0); Marshal.FreeHGlobal(c.CredentialBlob); return ok; }
  public static string Read(string target) {
    IntPtr p; if (!CredReadW(target, 1, 0, out p)) return null;
    CRED c = (CRED)Marshal.PtrToStructure(p, typeof(CRED));
    string s = Marshal.PtrToStringUni(c.CredentialBlob, c.CredentialBlobSize / 2); CredFree(p); return s; }
  public static bool Delete(string target) { return CredDeleteW(target, 1, 0); }
}
"""


static func available() -> bool:
	return OS.get_name() == "Windows"


## PowerShell-Argumente als -EncodedCommand (UTF-16LE, Base64): vermeidet Quoting-Probleme mit Anfuehrungszeichen.
static func _script(body: String) -> PackedStringArray:
	var script := "$ErrorActionPreference='Stop'; Add-Type -TypeDefinition @'\n" + CS + "\n'@; " + body
	return PackedStringArray(["-NoProfile", "-NonInteractive", "-EncodedCommand",
		Marshalls.raw_to_base64(script.to_utf16_buffer())])


static func save_key(slot: String, secret: String) -> bool:
	if not available() or secret == "":
		return false
	# Uebergabe per vererbter Umgebungsvariable (nur fuer diesen Aufruf gesetzt), nie per Kommandozeile
	OS.set_environment("PTR_CRED_SECRET", secret)
	var output: Array = []
	# Ein Tresoreintrag fasst hoechstens 1280 Zeichen (2560 Byte UTF-16); IONOS-Schluessel (JWT) sind laenger -> in Teile <Ziel>, <Ziel>#1, ...
	OS.execute("powershell.exe", _script(("$t='%s'; $s=$env:PTR_CRED_SECRET; $n=[math]::Ceiling($s.Length/%d); $ok=$true; " 		+ "for($i=0;$i -lt $n;$i++){ $z=$t; if($i -gt 0){$z=$t+'#'+$i}; if(-not [PtrCred]::Write($z,$s.Substring($i*%d,[math]::Min(%d,$s.Length-$i*%d)))){$ok=$false} }; " 		+ "for($i=$n;$i -lt %d;$i++){ [void][PtrCred]::Delete($t+'#'+$i) }; if($ok){'OK'}else{'FAIL'}") % [PREFIX + slot, CHUNK, CHUNK, CHUNK, CHUNK, MAX_PARTS]), output, true)
	OS.unset_environment("PTR_CRED_SECRET")
	return str(output).contains("OK")


static func read_key(slot: String) -> String:
	if not available():
		return ""
	var output: Array = []
	OS.execute("powershell.exe", _script(("$t='%s'; $r=[PtrCred]::Read($t); if($r -ne $null){ $i=1; while($i -lt %d){ $p=[PtrCred]::Read($t+'#'+$i); if($p -eq $null){break}; $r+=$p; $i++ }; 'KEY:'+$r }else{'NONE'}") % [PREFIX + slot, MAX_PARTS]), output, true)
	for chunk in output:
		for line in str(chunk).split("\n"):
			if line.begins_with("KEY:"):
				return line.trim_prefix("KEY:").strip_edges()
	return ""


static func delete_key(slot: String) -> void:
	if available():
		OS.execute("powershell.exe", _script("$t='%s'; [void][PtrCred]::Delete($t); for($i=1;$i -lt %d;$i++){ [void][PtrCred]::Delete($t+'#'+$i) }" % [PREFIX + slot, MAX_PARTS]), [], true)
