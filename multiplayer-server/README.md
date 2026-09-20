# Versus Multiplayer Server

A small lobby and relay server for the multiplayer mode of this Codename Engine fork. It has **no dependencies**: you only need [Node.js](https://nodejs.org) 16 or newer (the LTS version is fine).

It does **not** run the game. Every player plays their own copy of the song, and the server only

- keeps the list of lobbies (each one is titled after the mod its host is playing, and can have its own password),
- pairs two players in a lobby and remembers their side, song pick and ready state,
- randomly picks between the two players' songs when both are ready,
- gives both games the same start time, and passes each player's key presses, hits and misses to the other,
- collects both players' final scores for the results screen.

That means very little bandwidth and no CPU load. A cheap PC or a Raspberry Pi is plenty.

## Running it

Double-click `start-server.bat`, or from a terminal:

```
node server.js
```

Options (all optional):

| Option | Default | What it does |
| --- | --- | --- |
| `--port 7777` | `7777` | TCP port to listen on |
| `--host 0.0.0.0` | `0.0.0.0` | Address to bind to (`127.0.0.1` = this computer only) |
| `--password secret` | none | Password for the **whole server**. Nobody can connect without it |

The same options also work as environment variables: `PORT`, `HOST`, `AFTERNIGHT_PASSWORD`.

### No Node.js on the server PC?

Run `build-exe.bat` once (on any PC that has Node.js) to make `dist\versus-server.exe`. That single file runs anywhere on Windows without installing anything, and takes the same options (`versus-server.exe --port 7777 --password secret`).

## Letting people outside your home network connect

Your players connect **to your computer**, so nothing has to work peer-to-peer between them.

1. **Give the server PC a fixed local address**, in your router settings (a "DHCP reservation"), so port forwarding keeps working after a reboot.
2. **Forward the port.** In your router's port forwarding settings, forward **TCP** port `7777` (or whatever you passed to `--port`) to the server PC's local address.
3. **Allow it through the Windows firewall.** The first time you start the server Windows asks whether to allow Node.js. Allow it on **private networks**. To add the rule yourself, run in an administrator PowerShell:
   ```
   New-NetFirewallRule -DisplayName "Versus server" -Direction Inbound -Protocol TCP -LocalPort 7777 -Action Allow
   ```
4. **Find your public address** (search "what is my IP"), then give players `your.ip.address` or `your.ip.address:7777`.
   - Home IPs change now and then. A free dynamic DNS name (DuckDNS, No-IP) gives you an address like `myname.duckdns.org` that always follows your IP.
   - If your provider uses CGNAT (your router's WAN address differs from the address that "what is my IP" shows), port forwarding can't work. Ask your provider for a public IP, or use a VPN such as Tailscale/ZeroTier so friends connect to your VPN address instead.
5. Test from **outside** your network (a phone on mobile data works). Trying your own public IP from inside your network often fails even when everything is set up correctly.

Players on the same network as the server use the server PC's local address, for example `192.168.1.20`.

## Passwords

There are two independent, optional passwords:

- **Server password** (`--password`): asked for when connecting. Use it if you don't want strangers on your server at all.
- **Lobby password**: chosen by whoever creates a lobby. It shows a `[LOCKED]` marker in the lobby list, and joining asks for the password.

The connection is plain TCP without encryption, so these passwords keep casual visitors out but are not strong security. **Don't reuse a real password** here. Lobby passwords are kept in the server's memory only and are never sent to other players.

## Lobbies and usernames

- A lobby is titled after the mod its **host** is playing, and the title follows the host if they leave and the other player takes over.
- Usernames are unique per server. If someone picks a name that is taken, they get `Name (2)`.
- A lobby holds two players. It disappears when the last one leaves.

## Limits

The server drops connections that misbehave: messages over 16 KB, more than 300 messages per second, no greeting within 10 seconds, or 30 seconds of silence. It allows 64 connections (8 per IP) and 32 lobbies. Change the constants at the top of `server.js` if you need more.

## Testing

```
node test/flow-test.js
```

starts a server on a random port and plays two fake clients through lobbies, passwords, song rolls, a whole match and disconnects.

## Protocol

See [PROTOCOL.md](PROTOCOL.md) if you want to write your own client or bot.
