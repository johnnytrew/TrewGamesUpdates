using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;
[assembly: System.Reflection.AssemblyTitle("Connectopoly Auto Launcher")]
[assembly: System.Reflection.AssemblyVersion("1.1.0.0")]
[assembly: System.Reflection.AssemblyFileVersion("1.1.0.0")]
internal static class Program {
  [STAThread]
  static void Main() {
    try {
      string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"TrewGamesUpdater");
      string ps=Path.Combine(root,"TrewUpdateClient.ps1");
      if(!File.Exists(ps)) throw new Exception("TrewUpdateClient.ps1 is missing.");

      ProcessStartInfo p=new ProcessStartInfo(
        "powershell.exe",
        "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \""+ps+"\" -Mode Launch -Quiet"
      );
      p.UseShellExecute=false;
      p.CreateNoWindow=true;
      Process.Start(p);
    } catch(Exception ex) {
      MessageBox.Show(ex.Message,"Connectopoly Auto Launcher",MessageBoxButtons.OK,MessageBoxIcon.Warning);
    }
  }
}
