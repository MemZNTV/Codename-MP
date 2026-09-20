package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.multiplayer.MultiplayerClient.MPPlayer;
import funkin.multiplayer.MultiplayerClient.MPSong;
import funkin.multiplayer.MultiplayerClient.MPStatus;

/**
 * Room lobby: pick your side (left/right), pick a song, press Ready.
 *
 * Both players choose a song. When both are ready the server randomly picks one of the two songs and
 * both screens play the same "roll" animation, then the song loads (handled by `MultiplayerMatch`).
 */
class MultiplayerLobbyState extends MPScreen {
	/** One-shot message shown when the lobby opens (e.g. why a match was cancelled). */
	public static var notice:String = null;

	static inline final ROW_LEFT:Int = 0;
	static inline final ROW_RIGHT:Int = 1;
	static inline final ROW_SONG:Int = 2;
	static inline final ROW_READY:Int = 3;
	static inline final ROW_LEAVE:Int = 4;

	var slotNames:Array<FunkinText> = [];
	var slotInfo:Array<FunkinText> = [];
	var slotPicks:Array<FunkinText> = [];

	var roomText:FunkinText;
	var warnText:FunkinText;
	var rows:Array<FunkinText> = [];
	var rowPanels:Array<FlxSprite> = [];
	var selected:Int = 2; // start on "pick a song"
	var pingTimer:Float = 0;

	// song roll overlay
	var rollGroup:FlxTypedGroup<FlxSprite>;
	var rollHead:FunkinText;
	var rollSong:FunkinText;
	var rollBy:FunkinText;
	var rolling:Bool = false;
	var rollLanded:Bool = false;
	var rollOptions:Array<MPSong>;
	var rollMs:Float = 0;
	var rollTime:Float = 0;
	var rollFlips:Int = 0;
	var rollLastFlip:Int = -1;

	/** The lobby is titled after the mod its host is playing. */
	override function screenTitle():String
		return client.room != null ? client.room.title : "LOBBY";

	override function create() {
		super.create();
		MultiplayerMatch.init();

		roomText = label(0, 92, FlxG.width, "", 22, MPColor.DIM, CENTER);

		// the two side slots, each showing the player and the song they picked
		for (i in 0...2) {
			var x = 130 + i * 530;
			panel(x, 132, 490, 190, 0xFF000000, 0.55);
			label(x + 16, 140, 458, i == 0 ? "LEFT SIDE" : "RIGHT SIDE", 20, MPColor.ACCENT);
			slotNames.push(label(x + 16, 170, 458, "", 34));
			slotInfo.push(label(x + 16, 216, 458, "", 20, MPColor.DIM));
			slotPicks.push(label(x + 16, 254, 458, "", 22));
		}

		warnText = label(130, 330, 1020, "", 18, MPColor.BAD, CENTER);

		for (i in 0...5) {
			var y = 372 + i * 50;
			rowPanels.push(panel(390, y, 500, 42, 0xFF000000, 0.4));
			rows.push(label(390, y + 6, 500, "", 26, MPColor.INFO, CENTER));
		}

		label(0, FlxG.height - 42, FlxG.width, "UP / DOWN: choose      ENTER: select      ESC: leave lobby", 18, MPColor.DIM, CENTER);

		createRollOverlay();

		if (notice != null) {
			setStatus(notice, MPColor.ACCENT);
			notice = null;
		}

		refreshUI();
	}

	function createRollOverlay():Void {
		rollGroup = new FlxTypedGroup<FlxSprite>();
		add(rollGroup);

		var dim = panel(0, 0, FlxG.width, FlxG.height, 0xFF000000, 0.82);
		remove(dim, true);
		rollGroup.add(dim);

		rollHead = label(0, 190, FlxG.width, "", 34, MPColor.ACCENT, CENTER);
		rollSong = label(40, 280, FlxG.width - 80, "", 54, MPColor.INFO, CENTER);
		rollBy = label(0, 380, FlxG.width, "", 26, MPColor.DIM, CENTER);
		for (t in [rollHead, rollSong, rollBy]) {
			remove(t, true);
			rollGroup.add(t);
		}
		rollGroup.visible = false;
	}

	override function handleMessage(m:Dynamic) {
		switch (m.t) {
			case "room":
				refreshUI();
			case "roll":
				startRoll(m.options, m.chosen, m.ms);
			case "abort":
				stopRoll();
				setStatus(m.msg, MPColor.ACCENT);
			case "error":
				// fatal errors are followed by "_closed"; those show up on the connect screen
				if (client.status != MPStatus.Disconnected) setStatus(m.msg, MPColor.BAD);
			case "_closed":
				FlxG.switchState(new MultiplayerMenuState());
		}
	}

	// ------------------------------------------------------------ UI

	static function songLine(s:MPSong):String
		return s == null ? "no song picked yet" : '${s.display}  (${s.diff.toUpperCase()})';

	function refreshUI():Void {
		var room = client.room;
		if (room == null) return;

		titleText.text = room.title; // follows the host's mod if the host changes
		var host:MPPlayer = null;
		for (pl in room.players) if (pl.id == room.host) host = pl;
		roomText.text = 'Host: ${host != null ? host.name : "?"}   ·   ${room.locked ? "password protected   ·   " : ""}${room.players.length}/2 players   ·   ping ${Math.round(client.rtt)} ms';

		// side slots
		var sideNames = ["left", "right"];
		for (i in 0...2) {
			var p:MPPlayer = null;
			for (pl in room.players) if (pl.side == sideNames[i]) p = pl;
			if (p == null) {
				slotNames[i].text = "(empty)";
				slotNames[i].color = MPColor.DIM;
				slotInfo[i].text = "";
				slotPicks[i].text = "";
			} else {
				slotNames[i].text = p.name + (p.id == client.myId ? "  (you)" : "");
				slotNames[i].color = p.id == client.myId ? MPColor.ACCENT : MPColor.INFO;
				slotInfo[i].text = p.ready ? "READY" : "not ready";
				slotInfo[i].color = p.ready ? MPColor.GOOD : MPColor.DIM;
				slotPicks[i].text = "Pick:  " + songLine(p.pick);
				slotPicks[i].color = p.pick == null ? MPColor.DIM : MPColor.INFO;
			}
		}

		// warnings: a missing/different song, or the two players run different mods
		var me = client.me(), opp = client.opponent();
		var warn:String = null;
		for (p in room.players) {
			if (p.pick == null) continue;
			warn = MultiplayerClient.verifySong(p.pick);
			if (warn != null) break;
		}
		var isProblem = warn != null;
		if (warn == null && me != null && opp != null && me.mod != opp.mod)
			warn = 'Heads up: you are on mod "${me.mod}", your opponent is on "${opp.mod}".';
		if (warn == null && opp == null)
			warn = "Waiting for another player to join this lobby...";
		else if (warn == null && me != null && me.pick != null && opp != null && opp.pick != null)
			warn = "When you are both ready, the game randomly picks one of your two songs.";
		warnText.text = warn == null ? "" : warn;
		warnText.color = isProblem ? MPColor.BAD : MPColor.ACCENT;

		// rows
		var mySide = me != null ? me.side : null;
		rows[ROW_LEFT].text = (mySide == "left" ? "[x] " : "[ ] ") + "Play on the LEFT side";
		rows[ROW_RIGHT].text = (mySide == "right" ? "[x] " : "[ ] ") + "Play on the RIGHT side";
		rows[ROW_SONG].text = me != null && me.pick != null ? "Change my song" : "Pick my song";
		rows[ROW_READY].text = (me != null && me.ready) ? "Ready!  (press to cancel)" : "Ready";
		rows[ROW_LEAVE].text = "Leave lobby";
		updateSelection();
	}

	function updateSelection():Void {
		var me = client.me();
		for (i in 0...rows.length) {
			var idle = MPColor.INFO;
			if (i == ROW_READY && me != null && me.ready) idle = MPColor.GOOD;
			rows[i].color = i == selected ? MPColor.ACCENT : idle;
			rowPanels[i].alpha = i == selected ? 0.8 : 0.4;
		}
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (rolling) {
			updateRoll(elapsed);
			if (controls.BACK) leave();
			return;
		}

		// keep the ping display fresh
		pingTimer -= elapsed;
		if (pingTimer <= 0) {
			pingTimer = 1;
			refreshUI();
		}

		if (controls.UP_P || controls.DOWN_P) {
			selected = FlxMath.wrap(selected + (controls.DOWN_P ? 1 : -1), 0, rows.length - 1);
			CoolUtil.playMenuSFX(SCROLL, 0.5);
			updateSelection();
		}

		if (FlxG.mouse.justPressed) {
			for (i in 0...rows.length) if (FlxG.mouse.overlaps(rowPanels[i])) {
				selected = i;
				updateSelection();
				activate(i);
			}
		}

		if (controls.ACCEPT) activate(selected);
		if (controls.BACK) leave();
	}

	// ------------------------------------------------------------ song roll

	function startRoll(options:Array<MPSong>, chosen:Int, ms:Float):Void {
		rolling = true;
		rollLanded = false;
		rollOptions = options;
		rollMs = ms;
		rollTime = 0;
		rollLastFlip = -1;
		setStatus("", MPColor.INFO);

		// Deterministic: the server already decided the winner (`chosen`); both clients just animate towards it.
		// The display flips through the options and eases out, ending exactly on `chosen`.
		var n = options.length;
		rollFlips = n <= 1 ? 0 : 12 + ((chosen - 12) % n + n) % n;

		rollHead.text = n <= 1 ? "" : "ROLLING FOR A SONG...";
		rollHead.color = MPColor.ACCENT;
		rollGroup.visible = true;
		updateRoll(0);
	}

	function stopRoll():Void {
		rolling = false;
		rollGroup.visible = false;
	}

	function updateRoll(elapsed:Float):Void {
		if (rollOptions == null || rollOptions.length == 0) return;
		rollTime += elapsed * 1000;

		var n = rollOptions.length;
		var t = Math.min(1, rollTime / (rollMs * 0.85));
		var flip = Std.int(rollFlips * (1 - Math.sqrt(1 - t)));

		if (flip != rollLastFlip) {
			rollLastFlip = flip;
			var o = rollOptions[flip % n];
			rollSong.text = songLine(o);
			rollBy.text = o.by != null ? 'picked by ${o.by}' : "";
			if (n > 1 && !rollLanded) CoolUtil.playMenuSFX(SCROLL, 0.6);
		}

		if (t >= 1 && !rollLanded) {
			rollLanded = true;
			rollHead.text = n <= 1 ? "You both picked the same song!" : "TONIGHT'S SONG!";
			rollHead.color = MPColor.GOOD;
			rollSong.color = MPColor.GOOD;
			CoolUtil.playMenuSFX(CONFIRM, 0.9);
		}
	}

	// ------------------------------------------------------------ actions

	function activate(row:Int):Void {
		var me = client.me();
		if (me == null) return;

		switch (row) {
			case ROW_LEFT, ROW_RIGHT:
				var side = row == ROW_LEFT ? "left" : "right";
				client.send({t: "side", side: me.side == side ? null : side});
				CoolUtil.playMenuSFX(CONFIRM, 0.6);

			case ROW_SONG:
				CoolUtil.playMenuSFX(CONFIRM, 0.6);
				FlxG.switchState(new MultiplayerFreeplayState());

			case ROW_READY:
				if (me.ready) {
					client.send({t: "ready", ready: false});
					return;
				}
				var opp = client.opponent();
				if (opp == null) return setStatus("Waiting for another player to join the room.", MPColor.BAD);
				if (me.side == null) return setStatus("Pick a side first (left or right).", MPColor.BAD);
				if (opp.side == me.side) return setStatus("You both picked the same side.", MPColor.BAD);
				if (me.pick == null) return setStatus("Pick a song first.", MPColor.BAD);
				if (opp.pick == null) return setStatus('${opp.name} hasn\'t picked a song yet.', MPColor.BAD);
				// either song can win the roll, so we need both
				var problem = MultiplayerClient.verifySong(me.pick);
				if (problem == null) problem = MultiplayerClient.verifySong(opp.pick);
				if (problem != null) return setStatus(problem, MPColor.BAD);
				setStatus("", MPColor.INFO);
				client.send({t: "ready", ready: true});
				CoolUtil.playMenuSFX(CONFIRM, 0.6);

			case ROW_LEAVE:
				leave();
		}
	}

	/** Back to the lobby list (staying connected to the server). */
	function leave():Void {
		client.leaveLobby();
		CoolUtil.playMenuSFX(CANCEL, 0.7);
		FlxG.switchState(new MultiplayerBrowserState());
	}
}
