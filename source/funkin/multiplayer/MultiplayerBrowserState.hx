package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.multiplayer.MultiplayerClient.MPLobby;
import funkin.multiplayer.MultiplayerClient.MPStatus;

/**
 * The lobby list of the server. Every open lobby is titled after the mod its host is playing and shows
 * whether it needs a password. Join one (ENTER), or open your own (C) with an optional password.
 * The list updates live.
 */
class MultiplayerBrowserState extends MPScreen {
	static inline final VISIBLE_ROWS:Int = 7;
	static inline final ROW_H:Int = 62;
	static inline final LIST_Y:Int = 150;

	// password prompt modes
	static inline final PROMPT_NONE:Int = 0;
	static inline final PROMPT_JOIN:Int = 1;
	static inline final PROMPT_CREATE:Int = 2;

	var infoText:FunkinText;
	var emptyText:FunkinText;

	var rowPanels:Array<FlxSprite> = [];
	var rowTitles:Array<FunkinText> = [];
	var rowInfo:Array<FunkinText> = [];

	var selected:Int = 0;
	var top:Int = 0; // first visible lobby (for scrolling)
	var pingTimer:Float = 0;

	// password prompt overlay
	var promptGroup:FlxTypedGroup<FlxSprite>;
	var promptTitle:FunkinText;
	var promptBox:FlxSprite;
	var promptText:FunkinText;
	var promptHint:FunkinText;
	var promptMode:Int = PROMPT_NONE;
	var promptLobby:MPLobby;
	var input:MPTextInput = new MPTextInput(32);

	override function screenTitle():String
		return "LOBBIES";

	override function create() {
		super.create();
		MultiplayerMatch.init();

		infoText = label(0, 92, FlxG.width, "", 22, MPColor.DIM, CENTER);

		for (i in 0...VISIBLE_ROWS) {
			var y = LIST_Y + i * ROW_H;
			rowPanels.push(panel(160, y, 960, ROW_H - 8, 0xFF000000, 0.45));
			rowTitles.push(label(178, y + 8, 560, "", 30));
			rowInfo.push(label(600, y + 14, 502, "", 20, MPColor.DIM, RIGHT));
		}
		emptyText = label(0, 300, FlxG.width, "No lobbies yet.\nPress C to open the first one!", 30, MPColor.DIM, CENTER);

		label(0, FlxG.height - 42, FlxG.width, "UP / DOWN: choose      ENTER: join      C: create lobby      R: refresh      ESC: disconnect", 18, MPColor.DIM, CENTER);

		createPrompt();
		input.onChange = refreshPrompt;

		client.refreshLobbies();
		refreshUI();
	}

	override function destroy() {
		input.destroy();
		super.destroy();
	}

	// ------------------------------------------------------------ list

	function refreshUI():Void {
		var lobbies = client.lobbies;
		infoText.text = 'Signed in as ${client.myName}   ·   ping ${Math.round(client.rtt)} ms   ·   playing "${MultiplayerClient.currentMod() == "" ? "Base game" : MultiplayerClient.currentMod()}"';

		selected = lobbies.length == 0 ? 0 : Std.int(FlxMath.bound(selected, 0, lobbies.length - 1));
		if (selected < top) top = selected;
		if (selected >= top + VISIBLE_ROWS) top = selected - VISIBLE_ROWS + 1;
		top = Std.int(Math.max(0, Math.min(top, lobbies.length - VISIBLE_ROWS)));

		emptyText.visible = lobbies.length == 0;

		for (i in 0...VISIBLE_ROWS) {
			var idx = top + i;
			var has = idx < lobbies.length;
			rowPanels[i].visible = rowTitles[i].visible = rowInfo[i].visible = has;
			if (!has) continue;

			var l = lobbies[idx];
			var joinable = l.state == "lobby" && l.players < l.max;
			rowTitles[i].text = l.title + (l.locked ? "   [LOCKED]" : "");
			rowInfo[i].text = 'host: ${l.host}     ${l.players}/${l.max}     ${stateLabel(l)}';

			var sel = idx == selected;
			rowPanels[i].alpha = sel ? 0.85 : 0.45;
			rowTitles[i].color = sel ? MPColor.ACCENT : (joinable ? MPColor.INFO : MPColor.DIM);
			rowInfo[i].color = joinable ? (sel ? MPColor.INFO : MPColor.DIM) : MPColor.BAD;
		}
	}

	static function stateLabel(l:MPLobby):String {
		if (l.state != "lobby") return "IN MATCH";
		return l.players >= l.max ? "FULL" : "OPEN";
	}

	override function handleMessage(m:Dynamic) {
		switch (m.t) {
			case "lobbies":
				refreshUI();
			case "joined":
				FlxG.switchState(new MultiplayerLobbyState());
			case "error":
				// join refused (wrong password / full / gone) - the connection stays open
				if (client.status != MPStatus.Disconnected) {
					setStatus(m.msg, MPColor.BAD);
					if (m.code == "lobby_password" && promptLobby != null) openPrompt(PROMPT_JOIN, promptLobby);
				}
			case "_closed":
				FlxG.switchState(new MultiplayerMenuState());
		}
	}

	// ------------------------------------------------------------ password prompt

	function createPrompt():Void {
		promptGroup = new FlxTypedGroup<FlxSprite>();
		add(promptGroup);

		var dim = panel(0, 0, FlxG.width, FlxG.height, 0xFF000000, 0.8);
		var boxX = (FlxG.width - 600) / 2;
		promptBox = panel(boxX, 320, 600, 50, 0xFF202848, 1);
		promptTitle = label(0, 230, FlxG.width, "", 30, MPColor.INFO, CENTER);
		promptText = label(boxX + 12, 330, 576, "", 28);
		promptHint = label(0, 400, FlxG.width, "ENTER: confirm      ESC: cancel", 18, MPColor.DIM, CENTER);

		for (o in [dim, promptBox, promptTitle, promptText, promptHint]) {
			remove(o, true);
			promptGroup.add(o);
		}
		promptGroup.visible = false;
	}

	function openPrompt(mode:Int, lobby:MPLobby):Void {
		promptMode = mode;
		promptLobby = lobby;
		promptTitle.text = mode == PROMPT_CREATE ? "Lobby password  (leave empty for an open lobby)" : 'Password for "${lobby.title}"';
		input.value = "";
		input.enabled = true;
		promptGroup.visible = true;
		refreshPrompt();
	}

	function closePrompt():Void {
		promptMode = PROMPT_NONE;
		input.enabled = false;
		promptGroup.visible = false;
	}

	function refreshPrompt():Void {
		var caret = (FlxG.game.ticks % 1000) < 500 ? "|" : "";
		promptText.text = [for (_ in 0...input.value.length) "*"].join("") + caret;
	}

	function confirmPrompt():Void {
		var pw = input.value;
		var mode = promptMode;
		var lobby = promptLobby;
		closePrompt();
		if (mode == PROMPT_CREATE) {
			setStatus("Creating lobby...", MPColor.INFO);
			client.createLobby(pw);
		} else if (lobby != null) {
			setStatus('Joining "${lobby.title}"...', MPColor.INFO);
			client.joinLobby(lobby.id, pw);
		}
	}

	// ------------------------------------------------------------ input

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (promptMode != PROMPT_NONE) {
			input.update(elapsed);
			refreshPrompt();
			if (FlxG.keys.justPressed.ESCAPE) closePrompt();
			else if (FlxG.keys.justPressed.ENTER) confirmPrompt();
			return;
		}

		// keep the ping display fresh
		pingTimer -= elapsed;
		if (pingTimer <= 0) {
			pingTimer = 1;
			refreshUI();
		}

		var k = FlxG.keys;
		var lobbies = client.lobbies;

		if (k.justPressed.ESCAPE) return disconnect();
		if (k.justPressed.C) return openPrompt(PROMPT_CREATE, null);
		if (k.justPressed.R) {
			client.refreshLobbies();
			setStatus("Refreshed.", MPColor.DIM);
		}

		if (lobbies.length > 0) {
			var d = (k.justPressed.DOWN ? 1 : 0) - (k.justPressed.UP ? 1 : 0) - FlxG.mouse.wheel;
			if (d != 0) {
				selected = FlxMath.wrap(selected + Std.int(d), 0, lobbies.length - 1);
				CoolUtil.playMenuSFX(SCROLL, 0.5);
				refreshUI();
			}

			if (FlxG.mouse.justPressed) {
				for (i in 0...VISIBLE_ROWS) if (rowPanels[i].visible && FlxG.mouse.overlaps(rowPanels[i])) {
					if (selected == top + i) join(lobbies[selected]);
					selected = top + i;
					refreshUI();
					break;
				}
			}

			if (k.justPressed.ENTER) join(lobbies[selected]);
		}
	}

	function join(l:MPLobby):Void {
		if (l == null) return;
		if (l.state != "lobby") return setStatus("That lobby is in the middle of a match.", MPColor.BAD);
		if (l.players >= l.max) return setStatus("That lobby is full.", MPColor.BAD);
		CoolUtil.playMenuSFX(CONFIRM, 0.6);
		promptLobby = l;
		if (l.locked) openPrompt(PROMPT_JOIN, l);
		else {
			setStatus('Joining "${l.title}"...', MPColor.INFO);
			client.joinLobby(l.id, "");
		}
	}

	function disconnect():Void {
		client.disconnect();
		goToMainMenu();
	}
}
