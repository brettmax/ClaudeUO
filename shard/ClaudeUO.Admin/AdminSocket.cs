using System;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Server;
using Server.Logging;

namespace ClaudeUO.Admin;

// Localhost-only TCP control surface for the restart-scheduler running outside the process.
// Auto-started by ModernUO via the static Configure() entry point (see Main.cs:441
// AssemblyHandler.Invoke("Configure")).
//
// Commands are plain ASCII, one per line, terminated with \n:
//   PING                       -> "PONG"
//   BROADCAST <hue> <text>     -> World.Broadcast(hue, true, text)
//   RESTART                    -> Core.Kill(true)   (clean shutdown + restart loop)
//   SHUTDOWN                   -> Core.Kill(false)  (clean shutdown, no restart)
//
// Port and bind address come from modernuo.json settings, defaulting to 127.0.0.1:2595.
// Refusing non-loopback binds keeps the socket reachable only from the deploy host.
public static class AdminSocket
{
    private static readonly ILogger _log = LogFactory.GetLogger(typeof(AdminSocket));

    private static TcpListener? _listener;
    private static CancellationTokenSource? _cts;
    private static Task? _acceptLoop;

    public static void Configure()
    {
        var bind = ServerConfiguration.GetOrUpdateSetting("claudeuo.adminBind", "127.0.0.1");
        var port = ServerConfiguration.GetOrUpdateSetting("claudeuo.adminPort", 2595);

        if (!IPAddress.TryParse(bind, out var ip))
        {
            _log.Error("ClaudeUO admin socket: invalid bind address {Bind}; refusing to start", bind);
            return;
        }

        // Hard guard: never expose this socket beyond loopback. The restart scheduler runs
        // on the same host; remote access belongs to SSH + the deploy user, not to this socket.
        if (!IPAddress.IsLoopback(ip))
        {
            _log.Error("ClaudeUO admin socket refusing to bind to non-loopback address {Bind}", bind);
            return;
        }

        _cts = new CancellationTokenSource();
        _listener = new TcpListener(ip, port);
        _listener.Start();
        _acceptLoop = Task.Run(() => AcceptLoop(_cts.Token));

        _log.Information("ClaudeUO admin socket listening on {Bind}:{Port}", bind, port);
    }

    private static async Task AcceptLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            TcpClient client;
            try
            {
                client = await _listener!.AcceptTcpClientAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { return; }
            catch (ObjectDisposedException) { return; }
            catch (Exception ex)
            {
                _log.Error(ex, "ClaudeUO admin socket: accept failed");
                continue;
            }

            _ = Task.Run(() => HandleClient(client, ct), ct);
        }
    }

    private static async Task HandleClient(TcpClient client, CancellationToken ct)
    {
        using (client)
        {
            try
            {
                using var stream = client.GetStream();
                var buf = new byte[1024];
                var sb = new StringBuilder();

                while (!ct.IsCancellationRequested)
                {
                    int n = await stream.ReadAsync(buf.AsMemory(0, buf.Length), ct).ConfigureAwait(false);
                    if (n <= 0) return;

                    sb.Append(Encoding.ASCII.GetString(buf, 0, n));

                    string s = sb.ToString();
                    int nl;
                    while ((nl = s.IndexOf('\n')) >= 0)
                    {
                        var line = s[..nl].TrimEnd('\r').Trim();
                        s = s[(nl + 1)..];

                        if (line.Length > 0)
                        {
                            var reply = Dispatch(line);
                            var bytes = Encoding.UTF8.GetBytes(reply + "\n");
                            await stream.WriteAsync(bytes.AsMemory(0, bytes.Length), ct).ConfigureAwait(false);
                        }
                    }
                    sb.Clear();
                    sb.Append(s);
                }
            }
            catch (OperationCanceledException) { }
            catch (Exception ex)
            {
                _log.Warning(ex, "ClaudeUO admin socket: client handler error");
            }
        }
    }

    private static string Dispatch(string line)
    {
        var sp = line.IndexOf(' ');
        var cmd = (sp < 0 ? line : line[..sp]).ToUpperInvariant();
        var rest = sp < 0 ? string.Empty : line[(sp + 1)..];

        switch (cmd)
        {
            case "PING":
                return "PONG";

            case "BROADCAST":
            {
                // Format: BROADCAST <hue> <message...>
                var sp2 = rest.IndexOf(' ');
                if (sp2 < 0)
                {
                    return "ERR usage: BROADCAST <hue> <message>";
                }
                var hueText = rest[..sp2];
                var msg = rest[(sp2 + 1)..];
                if (!int.TryParse(hueText, out var hue))
                {
                    return "ERR hue must be integer";
                }
                if (string.IsNullOrWhiteSpace(msg))
                {
                    return "ERR empty message";
                }

                // World.Broadcast is not thread-safe; hop onto the game loop.
                Core.LoopContext.Post(() => World.Broadcast(hue, true, msg));
                return "OK";
            }

            case "RESTART":
                Core.LoopContext.Post(() => Core.Kill(true));
                return "OK restarting";

            case "SHUTDOWN":
                Core.LoopContext.Post(() => Core.Kill(false));
                return "OK shutting down";

            default:
                return "ERR unknown command";
        }
    }
}
