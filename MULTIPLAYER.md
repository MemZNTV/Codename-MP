# Versus Multiplayer

Two players play the same song against each other over the internet, each on their own copy of the game. Your notes stay lag-free because you only ever play your own side. The other player's side shows their key presses, hits and misses as they arrive.

Everything works with any mod: both players load the same mod, and the song list is that mod's Freeplay list.

## Playing

1. **Host a server** (once, on a PC that stays on): see [multiplayer-server/README.md](multiplayer-server/README.md). It's one Node.js script, no install.
2. In the game choose **Multiplayer** in the main menu (it is added automatically in every mod), or press **F6** from any menu. F6 works even if a mod replaced the main menu.
3. Enter a **username** and the **server address** (`ip` or `ip:port`, port 7777 by default). If the server has a password, enter it too.
4. In the **lobby list** join an open lobby, or press **C** to create your own (optionally with a password). A lobby is titled after the mod its host is playing, and locked lobbies show `[LOCKED]`.
5. In the lobby, each player chooses a **side** (left or right) and **picks a song** from the mod's Freeplay list. Press **Ready**.
6. When both are ready the game **rolls between the two picks** and both screens show the same animation. Then the song loads and both games start the countdown at the same moment.
7. After the song a **results screen** shows both players' score, accuracy, misses, max combo and hit counts, and who won (higher score, then higher accuracy).

During a match the pause menu is disabled (pausing would desync the two games). Press **Esc twice** to forfeit; the other player wins.

## Requirements for both players

- The **same mod** (same version). Both picked songs must exist for both players, because either one can win the roll. The lobby checks a fingerprint of each chart and tells you if yours differs.
- Windows (that's what this feature was built and tested for).

## How it works

- The server (`multiplayer-server/`) only manages lobbies and relays messages. It never simulates the game.
- Each game plays the real song locally. Your side is controlled by you. The other side is a normal strumline that doesn't auto-play: it hits or misses notes exactly when the other player's game says so, using the timing they got.
- The health bar is shared like in normal FNF: your hits pull it towards you, theirs pull it towards them, and both games apply the same events. Nobody can die; the winner is decided by score.
- Score, accuracy, misses and combo are per player and never touch your Freeplay/Story highscores.

Code: [source/funkin/multiplayer/](source/funkin/multiplayer/). The engine itself was changed in a few small places, all marked with "multiplayer" comments:
`PlayState` (countdown handoff, remote hits/misses, no pause/death during matches), `StrumLine` (`remote` strumlines, key-change signal), `FreeplayState` (`goBack` hook) and `MainMenuState` (the menu entry).
Scripts can react to the opponent's misses with `onDadMiss` / `onPostDadMiss` (their hits already trigger `onDadHit`).

## Mods that hide arrows

Some mods hide one side's arrows (usually the left/opponent side). In a match that would hide the arrows of whoever plays that side, so the game moves the hiding to the **opponent's** side instead: if a mod hides the left arrows and you play left, your arrows stay visible and the right side is hidden; if you play right, the left side is hidden as the mod intended. This only changes what is drawn, so the mod's own scripts are unaffected. It catches arrows hidden through the strumline's visibility or by fading the strums/notes to zero alpha; other hiding tricks in a mod's scripts may not be covered.

## Known limitations

- The opponent's animations are delayed by their network latency (usually tens of milliseconds). Your own gameplay is never affected.
- If the two players use different scroll speed options, downscroll etc., each just sees their own settings; the notes are identical.
- A few custom mod mechanics that assume a single human player (e.g. scripts that force-kill the player) still run locally on each side.
