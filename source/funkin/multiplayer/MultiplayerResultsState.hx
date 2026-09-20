package funkin.multiplayer;

import funkin.backend.FunkinText;
import funkin.multiplayer.MultiplayerClient.MPStatus;

/**
 * Shown after the song: both players' score, accuracy, misses, max combo and hit breakdown side by side.
 * Waits for the opponent to finish (the server sends both players' final numbers once both are done).
 */
class MultiplayerResultsState extends MPScreen {
	static final HIT_ORDER:Array<String> = ["sick", "good", "bad", "shit"];

	var headers:Array<FunkinText> = [];
	var bodies:Array<FunkinText> = [];
	var winnerText:FunkinText;
	var shown:Bool = false; // final numbers are on screen

	override function screenTitle():String
		return "RESULTS";

	override function create() {
		super.create();

		for (i in 0...2) {
			var x = 130 + i * 530;
			panel(x, 150, 490, 380, 0xFF000000, 0.55);
			headers.push(label(x + 16, 160, 458, "", 32, MPColor.ACCENT));
			bodies.push(label(x + 16, 214, 458, "", 26));
		}
		winnerText = label(0, 96, FlxG.width, "", 30, MPColor.INFO, CENTER);

		label(0, FlxG.height - 42, FlxG.width, "ENTER: back to lobby      ESC: leave lobby", 18, MPColor.DIM, CENTER);

		setStatus("Waiting for your opponent to finish...", MPColor.DIM);
		showCurrent();
	}

	override function update(elapsed:Float) {
		super.update(elapsed);

		if (!shown) {
			if (MultiplayerMatch.results != null) showFinal();
			else if (MultiplayerMatch.opponentLeft != null) showOpponentLeft();
			else showCurrent(); // opponent's live numbers while we wait
		}

		if (controls.ACCEPT && shown) backToLobby();
		if (controls.BACK) leave();
	}

	// ------------------------------------------------------------ rendering

	/** While waiting: our final numbers + the opponent's live ones. */
	function showCurrent():Void {
		var opp = client.opponent();
		render(0, myName(), MultiplayerMatch.mySide, MultiplayerMatch.myResult);
		var s = MultiplayerMatch.oppStats;
		render(1, opp != null ? opp.name : "Opponent", MultiplayerMatch.mySide == "left" ? "right" : "left", {
			score: s.score,
			misses: s.misses,
			accuracy: s.accuracy < 0 ? 0 : s.accuracy * 100,
			maxCombo: s.combo,
			hits: null
		});
	}

	function showFinal():Void {
		shown = true;
		var r:Dynamic = MultiplayerMatch.results.players;
		var mine:Dynamic = Reflect.field(r, Std.string(client.myId));
		var theirs:Dynamic = null;
		for (id in Reflect.fields(r)) if (id != Std.string(client.myId)) theirs = Reflect.field(r, id);

		if (mine == null || theirs == null) {
			setStatus("Results were incomplete.", MPColor.BAD);
			return;
		}

		render(0, mine.name, mine.side, mine);
		render(1, theirs.name, theirs.side, theirs);

		var mineWon = mine.score > theirs.score || (mine.score == theirs.score && mine.accuracy > theirs.accuracy);
		var draw = mine.score == theirs.score && mine.accuracy == theirs.accuracy;
		if (draw) {
			winnerText.text = "DRAW!";
			winnerText.color = MPColor.ACCENT;
		} else {
			winnerText.text = mineWon ? "YOU WIN!" : '${theirs.name} wins!';
			winnerText.color = mineWon ? MPColor.GOOD : MPColor.BAD;
		}
		setStatus("", MPColor.INFO);
		CoolUtil.playMenuSFX(CONFIRM, 0.8);
	}

	function showOpponentLeft():Void {
		shown = true;
		showCurrent();
		winnerText.text = '${MultiplayerMatch.opponentLeft} left the match - you win!';
		winnerText.color = MPColor.GOOD;
		setStatus("", MPColor.INFO);
	}

	function myName():String {
		var me = client.me();
		return me != null ? me.name : "You";
	}

	function render(col:Int, name:String, side:String, r:Dynamic):Void {
		headers[col].text = '$name  (${side == null ? "?" : side})';
		if (r == null) {
			bodies[col].text = "-";
			return;
		}
		var lines = [
			'Score       ${r.score}',
			'Accuracy    ${CoolUtil.quantize(r.accuracy, 100)}%',
			'Misses      ${r.misses}',
			'Max combo   ${r.maxCombo}'
		];
		if (r.hits != null) {
			lines.push("");
			var keys = Reflect.fields(r.hits);
			keys.sort(function(a, b) {
				var ia = HIT_ORDER.indexOf(a), ib = HIT_ORDER.indexOf(b);
				if (ia == -1) ia = 99;
				if (ib == -1) ib = 99;
				return ia != ib ? ia - ib : (a < b ? -1 : 1);
			});
			for (k in keys) {
				var nice = k.substr(0, 1).toUpperCase() + k.substr(1);
				lines.push(nice.rpad(" ", 12) + Std.string(Reflect.field(r.hits, k)));
			}
		}
		bodies[col].text = lines.join("\n");
	}

	// ------------------------------------------------------------ navigation

	function backToLobby():Void {
		MultiplayerMatch.end();
		if (client.status == MPStatus.Connected) FlxG.switchState(new MultiplayerLobbyState());
		else FlxG.switchState(new MultiplayerMenuState());
	}

	function leave():Void {
		client.leaveLobby();
		MultiplayerMatch.end();
		FlxG.switchState(new MultiplayerBrowserState());
	}
}
