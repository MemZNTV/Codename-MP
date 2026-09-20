package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.backend.scripting.events.note.NoteHitEvent;
import funkin.backend.scripting.events.note.NoteMissEvent;
import funkin.backend.system.Conductor;
import funkin.game.Note;
import funkin.game.StrumLine;
import funkin.multiplayer.MultiplayerClient.MPSong;
import haxe.Timer;

typedef MPStats = {
	var score:Int;
	var misses:Int;
	/** 0-1, or -1 when nothing has been hit yet */
	var accuracy:Float;
	var combo:Int;
}

/**
 * Glue between a running `PlayState` and the network for a versus match.
 *
 * How it works: every player plays their own copy of the song locally (so their own input never has
 * any lag). The strumline of the *other* player (`StrumLine.remote`) is not auto-played by the bot:
 * instead it replays the other player's key presses, note hits and misses as they arrive from the
 * server. Health is shared, exactly like a normal FNF health bar, since both clients apply the same
 * events. Score/accuracy/misses stay per player.
 *
 * Messages relayed to the opponent (`{t:"g", k:<kind>, ...}`):
 *  - `k`: key pressed/released     `{l:lane, p:1|0}`
 *  - `h`: note hit                 `{l:lane, m:noteTime, d:timingDiffMs}`  (sustain pieces are inferred from the held key)
 *  - `m`: note missed              `{l:lane, m:noteTime|null, su:1|0}`      (`m:null` = ghost tap)
 *  - `s`: live stats               `{sc, ms, ac, cb}`
 */
class MultiplayerMatch {
	/** True from the moment the server tells us to load a song until the results screen is left. PlayState checks this. */
	public static var active(default, null):Bool = false;

	public static var song:MPSong = null;
	public static var mySide:String = "right";

	/** The server's `results` message (both players' final numbers), once both finished. */
	public static var results:Dynamic = null;
	/** This player's own final numbers (what we sent to the server). */
	public static var myResult:Dynamic = null;
	/** Name of the opponent if they left/disconnected during the match. */
	public static var opponentLeft:Null<String> = null;
	/** The opponent's last live stats. */
	public static var oppStats:MPStats = {score: 0, misses: 0, accuracy: -1, combo: 0};
	/** True once our own song ended (or ended early). */
	public static var finished(default, null):Bool = false;

	static var ps:PlayState = null;
	static var local:StrumLine = null;
	static var remote:StrumLine = null;
	static var remoteIndex:Int = -1;

	static var installed:Bool = false;
	static var startAt:Null<Float> = null;
	static var maxCombo:Int = 0;
	static var statsTimer:Float = 0;

	static var pressed:Array<Bool> = [];
	static var justPressed:Array<Bool> = [];
	static var justReleased:Array<Bool> = [];
	static var pending:Array<{msg:Dynamic, expire:Float}> = [];

	static var oppText:FunkinText = null;
	static var hintText:FunkinText = null;
	static var hintTimer:Float = 0;
	static var forfeitTimer:Float = 0;
	static var pauseCooldown:Float = 0;

	static inline final PENDING_TTL:Float = 2; // seconds an early/unmatched hit or miss waits for its note to appear

	/** Hooks the global message handler. Safe to call many times. */
	public static function init():Void {
		if (installed) return;
		installed = true;
		MultiplayerClient.instance.onMessage.add(onMessage);
	}

	static function reset():Void {
		detach();
		results = null;
		myResult = null;
		opponentLeft = null;
		oppStats = {score: 0, misses: 0, accuracy: -1, combo: 0};
		finished = false;
		startAt = null;
		maxCombo = 0;
		statsTimer = 0;
		pending = [];
		pressed = [];
		justPressed = [];
		justReleased = [];
		oppText = hintText = null;
		hintTimer = forfeitTimer = pauseCooldown = 0;
		ps = null;
		local = remote = null;
		remoteIndex = -1;
	}

	/**
	 * Lets go of the PlayState and its strumlines (it's about to be destroyed). Network messages that still
	 * arrive afterwards, like the opponent's last hits, are then ignored instead of touching a dead state.
	 */
	static function detach():Void {
		if (local != null) {
			local.onHit.remove(onLocalHit);
			local.onMiss.remove(onLocalMiss);
			local.onKeyChange.remove(onLocalKey);
		}
		local = null;
		remote = null;
		ps = null;
		pending = [];
	}

	/** Leaves multiplayer mode; PlayState goes back to behaving like a normal game. */
	public static function end():Void {
		reset();
		active = false;
	}

	// ------------------------------------------------------------ server messages

	static function onMessage(m:Dynamic):Void {
		switch (m.t) {
			case "load":
				if (!active) begin(m.song);
			case "start":
				if (active) startAt = m.at; // server clock, ms
			case "g":
				if (active && ps != null) receive(m);
			case "results":
				if (active) results = m;
			case "opp_left":
				if (active) onOpponentLeft(m.name);
			case "abort":
				if (active) {
					var msg:String = m.msg;
					end();
					MultiplayerLobbyState.notice = msg;
					FlxG.switchState(new MultiplayerLobbyState());
				}
			case "_closed", "_fail":
				if (active) {
					end();
					FlxG.switchState(new MultiplayerMenuState());
				}
		}
	}

	/** The server said both players are ready: load the song into PlayState. */
	static function begin(s:MPSong):Void {
		var c = MultiplayerClient.instance;
		var me = c.me();
		if (me == null || me.side == null) { // can't happen (the server only starts with both sides picked), but never crash
			c.leaveLobby();
			FlxG.switchState(new MultiplayerBrowserState());
			return;
		}

		reset();
		active = true;
		song = s;
		mySide = me.side;

		// Left = the "opponent" strumline (type 0), which the engine's opponent mode hands to the player.
		PlayState.loadSong(s.name, s.diff, s.variant, mySide == "left", false);
		FlxG.switchState(new PlayState());
	}

	static function onOpponentLeft(name:String):Void {
		opponentLeft = name == null ? "Opponent" : name;
		if (ps != null && !finished) {
			// cut our own match short and show the results screen with what we have
			finished = true;
			myResult = buildResult(ps);
			detach();
			FlxG.switchState(new MultiplayerResultsState());
		}
	}

	// ------------------------------------------------------------ PlayState hooks

	/** Called from `PlayState.createPost` instead of the normal cutscene/countdown start. */
	public static function onPlayStateReady(p:PlayState):Void {
		ps = p;
		p.playCutscenes = false;
		p.validScore = false; // matches don't touch the solo highscores
		p.canPause = false;
		p.canDie = p.canDadDie = false;

		for (sl in p.strumLines.members) {
			if (sl == null) continue;
			if (sl.remote) remote = sl;
			else if (!sl.cpu) local = sl;
		}

		if (remote != null) {
			remoteIndex = p.strumLines.members.indexOf(remote);
			var keys = remote.members.length;
			pressed = [for (_ in 0...keys) false];
			justPressed = [for (_ in 0...keys) false];
			justReleased = [for (_ in 0...keys) false];
		}

		if (local != null) {
			local.onHit.add(onLocalHit);
			local.onMiss.add(onLocalMiss);
			local.onKeyChange.add(onLocalKey);
		}

		createHud(p);

		// Tell the server we're ready; the countdown begins when it sends the shared start time.
		MultiplayerClient.instance.send({t: "loaded"});
	}

	/** Called every frame from `PlayState.update` while a match is active. */
	public static function update(p:PlayState, elapsed:Float):Void {
		if (p != ps) return;
		var c = MultiplayerClient.instance;

		// scripts may try to turn these back on
		p.canDie = p.canDadDie = false;
		p.canPause = false;

		if (startAt != null && !p.startedCountdown && c.serverNow() >= startAt) {
			startAt = null;
			p.startCountdown();
		}

		processPending();
		updateRemote(p);

		if (p.combo > maxCombo) maxCombo = p.combo;

		statsTimer -= elapsed;
		if (statsTimer <= 0 && p.startedCountdown) {
			statsTimer = 0.25;
			c.send({t: "g", k: "s", sc: p.songScore, ms: p.misses, ac: fin(p.accuracy), cb: p.combo});
		}

		updateHud(p, elapsed);
		checkForfeit(p, elapsed);
	}

	/** Called from `PlayState.nextSong` when our song is over. */
	public static function onSongFinished(p:PlayState):Void {
		if (finished) return;
		finished = true;
		myResult = buildResult(p);
		var r = myResult;
		MultiplayerClient.instance.send({t: "result", score: r.score, misses: r.misses, accuracy: r.accuracy, maxCombo: r.maxCombo, hits: r.hits});
		detach();
		FlxG.switchState(new MultiplayerResultsState());
	}

	static function buildResult(p:PlayState):Dynamic {
		var hits:Dynamic = {};
		for (k => v in p.hits) Reflect.setField(hits, k, v);
		var acc = p.accuracy;
		return {
			score: p.songScore,
			misses: p.misses,
			accuracy: acc < 0 ? 0.0 : fin(acc * 100),
			maxCombo: Std.int(Math.max(maxCombo, p.combo)),
			hits: hits
		};
	}

	// ------------------------------------------------------------ sending (local player)

	static function onLocalKey(lane:Int, down:Bool):Void
		MultiplayerClient.instance.send({t: "g", k: "k", l: lane, p: down ? 1 : 0});

	static function onLocalHit(e:NoteHitEvent):Void {
		var n = e.note;
		if (n == null || n.isSustainNote) return; // held sustains are inferred by the other side from the key state
		MultiplayerClient.instance.send({t: "g", k: "h", l: n.strumID, m: fin(n.strumTime), d: fin(Math.abs(Conductor.songPosition - n.strumTime))});
	}

	static function onLocalMiss(e:NoteMissEvent):Void {
		var n = e.note;
		MultiplayerClient.instance.send({t: "g", k: "m", l: e.direction, m: n == null ? null : fin(n.strumTime), su: (n != null && n.isSustainNote) ? 1 : 0});
	}

	/** NaN/Infinity are not valid JSON. */
	static inline function fin(f:Float):Float
		return Math.isFinite(f) ? f : 0;

	// ------------------------------------------------------------ receiving (remote player)

	static function receive(m:Dynamic):Void {
		switch (m.k) {
			case "k":
				var l:Int = m.l;
				if (l < 0 || l >= pressed.length) return;
				if (m.p == 1) {
					pressed[l] = true;
					justPressed[l] = true;
				} else {
					pressed[l] = false;
					justReleased[l] = true;
				}
			case "h", "m":
				// may arrive before the matching note is active on this screen: retry for a moment
				if (!apply(m)) pending.push({msg: m, expire: Timer.stamp() + PENDING_TTL});
			case "s":
				oppStats = {score: Std.int(m.sc), misses: Std.int(m.ms), accuracy: m.ac, combo: Std.int(m.cb)};
		}
	}

	static function processPending():Void {
		if (pending.length == 0) return;
		var now = Timer.stamp();
		var keep = [];
		for (p in pending) {
			if (apply(p.msg)) continue;
			if (p.expire > now) keep.push(p);
		}
		pending = keep;
	}

	/** Plays the other player's hit/miss on their strumline. Returns false if the note isn't there (yet). */
	static function apply(m:Dynamic):Bool {
		if (remote == null || ps == null) return true; // nothing to apply it to

		var lane:Int = m.l;
		if (m.k == "h") {
			var note = findNote(lane, m.m, false);
			if (note == null) return false;
			ps.goodNoteHit(remote, note, m.d);
			return true;
		}

		// miss
		if (m.m == null) { // ghost tap
			ps.noteMiss(remote, null, lane, remoteIndex);
			return true;
		}
		var note = findNote(lane, m.m, m.su == 1);
		if (note == null) return false;
		ps.noteMiss(remote, note);
		return true;
	}

	/** Finds the remote strumline's not-yet-resolved note in a lane at (almost) the given time. */
	static function findNote(lane:Int, time:Float, sustain:Bool):Null<Note> {
		var best:Note = null;
		var bestDist = 4.0; // ms; charts round-trip through JSON so allow a little slack
		remote.notes.forEachAlive(function(n:Note) {
			if (n.strumID != lane || n.isSustainNote != sustain || n.wasGoodHit) return;
			var d = Math.abs(n.strumTime - time);
			if (d < bestDist) {
				bestDist = d;
				best = n;
			}
		});
		return best;
	}

	/** Per-frame: sustains follow the held key, strums animate like a real player's. */
	static function updateRemote(p:PlayState):Void {
		if (remote == null) return;

		if (p.startedCountdown && pressed.contains(true)) {
			remote.notes.forEachAlive(function(n:Note) {
				if (n.isSustainNote && !n.wasGoodHit && pressed[n.strumID] && n.strumTime <= Conductor.songPosition
					&& n.sustainParent != null && n.sustainParent.wasGoodHit)
					p.goodNoteHit(remote, n, 0);
			});
		}

		for (i => strum in remote.members) {
			if (strum == null || i >= pressed.length) continue;
			strum.updatePlayerInput(pressed[i], justPressed[i], justReleased[i]);
			justPressed[i] = justReleased[i] = false;
		}
	}

	// ------------------------------------------------------------ HUD / forfeit

	static function createHud(p:PlayState):Void {
		// Sits in the gap between the two strumlines so it never covers notes.
		oppText = new FunkinText(FlxG.width * 0.5 - 100, 8, 200, "", 18);
		oppText.alignment = CENTER;
		oppText.scrollFactor.set();
		oppText.cameras = [p.camHUD];
		p.add(oppText);

		hintText = new FunkinText(0, FlxG.height * 0.4, FlxG.width, "", 28);
		hintText.alignment = CENTER;
		hintText.scrollFactor.set();
		hintText.cameras = [p.camHUD];
		hintText.alpha = 0;
		p.add(hintText);
	}

	static function updateHud(p:PlayState, elapsed:Float):Void {
		if (oppText != null) {
			var opp = MultiplayerClient.instance.opponent();
			var name = opp != null ? opp.name : "Opponent";
			var acc = oppStats.accuracy < 0 ? "-" : Std.string(CoolUtil.quantize(oppStats.accuracy * 100, 100)) + "%";
			oppText.text = '$name\n${oppStats.score}\n$acc  |  ${oppStats.misses} miss${oppStats.misses == 1 ? "" : "es"}';
		}
		if (hintText != null && hintTimer > 0) {
			hintTimer -= elapsed;
			hintText.alpha = Math.min(1, hintTimer * 2);
		}
	}

	/** ESC/pause twice within 2 seconds forfeits (pausing would desync the match). */
	static function checkForfeit(p:PlayState, elapsed:Float):Void {
		pauseCooldown -= elapsed;
		if (forfeitTimer > 0) forfeitTimer -= elapsed;
		if (!p.controls.PAUSE || pauseCooldown > 0 || finished) return;
		pauseCooldown = 0.3;

		if (forfeitTimer > 0) {
			forfeit();
			return;
		}
		forfeitTimer = 2;
		if (hintText != null) {
			hintText.text = "Press again to forfeit the match";
			hintTimer = 2;
			hintText.alpha = 1;
		}
	}

	/** Leaves the match (the opponent wins by forfeit) and returns to the lobby list, still connected. */
	public static function forfeit():Void {
		MultiplayerClient.instance.leaveLobby();
		end();
		FlxG.switchState(new MultiplayerBrowserState());
	}
}
