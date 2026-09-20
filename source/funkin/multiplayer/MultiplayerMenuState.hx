package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.multiplayer.MultiplayerClient.MPStatus;

/**
 * "Multiplayer" entry point: enter your username and the server address (plus the server password if
 * it has one) and connect. You then land in the lobby browser.
 */
class MultiplayerMenuState extends MPScreen {
	// field indexes
	static inline final F_NAME:Int = 0;
	static inline final F_SERVER:Int = 1;
	static inline final F_PASS:Int = 2;
	static inline final BTN_CONNECT:Int = 3;
	static inline final FIELDS:Int = 3;

	static final LABELS:Array<String> = ["Your username", "Server address  (ip or ip:port)", "Server password  (optional)"];
	static final MAX_LEN:Array<Int> = [20, 80, 40];

	var values:Array<String> = ["", "", ""];
	var boxes:Array<FlxSprite> = [];
	var texts:Array<FunkinText> = [];
	var button:FlxSprite;
	var buttonText:FunkinText;
	var focus:Int = 0;

	var input:MPTextInput = new MPTextInput();
	var connecting:Bool = false;

	override function screenTitle():String
		return "MULTIPLAYER";

	/**
	 * Called every frame from `Main.onUpdate`. Opens the multiplayer menu on F6 from anywhere (for mods whose
	 * main menu has no Multiplayer entry), except while playing
	 * a song, in the editors, in the multiplayer screens themselves, or while a substate (pause menu,
	 * keybind rebinding, transition...) is open.
	 */
	public static function checkHotkey():Void {
		if (!FlxG.keys.justPressed.F6 || MultiplayerMatch.active) return;
		var state = FlxG.state;
		if (state == null || state.subState != null || !(state is MusicBeatState) || state is PlayState) return;
		var name = Type.getClassName(Type.getClass(state));
		if (StringTools.startsWith(name, "funkin.editors.") || StringTools.startsWith(name, "funkin.multiplayer.")) return;
		CoolUtil.playMenuSFX(CONFIRM, 0.7);
		FlxG.switchState(new MultiplayerMenuState());
	}

	override function create() {
		super.create();
		MultiplayerMatch.end(); // make sure PlayState behaves normally again
		MultiplayerMatch.init();

		loadSaved();

		var boxX = (FlxG.width - 600) / 2;
		for (i in 0...FIELDS) {
			var y = 130 + i * 100;
			label(boxX, y, 600, LABELS[i], 20, MPColor.DIM);
			boxes.push(panel(boxX, y + 30, 600, 46, 0xFF000000, 0.6));
			texts.push(label(boxX + 12, y + 38, 576, "", 26));
		}

		var by = 130 + FIELDS * 100 + 6;
		button = panel(boxX + 150, by, 300, 52, 0xFF000000, 0.6);
		buttonText = label(boxX + 150, by + 10, 300, "CONNECT", 28, MPColor.INFO, CENTER);

		label(0, FlxG.height - 48, FlxG.width, "UP / DOWN: choose      ENTER: next / connect      ESC: back      CTRL+V: paste", 18, MPColor.DIM, CENTER);

		if (client.lastError != null) setStatus(client.lastError, MPColor.BAD);
		if (client.status != MPStatus.Disconnected) client.disconnect();

		input.onChange = onInputChanged;
		focusField(focus);
		refresh();
	}

	override function destroy() {
		input.destroy();
		super.destroy();
	}

	function loadSaved() {
		var d:Dynamic = FlxG.save.data;
		values[F_NAME] = d.mpName != null ? d.mpName : "";
		values[F_SERVER] = d.mpServer != null ? d.mpServer : "";
		values[F_PASS] = ""; // passwords are never stored
		if (values[F_NAME] == "") values[F_NAME] = "Player";
		// first time: start on the server address, since that's the one thing we can't guess
		focus = values[F_SERVER] == "" ? F_SERVER : BTN_CONNECT;
	}

	function save() {
		var d:Dynamic = FlxG.save.data;
		d.mpName = values[F_NAME];
		d.mpServer = values[F_SERVER];
		FlxG.save.flush();
	}

	function focusField(i:Int) {
		focus = i;
		input.enabled = i < FIELDS && !connecting;
		if (i < FIELDS) {
			input.maxLen = MAX_LEN[i];
			input.value = values[i];
		}
	}

	function onInputChanged() {
		if (focus < FIELDS) values[focus] = input.value;
	}

	function refresh() {
		for (i in 0...FIELDS) {
			var shown = i == F_PASS ? [for (_ in 0...values[i].length) "*"].join("") : values[i];
			// blinking caret on the focused field
			var caret = (i == focus && !connecting && (FlxG.game.ticks % 1000) < 500) ? "|" : "";
			texts[i].text = shown + caret;
			boxes[i].alpha = i == focus ? 0.85 : 0.5;
		}
		button.alpha = focus == BTN_CONNECT ? 0.85 : 0.5;
		buttonText.color = focus == BTN_CONNECT ? MPColor.ACCENT : MPColor.INFO;
		buttonText.text = connecting ? "CONNECTING..." : "CONNECT";
	}

	override function update(elapsed:Float) {
		super.update(elapsed);
		input.update(elapsed);
		refresh();

		var k = FlxG.keys;
		if (k.justPressed.ESCAPE) {
			if (connecting) cancelConnect();
			else goToMainMenu();
			return;
		}
		if (connecting) return;

		if (k.justPressed.DOWN || (k.justPressed.TAB && !k.pressed.SHIFT)) changeFocus(1);
		else if (k.justPressed.UP || (k.justPressed.TAB && k.pressed.SHIFT)) changeFocus(-1);

		if (k.justPressed.ENTER) {
			if (focus < FIELDS - 1) changeFocus(1);
			else tryConnect();
		}

		if (FlxG.mouse.justPressed) {
			for (i in 0...FIELDS) if (FlxG.mouse.overlaps(boxes[i])) focusField(i);
			if (FlxG.mouse.overlaps(button)) tryConnect();
		}
	}

	function changeFocus(d:Int) {
		focusField(FlxMath.wrap(focus + d, 0, BTN_CONNECT));
		CoolUtil.playMenuSFX(SCROLL, 0.5);
	}

	function parseServer():Null<{host:String, port:Int}> {
		var s = StringTools.trim(values[F_SERVER]);
		if (s == "") return null;
		var host = s, port = MultiplayerClient.DEFAULT_PORT;
		var colon = s.lastIndexOf(":");
		if (colon > 0 && s.indexOf(":") == colon) { // "host:port" (a bare IPv6 address has several colons, leave those alone)
			host = s.substr(0, colon);
			var p = Std.parseInt(s.substr(colon + 1));
			if (p == null || p < 1 || p > 65535) return null;
			port = p;
		}
		return {host: host, port: port};
	}

	function tryConnect() {
		var server = parseServer();
		if (server == null) {
			setStatus("Enter the server address, like 203.0.113.5 or myhome.duckdns.org:7777", MPColor.BAD);
			focusField(F_SERVER);
			return;
		}
		var name = StringTools.trim(values[F_NAME]);
		if (name == "") name = "Player";

		save();
		connecting = true;
		input.enabled = false;
		setStatus('Connecting to ${server.host}:${server.port} ...', MPColor.INFO);
		CoolUtil.playMenuSFX(CONFIRM, 0.7);
		client.connect(server.host, server.port, name, values[F_PASS]);
	}

	function cancelConnect() {
		client.disconnect();
		connecting = false;
		setStatus("Cancelled.", MPColor.DIM);
		focusField(focus);
	}

	override function handleMessage(m:Dynamic) {
		switch (m.t) {
			case "welcome":
				connecting = false;
				FlxG.switchState(new MultiplayerBrowserState());
			case "_fail", "_closed", "error":
				if (!connecting) return;
				connecting = false;
				setStatus(client.lastError != null ? client.lastError : "Could not connect.", MPColor.BAD);
				focusField(focus);
		}
	}
}
