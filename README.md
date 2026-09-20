# Codename MP

> [!IMPORTANT]
> ## This is a **fork of [Codename Engine](https://github.com/CodenameCrew/CodenameEngine)**
> Everything that makes this a game engine (the engine, its editors, its modding system, the art and the base game) is the work of the **[Codename Crew](https://github.com/CodenameCrew)** and its contributors. This repository is an **unofficial** fork that adds one feature on top. It is **not affiliated with or endorsed by** the Codename Crew. Please don't ask them for support with this fork.

> [!WARNING]
> ## This is **vibecoded**
> The multiplayer feature in this fork was written by an AI ([Claude](https://claude.com/claude-code)), directed by a person through conversation, rather than hand-written and reviewed by experienced engine developers. Treat it that way:
> - The server has an automated test suite (38 checks, `multiplayer-server/test`) and the game compiles, but the game side has had **only light manual testing**. Expect bugs and rough edges.
> - Review the code before you trust it with anything that matters. In particular the connection is plain, unencrypted TCP, so **don't reuse a real password** in the server or lobby password fields.
> - Bug reports for the multiplayer feature belong **here**, not in the upstream Codename Engine repository.

## What this fork adds: Versus multiplayer

Two players play the same Friday Night Funkin' song against each other over the internet, each on their own copy of the game, with **any Codename Engine mod**.

- **Lobby browser.** Lobbies are titled after the mod their host is playing, can have a password, and show up live. Usernames are unique.
- **Left or right.** Each player picks a side.
- **Song roll.** Both players pick a song, and when both are ready the game randomly rolls between the two.
- **Lag-free notes.** You only ever play your own side. The opponent's side shows their key presses, hits and misses as they arrive.
- **Results screen.** Score, accuracy, misses, max combo and hit counts for both players, plus the winner.
- **Standalone server.** A small zero-dependency Node.js server you can host at home (port forwarding, no peer-to-peer needed), also available as a single `.exe`.
- **F6** opens multiplayer from any menu, even in mods that replace the main menu.

**Start here:** [MULTIPLAYER.md](MULTIPLAYER.md) (how to play and how it works) and [multiplayer-server/README.md](multiplayer-server/README.md) (hosting a server).
The game-side code is in [`source/funkin/multiplayer`](source/funkin/multiplayer). The engine itself was changed in a few small places, all marked with "multiplayer" comments (`PlayState`, `StrumLine`, `FreeplayState`, `MainMenuState`, `Main`).

Building works exactly like upstream, see [building/README.md](building/README.md). Windows is the only platform this feature has been built on.

## License and credit

Codename Engine is licensed under the [Apache License 2.0](LICENSE), and its authors ask that forks keep credit and say what they are (see *Usage Info* in the original README below). This fork keeps the license and the credits, and it is a fork, not a new engine. All credit for the engine goes to the [Codename Crew](https://github.com/CodenameCrew).

---

# Original Codename Engine README

# Friday Night Funkin' - Codename Engine

![Animated-Banner](https://github.com/user-attachments/assets/5830221d-d954-4be3-afe8-caae364a5881)

Codename Engine is a cross platform [Friday Night Funkin'](https://github.com/FunkinCrew/Funkin) Engine aimed at simplifying modding focusing on softcoding, along with extensiblity and ease of use.<br>
It is the the official successor of the previously well known [Yoshi Engine](https://github.com/CodenameCrew/YoshiCrafterEngine).

The engine uses [HaxeFlixel](https://haxeflixel.com/) and it mainly features:
- A full scripting system with an optimized fork of [Hscript](https://lib.haxe.org/p/hscript/) (its name is [Hscript Improved](https://github.com/CodenameCrew/hscript-improved))
- Uses forks of popular libraries tailored specifically for the engine for the goal of better optimization.
- Modding system and softcoding is as capable as source coding.
- Focuses heavily on optimization, and encourages its users to also take on optimization practices.
- Many modding tools without changing the core gameplay and the base to mod on.
- Allows modularity using addons and mods that apply on top of the core mod.
- Advanced editors which allows for possibly better experience and easiness when creating the mod.
- Much more can be read [HERE](FEATURES.md)

> [!NOTE]
> Please keep in mind that, despite these differences, we do not consider our engine to be any better or worse than the others.

---

> [!CAUTION]
> Want to use this project's code for different purposes or something similar? Check out the ***Usage Info*** part below first, it basically explains what you can do or not do!<br>
> We love open source but we also love proper credits for having respect of all the people who worked hard on this project!!

> [!WARNING]
> Before making issues or if you need help with something, check our website [HERE](https://codename-engine.com/).<br>
> It contains a wiki of how to mod with EXAMPLES, an api, lists of mods made with Codename Engine and more!

> [!TIP]
> Want to stay updated with this project?<br>
> Check out our [patch notes](PATCHNOTES.md)!

---

<img width="1080" height="146" alt="immagine" src="https://github.com/user-attachments/assets/93604082-6bac-4ffc-99b0-5393b1e340a4" />

<br><br>

<img width="1280" height="720" alt="immagine" src="https://github.com/user-attachments/assets/4106f77a-40f8-4159-9f4e-b601cc79e1d0" />
<img width="1280" height="720" alt="immagine" src="https://github.com/user-attachments/assets/2c06f5ea-3462-459b-982e-bf4eddf3d099" />
<img width="1280" height="720" alt="immagine" src="https://github.com/user-attachments/assets/4979e256-6b99-4857-8a2a-96abd94f9c4e" />
<img width="1280" height="720" alt="immagine" src="https://github.com/user-attachments/assets/55a5a710-55b9-4988-bdcc-0977ba1de97a" />
<img width="1280" height="720" alt="immagine" src="https://github.com/user-attachments/assets/4676b035-bec7-445b-a303-78e66f11c479" />

---

> [!NOTE]
> Codename Engine as for now supports **Windows x64**, **Mac OS Universal** and **Linux x64**.<br>
> More platforms will soon come, stay tuned!<br>
> - [ ] **Web (HTML5) Support**
> - [ ] **Mobile Support**

<details>
  <summary><h2>How to download</h2></summary>

  - Stable builds of the engine can be found on our [GameBanana](https://gamebanana.com/mods/598553) or our [itch.io](https://nex-isdumb.itch.io/codename-engine) pages.
  - Latest *EXPERIMENTAL* builds of the engine can be found in the [Actions](https://github.com/CodenameCrew/CodenameEngine/actions) tab. **REQUIRES A GITHUB ACCOUNT!!**

  If you don't have a GitHub account to download experimental builds, you can also go onto our [official website](https://codename-engine.com/) and click the download button for the respective operating system under the **Experimental** section.
</details>

<details>
  <summary><h2>How to mod</h2></summary>

  Check out our wiki [HERE](https://codename-engine.com/wiki/)
</details>

<details>
  <summary><h2>How to setup and build the engine and its documentation</h2></summary>

  Check out our guide [HERE](building/README.md)
</details>

<details>
  <summary><h2>Usage Info</h2></summary>

  ### Feel free to:
  - Download and play the engine with its mods and modpacks
  - Mod and fork the engine (without using it for illicit purposes)
  - Contribute to the engine (for example through *Pull Requests*, *Issues*, etc.)
  - Create a sub engine with Codename Engine as **TEMPLATE** with **CREDITS** (for example leaving the *credits menu submenu with the GitHub contributors* and putting the *[main devs](https://github.com/CodenameCrew)* in a *README* specifying that it's a *sub engine from Codename Engine*)
  - Release excutable mods that use Codename Engine as source (specifing that uses Codename Engine by for example the same way written above this)
  - Release Codename Engine modpacks

  ### Please do not:
  - Create a *side/new/etc* engine (or mod that doesn't use Codename Engine) using Codename Engine's code
  - Steal code from Codename Engine for another different project that is not Codename Engine related (Codename Engine mods excluded) without properly crediting
  - Release the entirety of Codename Engine on platforms (mods that use Codename Engine as source are fine)

  #### *If you need more info or feel like asking to do something which is not listed here, ask us directly on our [discord server](https://discord.gg/codename-crew)!*
</details>

<details>
  <summary><h2>Credits</h2></summary>

- All main Credits can be seen inside the Engine and specifically [HERE](https://github.com/CodenameCrew/CodenameEngine/graphs/contributors)
- Credits to the [FlxAnimate](https://github.com/Dot-Stuff/flxanimate) team for the Animate Atlas support
- Credits to Smokey555 for the backup Animate Atlas to spritesheet code
- Credits to MAJigsaw77 for [hxvlc](https://github.com/MAJigsaw77/hxvlc) (video cutscene/mp4 support) and [hxdiscord_rpc](https://github.com/MAJigsaw77/hxdiscord_rpc) (discord rpc integration)
- Credits to [TheoDev](https://github.com/TheoDevelops) for [FunkinModchart](https://lib.haxe.org/p/funkin-modchart/). ***(library used for modcharting features)***
- Credits to [Ninjamuffin99](https://github.com/ninjamuffin99) and the [Funkin Crew](https://github.com/FunkinCrew) for the base game Friday Night Funkin'
</details>
