using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Diagnostics;
using System.Windows.Forms;

[assembly: AssemblyTitle("homeNetbird Aurora Setup")]
[assembly: AssemblyVersion("1.1.0.0")]
internal static class SetupLauncher {
    [STAThread]
    private static void Main() {
        Application.EnableVisualStyles();
        try {
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "homeNetbird", "Setup", "1.1.0");
            Directory.CreateDirectory(root);
            string archive = Path.Combine(root, "payload.zip");
            using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream("homeNetbird.payload.zip"))
            using (FileStream target = File.Create(archive)) { source.CopyTo(target); }
            using (SHA256 hash = SHA256.Create())
            using (FileStream stream = File.OpenRead(archive)) {
                string actual = BitConverter.ToString(hash.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
                if (actual != "__PAYLOAD_SHA256__") throw new InvalidDataException("Embedded package checksum mismatch.");
            }
            string prefix = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            using (ZipArchive zip = ZipFile.OpenRead(archive)) {
                foreach (ZipArchiveEntry entry in zip.Entries) {
                    string destination = Path.GetFullPath(Path.Combine(root, entry.FullName));
                    if (!destination.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Invalid archive path.");
                    if (String.IsNullOrEmpty(entry.Name)) { Directory.CreateDirectory(destination); continue; }
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    entry.ExtractToFile(destination, true);
                }
            }
            string script = Path.Combine(root, "homeNetbird", "Setup.ps1");
            ProcessStartInfo info = new ProcessStartInfo();
            info.FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe");
            info.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + script + "\"";
            info.UseShellExecute = false; info.CreateNoWindow = true;
            Process.Start(info);
        } catch (Exception error) {
            MessageBox.Show(error.Message, "homeNetbird setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
