# Protocol (version 2)

TCP. Every message is one JSON object on one line, UTF-8, ending in `\n`. Every object has a type field `t`.
Unknown message types are ignored. A line may not exceed 16 KB.

## Connecting

```
C -> S  {"t":"hello","v":2,"name":"Alice","mod":"my-mod","pass":"<server password, if any>"}
S -> C  {"t":"welcome","id":7,"name":"Alice","v":2,"serverTime":1718000000000}
S -> C  {"t":"lobbies","lobbies":[...]}
```

`hello` must be the first message. `name` is made unique by the server (`Alice (2)`), the welcome carries the final name.
`mod` is the mod folder the player runs; a lobby is titled after its host's mod.
Fatal problems come as `{"t":"error","code":"...","msg":"...","fatal":true}` followed by the server closing the connection
(`version`, `bad_password`, `busy`, `timeout`, `too_big`, `flood`, `protocol`).

### Clock sync and keep-alive

```
C -> S  {"t":"ping","c":<client ms>,"p":<last measured rtt>}
S -> C  {"t":"pong","c":<same client ms>,"s":<server ms>}
```

Send one every ~2 seconds (the server drops silent clients after 30 s). With the round trip time `rtt = now - c`,
the server clock is `s + rtt/2 - now` ahead of the client's; keep the sample with the smallest rtt.

## Lobby list (while not inside a lobby)

```
S -> C  {"t":"lobbies","lobbies":[{"id":3,"title":"my-mod","host":"Alice","players":1,"max":2,"locked":true,"state":"lobby"}]}
C -> S  {"t":"lobbies"}                                  refresh (the server also pushes changes by itself)
C -> S  {"t":"create","password":"","mod":"my-mod"}      open a lobby; empty password = open lobby
C -> S  {"t":"join","id":3,"password":"","mod":"my-mod"}
S -> C  {"t":"joined","id":3}                            followed by a "room" snapshot
```

`state` is `lobby | rolling | loading | playing`; only `lobby` can be joined.
Refused requests (non-fatal errors): `lobby_password`, `lobby_full`, `lobby_busy`, `no_lobby`, `too_many_lobbies`.

## Inside a lobby

The server sends a full snapshot after every change:

```
S -> C  {"t":"room","id":3,"title":"my-mod","locked":true,"state":"lobby","host":7,"song":null,
         "players":[{"id":7,"name":"Alice","side":"left","ready":false,"pick":{...}|null,"mod":"my-mod","ping":31}, ...]}
```

`players[0]` is the host. A pick is `{"name","diff","variant","display","hash"}`.

```
C -> S  {"t":"side","side":"left"|"right"|null}          error "side_taken" if the other player has it
C -> S  {"t":"song","name":"bopeebo","diff":"hard","variant":null,"display":"Bopeebo","hash":"<chart md5>"}   your pick
C -> S  {"t":"ready","ready":true}
C -> S  {"t":"leave_lobby"}                              back to the lobby list; mid-match this is a forfeit
```

Changing your side or song, or someone joining/leaving, clears everybody's ready flag.

## Starting a match

When both players are ready, both have a pick, and the sides differ:

```
S -> C  {"t":"roll","options":[<pick A + "by":"Alice">,<pick B + "by":"Bob">],"chosen":1,"ms":3800}
```

`chosen` indexes `options` (identical picks are sent as a single option). All clients show a roll animation of `ms` milliseconds, ending on `chosen`.
About 600 ms after the animation the server continues:

```
S -> C  {"t":"load","song":{...chosen pick, "by":"Bob"}}
C -> S  {"t":"loaded"}                                   once the song is loaded and the countdown could start
S -> C  {"t":"start","at":<server ms>}                   after both loaded; begin the countdown at that server time
```

Either step can be cancelled with `{"t":"abort","code":"...","msg":"..."}` (a player left, or loading took over 45 s); everyone returns to the lobby.

## During a match

Anything a client sends as `{"t":"g", ...}` is relayed unchanged to the other player (only during `loading`/`playing`). The game uses:

| `k` | Meaning | Fields |
| --- | --- | --- |
| `k` | key pressed or released | `l` lane, `p` 1 = down / 0 = up |
| `h` | note hit | `l` lane, `m` note time (ms), `d` timing difference (ms) |
| `m` | note missed | `l` lane, `m` note time or `null` (ghost tap), `su` 1 if a sustain piece |
| `s` | live stats (4 per second) | `sc` score, `ms` misses, `ac` accuracy 0-1 (-1 = none yet), `cb` combo |

At the end of the song each client reports its final numbers:

```
C -> S  {"t":"result","score":12000,"misses":1,"accuracy":96.2,"maxCombo":80,"hits":{"sick":70,"good":3}}
S -> C  {"t":"results","players":{"<id>":{"name","side","score","misses","accuracy","maxCombo","hits"}, ...}}    when both reported
```

If the opponent leaves or disconnects while playing: `{"t":"opp_left","id":7,"name":"Alice","reason":"left"|"disconnect"}`.
After `results`, `opp_left` or `abort` the lobby is back in the `lobby` state with everybody unready.
