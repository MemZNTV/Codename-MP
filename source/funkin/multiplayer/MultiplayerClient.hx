package funkin.multiplayer;

import flixel.util.FlxSignal.FlxTypedSignal;
import funkin.backend.assets.ModsFolder;
import funkin.backend.chart.Chart;
import haxe.Json;
import haxe.Timer;
import haxe.crypto.Md5;
import haxe.io.Bytes;
import haxe.io.BytesOutput;
import sys.net.Host;
import sys.net.Socket;
import sys.thread.Deque;
import sys.thread.Thread;

typedef MPPlayer = {
	var id:Int;
	var name:String;
	var side:Null<String>;
	var ready:Bool;
	/** The song this player wants to play (one of the two picks gets rolled when both are ready). */
	var pick:Null<MPSong>;
	var mod:String;
	var ping:Int;
}

typedef MPSong = {
	var name:String;
	var diff:String;
	var variant:Null<String>;
	var display:String;
	var hash:String;
	/** Name of the player who picked it (only set on the rolled/loaded song). */
	@:optional var by:String;
}

/** One row of the lobby browser. */
typedef MPLobby = {
	var id:Int;
	/** Named after the mod the host is playing. */
	var title:String;
	var host:String;
	var players:Int;
	var max:Int;
	var locked:Bool;
	/** lobby | rolling | loading | playing */
	var state:String;
}

typedef MPRoom = {
	var id:Int;
	/** Named after the mod the host is playing. */
	var title:String;
	var locked:Bool;
	var state:String;
	var host:Int;
	var song:Null<MPSong>;
	var players:Array<MPPlayer>;
}

enum MPStatus {
	Disconnected;
	Connecting;
	Connected;
}

/**
 * Connection to the versus server (see `multiplayer-server/`).
 *
 * Transport is plain TCP with one JSON object per line. A background thread does all the blocking
 * socket reads and pushes parsed messages into a queue, which is drained on the main thread once per
 * frame (so all the game code only ever runs on the main thread).
 *
 * Listen to everything the server says with `onMessage`. Room snapshots are kept in `room`.
 */
class MultiplayerClient {
	public static inline final PROTOCOL_VERSION:Int = 2;
	public static inline final DEFAULT_PORT:Int = 7777;

	static var __instance:MultiplayerClient;
	public static var instance(get, never):MultiplayerClient;
	static function get_instance():MultiplayerClient {
		if (__instance == null) __instance = new MultiplayerClient();
		return __instance;
	}

	public var status(default, null):MPStatus = Disconnected;
	/** Our id on the server. 0 until the server welcomed us. */
	public var myId(default, null):Int = 0;
	/** Our username as the server registered it (usernames are unique, so it may differ from what was typed). */
	public var myName(default, null):String = "";
	/** Latest list of open lobbies (updated live by the server while we're not inside one). */
	public var lobbies(default, null):Array<MPLobby> = [];
	/** Latest room snapshot from the server. */
	public var room(default, null):MPRoom = null;
	/** Human readable reason for the last failure/disconnect (null if none). */
	public var lastError(default, null):String = null;
	/** Last measured round trip time in ms. */
	public var rtt(default, null):Float = 0;

	/** Dispatched (on the main thread) for every server message, after the client processed it. Internal messages: `_fail`, `_closed`. */
	public var onMessage:FlxTypedSignal<Dynamic->Void> = new FlxTypedSignal<Dynamic->Void>();

	var socket:Socket = null;
	var queue:Deque<Dynamic> = new Deque<Dynamic>();
	var gen:Int = 0; // bumped on every connect/disconnect so stale threads are ignored

	// clock sync
	var serverOffset:Float = 0; // serverMs - localMs
	var samples:Array<{rtt:Float, offset:Float}> = [];
	var pingTimer:Float = 0;
	var quickPings:Int = 0;

	static var chartHashCache:Map<String, String> = [];

	function new() {
		FlxG.signals.preUpdate.add(pump);
	}

	public static inline function nowMs():Float
		return Timer.stamp() * 1000;

	/** Estimated current time on the server clock, in ms. */
	public inline function serverNow():Float
		return nowMs() + serverOffset;

	// ------------------------------------------------------------ connection

	/** The mod folder currently loaded; sent to the server so it can title the lobby after it. */
	public static function currentMod():String
		return ModsFolder.currentModFolder == null ? "" : ModsFolder.currentModFolder;

	public function connect(host:String, port:Int, name:String, serverPassword:String):Void {
		disconnect();
		final myGen = gen;
		status = Connecting;
		lastError = null;
		chartHashCache.clear();

		final hello = {
			t: "hello",
			v: PROTOCOL_VERSION,
			name: name,
			pass: serverPassword,
			mod: currentMod()
		};

		Thread.create(function() {
			var s:Socket = null;
			try {
				s = new Socket();
				s.connect(new Host(host), port);
				s.setFastSend(true);
				if (myGen != gen) { // cancelled while connecting
					s.close();
					return;
				}
				socket = s;
				s.output.writeString(Json.stringify(hello) + "\n");
			} catch (e) {
				try if (s != null) s.close() catch (_) {}
				if (myGen == gen)
					queue.add({gen: myGen, msg: {t: "_fail", msg: 'Could not connect to $host:$port.'}});
				return;
			}

			// blocking read loop; lines are assembled from raw bytes so nothing is lost or split
			var buf = Bytes.alloc(4096);
			var line = new BytesOutput();
			var lineLen = 0;
			try {
				while (myGen == gen) {
					var n = s.input.readBytes(buf, 0, buf.length);
					for (i in 0...n) {
						var b = buf.get(i);
						if (b == 10) {
							if (lineLen > 0) {
								var str = line.getBytes().toString();
								try queue.add({gen: myGen, msg: Json.parse(str)}) catch (_) {}
							}
							line = new BytesOutput();
							lineLen = 0;
						} else {
							line.writeByte(b);
							if (++lineLen > 65536) throw "line too long";
						}
					}
				}
			} catch (e:Dynamic) {}
			if (myGen == gen) queue.add({gen: myGen, msg: {t: "_closed"}});
		});
	}

	public function disconnect():Void {
		gen++;
		status = Disconnected;
		myId = 0;
		myName = "";
		room = null;
		lobbies = [];
		serverOffset = 0;
		samples = [];
		var s = socket;
		socket = null;
		if (s != null) {
			try s.shutdown(true, true) catch (_) {}
			try s.close() catch (_) {}
		}
		while (queue.pop(false) != null) {}
	}

	/** Sends a message. Returns false if we're not connected. */
	public function send(obj:Dynamic):Bool {
		if (socket == null || status == Disconnected) return false;
		try {
			socket.output.writeString(Json.stringify(obj) + "\n");
			return true;
		} catch (e) {
			queue.add({gen: gen, msg: {t: "_closed"}});
			return false;
		}
	}

	// ------------------------------------------------------------ per-frame

	function pump():Void {
		var item:Dynamic;
		while ((item = queue.pop(false)) != null) {
			if (item.gen != gen) continue;
			process(item.msg);
		}

		if (status == Connected) {
			pingTimer -= FlxG.elapsed;
			if (pingTimer <= 0) {
				pingTimer = quickPings > 0 ? 0.15 : 2;
				if (quickPings > 0) quickPings--;
				send({t: "ping", c: nowMs(), p: Math.round(rtt)});
			}
		}
	}

	function process(m:Dynamic):Void {
		switch (m.t) {
			case "_fail":
				status = Disconnected;
				lastError = m.msg;
			case "_closed":
				if (status == Disconnected) return;
				status = Disconnected;
				if (lastError == null) lastError = "Connection to the server was lost.";
				room = null;
			case "welcome":
				status = Connected;
				lastError = null;
				myId = m.id;
				myName = m.name;
				quickPings = 8;
				pingTimer = 0;
			case "pong":
				onPong(m.c, m.s);
			case "room":
				room = cast m;
			case "lobbies":
				// only sent while we're not inside a lobby
				lobbies = m.lobbies;
				room = null;
			case "error":
				// fatal errors are followed by the server closing the connection; keep the reason for the UI.
				// (a rejected request like a wrong lobby password leaves the connection open)
				if (m.fatal == true) lastError = m.msg;
		}
		onMessage.dispatch(m);
	}

	function onPong(sent:Float, serverTime:Float):Void {
		var t = nowMs();
		rtt = t - sent;
		// Assume the reply took half the round trip; keep the sample with the smallest RTT (most accurate).
		samples.push({rtt: rtt, offset: serverTime + rtt * 0.5 - t});
		if (samples.length > 10) samples.shift();
		var best = samples[0];
		for (s in samples) if (s.rtt < best.rtt) best = s;
		serverOffset = best.offset;
	}

	// ------------------------------------------------------------ lobby actions

	/** Opens a new lobby (titled after our current mod). Optional password. The server answers with `joined` + a `room` snapshot. */
	public function createLobby(password:String):Void
		send({t: "create", password: password, mod: currentMod()});

	public function joinLobby(id:Int, password:String):Void
		send({t: "join", id: id, password: password, mod: currentMod()});

	/** Back to the lobby list without disconnecting (also how you forfeit a match). */
	public function leaveLobby():Void {
		send({t: "leave_lobby"});
		room = null;
	}

	public function refreshLobbies():Void
		send({t: "lobbies"});

	// ------------------------------------------------------------ room helpers

	public function me():Null<MPPlayer> {
		if (room == null) return null;
		for (p in room.players) if (p.id == myId) return p;
		return null;
	}

	public function opponent():Null<MPPlayer> {
		if (room == null) return null;
		for (p in room.players) if (p.id != myId) return p;
		return null;
	}

	public inline function isHost():Bool
		return room != null && room.host == myId;

	// ------------------------------------------------------------ song verification

	static function songKey(name:String, diff:String, variant:Null<String>):String
		return name + "|" + diff + "|" + (variant == null ? "" : variant);

	/**
	 * Fingerprint of a chart (note counts/timings). Both players must have the same one, otherwise their
	 * notes wouldn't line up. Returns null if the chart doesn't exist in the currently loaded mod.
	 */
	public static function chartHash(name:String, diff:String, variant:Null<String>):Null<String> {
		var key = songKey(name, diff, variant);
		if (chartHashCache.exists(key)) return chartHashCache.get(key);

		var result:String = null;
		try {
			if (Assets.exists(Paths.chart(name, diff, variant))) {
				var chart = Chart.parse(name, diff, variant);
				var sb = new StringBuf();
				for (sl in chart.strumLines) {
					var count = 0, sumTime = 0.0, sumId = 0, sumLen = 0.0;
					if (sl.notes != null) for (n in sl.notes) {
						count++;
						sumTime += n.time;
						sumId += n.id;
						sumLen += Math.isNaN(n.sLen) ? 0 : n.sLen;
					}
					sb.add('${sl.type}:$count:${Math.round(sumTime)}:$sumId:${Math.round(sumLen)};');
				}
				result = Md5.encode(sb.toString());
			}
		} catch (e) {}
		chartHashCache.set(key, result);
		return result;
	}

	/** Returns null if we have the exact same chart as the one picked, otherwise a message explaining why not. */
	public static function verifySong(song:MPSong):Null<String> {
		var mine = chartHash(song.name, song.diff, song.variant);
		if (mine == null) return 'You don\'t have "${song.display}" (${song.diff}). Both players need the same mod.';
		if (song.hash != null && song.hash != "" && song.hash != mine) return 'Your chart for "${song.display}" (${song.diff}) is different from the other player\'s. Are you on the same mod version?';
		return null;
	}
}
