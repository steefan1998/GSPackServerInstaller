// GSPack Server Installer - Windows GUI for Build-ServerPack.ps1.
// Every action runs the PowerShell script next to this exe and shows its output.
// Build with gui\build-gui.ps1 (uses the C# compiler that ships with Windows).
using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows.Forms;

[assembly: System.Reflection.AssemblyTitle("GSPack Server Installer")]
[assembly: System.Reflection.AssemblyProduct("GSPack Server Installer")]
[assembly: System.Reflection.AssemblyVersion("0.3.0.0")]

namespace GSPackInstaller
{
    class PackRelease
    {
        public long Id;
        public string Name;
        public DateTime Date;
        public override string ToString() { return Name + "  (" + Date.ToString("yyyy-MM-dd") + ")"; }
    }

    class MainForm : Form
    {
        const int ProjectId = 1777849;
        const string CfFiles = "https://www.curseforge.com/api/v1/mods/{0}/files?pageIndex=0&pageSize=50&sort=dateCreated&sortDescending=true&removeAlphas=true";

        readonly string appDir = AppDomain.CurrentDomain.BaseDirectory;
        string ScriptPath { get { return Path.Combine(appDir, "Build-ServerPack.ps1"); } }

        TextBox serverDirBox, zipBox, log;
        Label installedLabel, newestLabel, updateLabel;
        RadioButton latestRadio, versionRadio, zipRadio;
        ComboBox versionCombo;
        NumericUpDown ramBox;
        CheckBox eulaCheck, browserCheck, filesOnlyCheck;
        Button buildButton, startButton, folderButton, refreshButton, stopButton, consoleButton;
        Process running;
        ConsoleForm console;
        List<PackRelease> releases = new List<PackRelease>();

        public MainForm()
        {
            Text = "GSPack Server Installer";
            Font = new Font("Segoe UI", 9f);
            ClientSize = new Size(820, 720);
            MinimumSize = new Size(760, 620);
            StartPosition = FormStartPosition.CenterScreen;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            // Header with the pack logo
            var header = new Panel { Dock = DockStyle.Top, Height = 84, BackColor = Color.FromArgb(32, 24, 56) };
            var logo = new PictureBox { Location = new Point(12, 10), Size = new Size(64, 64), SizeMode = PictureBoxSizeMode.Zoom };
            string iconFile = Path.Combine(appDir, "server-icon.png");
            if (File.Exists(iconFile)) { try { logo.Image = Image.FromFile(iconFile); } catch { } }
            var title = new Label { Text = "GSPack Server Installer", ForeColor = Color.FromArgb(255, 196, 64), Font = new Font("Segoe UI", 16f, FontStyle.Bold), Location = new Point(88, 12), AutoSize = true };
            var sub = new Label { Text = "Build, update and start your GSPack Minecraft server", ForeColor = Color.Gainsboro, Location = new Point(90, 48), AutoSize = true };
            header.Controls.AddRange(new Control[] { logo, title, sub });

            // Add the panels first, so anchored controls get the real width
            var body = new Panel { Dock = DockStyle.Fill, Padding = new Padding(12) };
            Controls.Add(body);
            Controls.Add(header);

            // Server folder + status
            var folderGroup = new GroupBox { Text = "Server", Location = new Point(12, 8), Size = new Size(796, 92), Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            folderGroup.Controls.Add(new Label { Text = "Folder:", Location = new Point(12, 26), AutoSize = true });
            serverDirBox = new TextBox { Location = new Point(70, 22), Size = new Size(590, 23), Text = Path.Combine(appDir, "GSPackServer"), Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            serverDirBox.Leave += delegate { UpdateStatus(); };
            var browseDir = new Button { Text = "Browse...", Location = new Point(668, 21), Size = new Size(116, 26), Anchor = AnchorStyles.Top | AnchorStyles.Right };
            browseDir.Click += delegate {
                using (var d = new FolderBrowserDialog { SelectedPath = serverDirBox.Text, Description = "Server folder" })
                    if (d.ShowDialog(this) == DialogResult.OK) { serverDirBox.Text = d.SelectedPath; UpdateStatus(); }
            };
            installedLabel = new Label { Location = new Point(12, 58), AutoSize = true };
            newestLabel = new Label { Location = new Point(260, 58), AutoSize = true };
            updateLabel = new Label { Location = new Point(500, 58), AutoSize = true, ForeColor = Color.DarkOrange, Font = new Font("Segoe UI", 9f, FontStyle.Bold) };
            folderGroup.Controls.AddRange(new Control[] { serverDirBox, browseDir, installedLabel, newestLabel, updateLabel });

            // Which pack
            var packGroup = new GroupBox { Text = "Pack version", Location = new Point(12, 106), Size = new Size(796, 114), Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            latestRadio = new RadioButton { Text = "Latest from CurseForge", Location = new Point(12, 22), AutoSize = true, Checked = true };
            versionRadio = new RadioButton { Text = "Version:", Location = new Point(12, 50), AutoSize = true };
            versionCombo = new ComboBox { Location = new Point(110, 48), Size = new Size(300, 23), DropDownStyle = ComboBoxStyle.DropDownList };
            versionCombo.SelectedIndexChanged += delegate { versionRadio.Checked = true; };
            refreshButton = new Button { Text = "Check for updates", Location = new Point(420, 47), Size = new Size(140, 26) };
            refreshButton.Click += delegate { LoadReleases(); };
            zipRadio = new RadioButton { Text = "Local zip:", Location = new Point(12, 80), AutoSize = true };
            zipBox = new TextBox { Location = new Point(110, 78), Size = new Size(550, 23), Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            zipBox.TextChanged += delegate { if (zipBox.Text.Length > 0) zipRadio.Checked = true; };
            var browseZip = new Button { Text = "Browse...", Location = new Point(668, 77), Size = new Size(116, 26), Anchor = AnchorStyles.Top | AnchorStyles.Right };
            browseZip.Click += delegate {
                using (var d = new OpenFileDialog { Filter = "CurseForge pack (*.zip)|*.zip", Title = "Choose a GSPack zip" })
                    if (d.ShowDialog(this) == DialogResult.OK) zipBox.Text = d.FileName;
            };
            packGroup.Controls.AddRange(new Control[] { latestRadio, versionRadio, versionCombo, refreshButton, zipRadio, zipBox, browseZip });

            // Settings
            var setGroup = new GroupBox { Text = "Settings", Location = new Point(12, 226), Size = new Size(796, 84), Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right };
            setGroup.Controls.Add(new Label { Text = "RAM (GB):", Location = new Point(12, 26), AutoSize = true });
            ramBox = new NumericUpDown { Location = new Point(84, 23), Size = new Size(60, 23), Minimum = 2, Maximum = 64, Value = 8 };
            eulaCheck = new CheckBox { Text = "I accept the Minecraft EULA", Location = new Point(170, 24), AutoSize = true };
            var eulaLink = new LinkLabel { Text = "read EULA", Location = new Point(360, 26), AutoSize = true };
            eulaLink.LinkClicked += delegate { Process.Start("https://aka.ms/MinecraftEULA"); };
            browserCheck = new CheckBox { Text = "Open the download page of mods that fail to download", Location = new Point(12, 54), AutoSize = true, Checked = true };
            filesOnlyCheck = new CheckBox { Text = "Files only (for a hosting panel)", Location = new Point(440, 24), AutoSize = true };
            setGroup.Controls.AddRange(new Control[] { ramBox, eulaCheck, eulaLink, browserCheck, filesOnlyCheck });

            // Actions
            buildButton = new Button { Text = "Build / Update server", Location = new Point(12, 318), Size = new Size(190, 34), Font = new Font("Segoe UI", 9.5f, FontStyle.Bold) };
            buildButton.Click += delegate { Build(); };
            stopButton = new Button { Text = "Stop", Location = new Point(208, 318), Size = new Size(70, 34), Enabled = false };
            stopButton.Click += delegate { StopBuild(); };
            startButton = new Button { Text = "Start server", Location = new Point(290, 318), Size = new Size(130, 34) };
            startButton.Click += delegate { StartServer(); };
            consoleButton = new Button { Text = "Server console", Location = new Point(582, 318), Size = new Size(140, 34) };
            consoleButton.Click += delegate { OpenConsole(); };
            folderButton = new Button { Text = "Open server folder", Location = new Point(426, 318), Size = new Size(150, 34) };
            folderButton.Click += delegate {
                if (Directory.Exists(serverDirBox.Text)) Process.Start("explorer.exe", "\"" + serverDirBox.Text + "\"");
                else MessageBox.Show(this, "There is no server folder yet. Build the server first.", Text);
            };

            // Body is 720 - 84 (header) = 636 high: log fills it down to a 12 px margin
            log = new TextBox { Location = new Point(12, 360), Size = new Size(796, 264), Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Vertical,
                Font = new Font("Consolas", 9f), BackColor = Color.FromArgb(20, 20, 28), ForeColor = Color.Gainsboro, WordWrap = false,
                Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right };

            body.Controls.AddRange(new Control[] { folderGroup, packGroup, setGroup, buildButton, stopButton, startButton, folderButton, consoleButton, log });
            ActiveControl = buildButton;

            Shown += delegate {
                if (!File.Exists(ScriptPath)) {
                    MessageBox.Show(this, "Build-ServerPack.ps1 was not found next to this program:\n" + appDir + "\n\nKeep the exe in the same folder as the scripts.", Text, MessageBoxButtons.OK, MessageBoxIcon.Error);
                    buildButton.Enabled = false;
                }
                LoadReleases();
            };
            FormClosing += delegate(object s, FormClosingEventArgs e) {
                if (running != null && !running.HasExited &&
                    MessageBox.Show(this, "A build is still running. Stop it and close?", Text, MessageBoxButtons.YesNo) == DialogResult.No) e.Cancel = true;
                else StopBuild();
            };
        }

        // "GSPack 0.4" -> 0.4
        static Version VersionOf(string text)
        {
            if (text == null) return null;
            var m = Regex.Match(text, @"\d+(\.\d+)+");
            return m.Success ? new Version(m.Value) : null;
        }

        string InstalledVersion()
        {
            string f = Path.Combine(serverDirBox.Text, "pack-version.txt");
            try { return File.Exists(f) ? File.ReadAllLines(f)[0].Trim() : null; } catch { return null; }
        }

        void UpdateStatus()
        {
            string inst = InstalledVersion();
            installedLabel.Text = "Installed: " + (inst ?? "nothing yet");
            newestLabel.Text = "On CurseForge: " + (releases.Count > 0 ? releases[0].Name : "(not reachable)");
            Version a = releases.Count > 0 ? VersionOf(releases[0].Name) : null, b = VersionOf(inst);
            updateLabel.Text = (a != null && b != null && a > b) ? "Update available: " + inst + " -> " + releases[0].Name : "";
        }

        void LoadReleases()
        {
            refreshButton.Enabled = false;
            newestLabel.Text = "On CurseForge: checking...";
            ThreadPool.QueueUserWorkItem(delegate {
                var list = new List<PackRelease>();
                try {
                    ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
                    using (var wc = new WebClient()) {
                        wc.Headers[HttpRequestHeader.UserAgent] = "Mozilla/5.0 (GSPack server builder)";
                        wc.Encoding = Encoding.UTF8;
                        var json = new JavaScriptSerializer().Deserialize<Dictionary<string, object>>(wc.DownloadString(string.Format(CfFiles, ProjectId)));
                        foreach (Dictionary<string, object> f in (ArrayList)json["data"]) {
                            string file = (string)f["fileName"];
                            if (!file.EndsWith(".zip", StringComparison.OrdinalIgnoreCase)) continue;
                            DateTime d; DateTime.TryParse((string)f["dateCreated"], out d);
                            list.Add(new PackRelease { Id = Convert.ToInt64(f["id"]), Name = (string)f["displayName"], Date = d });
                        }
                    }
                } catch (Exception ex) {
                    BeginInvoke((Action)delegate { AppendLog("Couldn't reach CurseForge: " + ex.Message + Environment.NewLine); });
                }
                BeginInvoke((Action)delegate {
                    releases = list;
                    versionCombo.Items.Clear();
                    foreach (var r in releases) versionCombo.Items.Add(r);
                    refreshButton.Enabled = true;
                    UpdateStatus();
                });
            });
        }

        void AppendLog(string s)
        {
            log.AppendText(s);
        }

        static string Quote(string s) { return "\"" + s.Replace("\"", "\\\"") + "\""; }

        void Build()
        {
            var args = new StringBuilder("-NoProfile -ExecutionPolicy Bypass -File " + Quote(ScriptPath));
            args.Append(" -OutDir " + Quote(serverDirBox.Text));
            args.Append(" -RamMB " + ((int)ramBox.Value * 1024));
            if (eulaCheck.Checked) args.Append(" -AcceptEula");
            if (!browserCheck.Checked) args.Append(" -NoBrowser");
            if (filesOnlyCheck.Checked) args.Append(" -FilesOnly");
            if (versionRadio.Checked) {
                var r = versionCombo.SelectedItem as PackRelease;
                if (r == null) { MessageBox.Show(this, "Choose a version first.", Text); return; }
                args.Append(" -FileId " + r.Id);
            } else if (zipRadio.Checked) {
                if (!File.Exists(zipBox.Text)) { MessageBox.Show(this, "That zip file doesn't exist.", Text); return; }
                args.Append(" -Zip " + Quote(zipBox.Text));
            }

            log.Clear();
            var psi = new ProcessStartInfo("powershell.exe", args.ToString()) {
                UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = appDir,
                RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage),
                StandardErrorEncoding = Encoding.GetEncoding(System.Globalization.CultureInfo.CurrentCulture.TextInfo.OEMCodePage)
            };
            running = new Process { StartInfo = psi, EnableRaisingEvents = true };
            DataReceivedEventHandler onLine = delegate(object s, DataReceivedEventArgs e) {
                if (e.Data != null) BeginInvoke((Action)delegate { AppendLog(e.Data + Environment.NewLine); });
            };
            running.OutputDataReceived += onLine;
            running.ErrorDataReceived += onLine;
            running.Exited += delegate {
                int code = running.ExitCode;
                BeginInvoke((Action)delegate {
                    AppendLog(Environment.NewLine + (code == 0 ? "Finished." : "Stopped with an error (exit " + code + ").") + Environment.NewLine);
                    SetBusy(false);
                    UpdateStatus();
                });
            };
            SetBusy(true);
            running.Start();
            running.BeginOutputReadLine();
            running.BeginErrorReadLine();
        }

        void StopBuild()
        {
            try { if (running != null && !running.HasExited) Process.Start(new ProcessStartInfo("taskkill", "/PID " + running.Id + " /T /F") { CreateNoWindow = true, UseShellExecute = false }); } catch { }
        }

        void SetBusy(bool busy)
        {
            buildButton.Enabled = !busy;
            stopButton.Enabled = busy;
            startButton.Enabled = !busy;
        }

        // True when the server exists and its EULA is accepted (asks the user if it isn't yet)
        bool ReadyToStart()
        {
            string dir = serverDirBox.Text, eula = Path.Combine(dir, "eula.txt");
            if (!File.Exists(Path.Combine(dir, "start.bat"))) { MessageBox.Show(this, "There is no server yet. Build it first.", Text); return false; }
            bool accepted = File.Exists(eula) && Regex.IsMatch(File.ReadAllText(eula), @"(?m)^eula=true");
            if (!accepted) {
                if (MessageBox.Show(this, "The server only starts after you accept the Minecraft EULA (https://aka.ms/MinecraftEULA).\n\nDo you accept it?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) return false;
                File.WriteAllText(eula, "# https://aka.ms/MinecraftEULA\r\neula=true\r\n");
                eulaCheck.Checked = true;
            }
            return true;
        }

        void StartServer()
        {
            if (console != null && console.ServerRunning) { MessageBox.Show(this, "The server is already running in the server console.", Text); return; }
            if (!ReadyToStart()) return;
            string dir = serverDirBox.Text;
            Process.Start(new ProcessStartInfo(Path.Combine(dir, "start.bat")) { WorkingDirectory = dir, UseShellExecute = true });
            AppendLog("Server started in its own window." + Environment.NewLine);
        }

        void OpenConsole()
        {
            if (console == null || console.IsDisposed) {
                if (!ReadyToStart()) return;
                console = new ConsoleForm(serverDirBox.Text, Icon);
                console.Show(this);
                console.StartServer();
            } else {
                console.Activate();
            }
        }

    }

    // Runs the server inside the program: live log, a command box, and a clean stop.
    class ConsoleForm : Form
    {
        readonly string dir;
        TextBox output, input;
        Button startButton, stopButton, sendButton;
        Label status;
        Process server;
        readonly List<string> history = new List<string>();
        int historyPos;

        public bool ServerRunning { get { return server != null && !server.HasExited; } }

        public ConsoleForm(string serverDir, Icon icon)
        {
            dir = serverDir;
            Text = "GSPack Server Console";
            Icon = icon;
            Font = new Font("Segoe UI", 9f);
            ClientSize = new Size(900, 600);
            MinimumSize = new Size(600, 400);
            StartPosition = FormStartPosition.CenterParent;

            var top = new Panel { Dock = DockStyle.Top, Height = 46 };
            var bottom = new Panel { Dock = DockStyle.Bottom, Height = 46 };
            output = new TextBox { Dock = DockStyle.Fill, Multiline = true, ReadOnly = true, ScrollBars = ScrollBars.Both, WordWrap = false,
                Font = new Font("Consolas", 9f), BackColor = Color.FromArgb(20, 20, 28), ForeColor = Color.Gainsboro, MaxLength = 0 };
            Controls.Add(output);
            Controls.Add(top);
            Controls.Add(bottom);

            startButton = new Button { Text = "Start", Location = new Point(10, 8), Size = new Size(90, 30) };
            startButton.Click += delegate { StartServer(); };
            stopButton = new Button { Text = "Stop", Location = new Point(106, 8), Size = new Size(90, 30), Enabled = false };
            stopButton.Click += delegate { StopServer(); };
            status = new Label { Location = new Point(210, 15), AutoSize = true, Text = "Stopped" };
            top.Controls.AddRange(new Control[] { startButton, stopButton, status });
            // Quick commands, right-aligned
            string[] quick = { "list", "save-all", "tps" };
            for (int i = 0; i < quick.Length; i++) {
                string c = quick[i];
                var b = new Button { Text = c, Size = new Size(80, 30), Location = new Point(top.Width - (quick.Length - i) * 86 - 4, 8), Anchor = AnchorStyles.Top | AnchorStyles.Right };
                b.Click += delegate { Send(c); };
                top.Controls.Add(b);
            }

            bottom.Controls.Add(new Label { Text = "Command:", Location = new Point(10, 15), AutoSize = true });
            input = new TextBox { Location = new Point(80, 11), Size = new Size(bottom.Width - 190, 23), Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top, Font = new Font("Consolas", 9.5f) };
            input.KeyDown += InputKeyDown;
            sendButton = new Button { Text = "Send", Location = new Point(bottom.Width - 100, 9), Size = new Size(90, 28), Anchor = AnchorStyles.Right | AnchorStyles.Top };
            sendButton.Click += delegate { SendInput(); };
            bottom.Controls.AddRange(new Control[] { input, sendButton });
            AcceptButton = sendButton;

            FormClosing += OnClosing;
        }

        void Append(string s)
        {
            // Keep the box from growing without limit on long-running servers
            if (output.TextLength > 2000000) output.Text = output.Text.Substring(output.TextLength - 1000000);
            output.AppendText(s);
        }

        // The java command line from start.bat (without its restart loop)
        bool GetLaunch(out string exe, out string args)
        {
            exe = null; args = null;
            foreach (string line in File.ReadAllLines(Path.Combine(dir, "start.bat"))) {
                if (line.IndexOf("@user_jvm_args.txt", StringComparison.OrdinalIgnoreCase) < 0) continue;
                var m = Regex.Match(line.Trim(), "^\"?(?<exe>[^\"]+?)\"?\\s+(?<args>@user_jvm_args\\.txt.*?)\\s*(%\\*)?$");
                if (!m.Success) return false;
                exe = m.Groups["exe"].Value.Replace("%~dp0", dir.TrimEnd('\\') + "\\");
                args = m.Groups["args"].Value;
                return true;
            }
            return false;
        }

        public void StartServer()
        {
            if (ServerRunning) return;
            string exe, args;
            if (!GetLaunch(out exe, out args)) { MessageBox.Show(this, "Couldn't read the java command from start.bat. Rebuild the server.", Text); return; }
            var psi = new ProcessStartInfo(exe, "-Dstdout.encoding=UTF-8 -Dstderr.encoding=UTF-8 " + args) {
                WorkingDirectory = dir, UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
            };
            server = new Process { StartInfo = psi, EnableRaisingEvents = true };
            DataReceivedEventHandler onLine = delegate(object s, DataReceivedEventArgs e) {
                if (e.Data == null) return;
                string line = e.Data;
                try { BeginInvoke((Action)delegate {
                    Append(line + Environment.NewLine);
                    if (line.Contains("Done (") && line.Contains("For help")) SetStatus("Running", Color.ForestGreen);
                }); } catch (InvalidOperationException) { }
            };
            server.OutputDataReceived += onLine;
            server.ErrorDataReceived += onLine;
            server.Exited += delegate {
                int code = server.ExitCode;
                try { BeginInvoke((Action)delegate {
                    Append(Environment.NewLine + "Server stopped (exit " + code + ")." + Environment.NewLine);
                    SetStatus("Stopped", SystemColors.ControlText);
                    startButton.Enabled = true; stopButton.Enabled = false;
                }); } catch (InvalidOperationException) { }
            };
            output.Clear();
            Append("Starting the server in " + dir + Environment.NewLine + Environment.NewLine);
            server.Start();
            server.BeginOutputReadLine();
            server.BeginErrorReadLine();
            SetStatus("Starting...", Color.DarkOrange);
            startButton.Enabled = false; stopButton.Enabled = true;
            input.Focus();
        }

        void SetStatus(string s, Color c) { status.Text = s; status.ForeColor = c; }

        void Send(string cmd)
        {
            if (!ServerRunning) { Append("(the server isn't running)" + Environment.NewLine); return; }
            Append("> " + cmd + Environment.NewLine);
            server.StandardInput.WriteLine(cmd);
            server.StandardInput.Flush();
        }

        void SendInput()
        {
            string cmd = input.Text.Trim().TrimStart('/');
            if (cmd.Length == 0) return;
            history.Add(cmd); historyPos = history.Count;
            input.Clear();
            Send(cmd);
        }

        void InputKeyDown(object s, KeyEventArgs e)
        {
            // Up/Down walk through earlier commands
            if (e.KeyCode == Keys.Up && historyPos > 0) { historyPos--; input.Text = history[historyPos]; input.SelectionStart = input.TextLength; e.Handled = true; }
            else if (e.KeyCode == Keys.Down && historyPos < history.Count) { historyPos++; input.Text = historyPos < history.Count ? history[historyPos] : ""; input.SelectionStart = input.TextLength; e.Handled = true; }
        }

        void StopServer()
        {
            if (!ServerRunning) return;
            SetStatus("Stopping...", Color.DarkOrange);
            Send("stop");
        }

        void OnClosing(object s, FormClosingEventArgs e)
        {
            if (!ServerRunning) return;
            if (MessageBox.Show(this, "The server is still running. Stop it (saves the world) and close?", Text, MessageBoxButtons.YesNo, MessageBoxIcon.Question) != DialogResult.Yes) { e.Cancel = true; return; }
            StopServer();
            // Give it time to save; kill it only if it hangs
            if (!server.WaitForExit(60000)) { try { server.Kill(); } catch { } }
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
